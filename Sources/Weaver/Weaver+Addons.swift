// Weaver+Addons.swift

import Foundation
import os

// MARK: - ==================== Addon Activation ====================

/// 고급 캐시 및 메트릭 기능을 활성화하기 위해 `WeaverBuilder`를 확장합니다.
extension WeaverBuilder {
    /// 고급 캐시 시스템을 활성화합니다.
    ///
    /// 이 메서드를 호출하면, 컨테이너는 TTL, LRU/FIFO 퇴출 정책 등을 지원하는
    /// `DefaultCacheManager`를 사용하게 됩니다.
    /// - Parameter policy: 캐시의 최대 크기, TTL, 퇴출 정책 등을 담은 객체입니다. 기본값은 `.default`.
    /// - Returns: 체이닝을 위해 빌더 자신(`Self`)을 반환합니다.
    @discardableResult
    public func enableAdvancedCaching(policy: CachePolicy = .default) -> Self {
        self.configuration.cachePolicy = policy
        return setCacheManagerFactory { cachePolicy, logger in
            DefaultCacheManager(policy: policy, logger: logger)
        }
    }
    
    /// 메트릭 수집 기능을 활성화합니다.
    ///
    /// 이 메서드를 호출하면, 컨테이너는 의존성 해결 시간, 캐시 히트율 등의
    /// 상세 정보를 수집하는 `DefaultMetricsCollector`를 사용하게 됩니다.
    /// - Returns: 체이닝을 위해 빌더 자신(`Self`)을 반환합니다.
    @discardableResult
    public func enableMetricsCollection() -> Self {
        return setMetricsCollectorFactory {
            DefaultMetricsCollector()
        }
    }
}


// MARK: - ==================== Dependency Graph Feature ====================

/// 의존성 그래프 기능을 활성화하기 위해 `WeaverContainer`를 확장합니다.
extension WeaverContainer {
    /// 등록된 의존성 정보를 바탕으로 시각화할 수 있는 그래프 객체를 반환합니다.
    ///
    /// 이 기능은 디버깅 목적으로 의존성 관계를 파악하는 데 유용합니다.
    public func getDependencyGraph() -> DependencyGraph {
        return DependencyGraph(registrations: registrations)
    }
}

/// 의존성 그래프를 표현하고, DOT 언어 형식의 문자열로 생성하는 구조체입니다.
public struct DependencyGraph: Sendable {
    private let registrations: [AnyDependencyKey: DependencyRegistration]
    
    internal init(registrations: [AnyDependencyKey: DependencyRegistration]) {
        self.registrations = registrations
    }
    
    /// Graphviz 등에서 시각화할 수 있는 DOT 형식의 문자열을 생성합니다.
    /// - Returns: DOT 언어 형식의 그래프 정의 문자열.
    public func generateDotGraph() -> String {
        var dot = "digraph Dependencies {\n"
        dot += "  rankdir=TB;\n"
        dot += "  node [shape=box, style=rounded];\n"
        registrations.forEach { key, registration in
            let color: String = switch registration.scope {
            case .container: "lightgreen"
            case .cached: "khaki"
            case .transient: "lightblue"
            }
            dot += "  \"\(key.description)\" [fillcolor=\(color), style=filled];\n"
        }
        dot += "}"
        return dot
    }
}

// MARK: - ==================== Advanced Caching Feature ====================

/// 캐시 퇴출 정책을 정의합니다.
public enum EvictionPolicy: Sendable {
    /// 가장 최근에 사용되지 않은 항목을 먼저 제거합니다 (Least Recently Used).
    case lru
    /// 가장 먼저 추가된 항목을 먼저 제거합니다 (First-In, First-Out).
    case fifo
}

/// 고급 캐시의 동작을 정의하는 정책 구조체입니다.
public struct CachePolicy: Sendable {
    /// 캐시에 저장할 수 있는 최대 인스턴스 수.
    public let maxSize: Int
    /// 캐시된 각 인스턴스의 생존 시간 (Time To Live). 초 단위.
    public let ttl: TimeInterval
    /// 캐시가 가득 찼을 때 적용할 퇴출 정책.
    public let evictionPolicy: EvictionPolicy
    
    public init(maxSize: Int = 100, ttl: TimeInterval = 300, evictionPolicy: EvictionPolicy = .lru) {
        self.maxSize = maxSize
        self.ttl = ttl
        self.evictionPolicy = evictionPolicy
    }
    
    /// 기본 캐시 정책 (maxSize: 100, ttl: 300초, eviction: lru).
    public static let `default` = CachePolicy()
}

/// 고급 캐싱 기능을 제공하는 기본 캐시 매니저 액터입니다.
actor DefaultCacheManager: CacheManaging {
    // MARK: - Properties
    private let policy: CachePolicy
    private let logger: WeaverLogger?
    private var cache: [AnyDependencyKey: CacheEntry] = [:]
    private let accessList = DoublyLinkedList()
    private var expirationHeap = PriorityQueue<ExpirationEntry>()
    private let memoryMonitor = MemoryMonitor()
    private var cacheHits = 0
    private var cacheMisses = 0
    
    // MARK: - Initialization
    init(policy: CachePolicy, logger: WeaverLogger?) {
        self.policy = policy
        self.logger = logger
        Task { await self.memoryMonitor.start() }
    }
    
    // MARK: - Public API
    func clear() async {
        await memoryMonitor.stop()
        cache.removeAll()
        accessList.clear()
        expirationHeap.clear()
        cacheHits = 0
        cacheMisses = 0
    }
    
    func getOrCreateInstance<T: Sendable>(key: AnyDependencyKey, factory: @Sendable @escaping () async throws -> T) async throws -> (value: T, isHit: Bool) {
        // 메모리 압박 상황 처리
        if await memoryMonitor.isUnderPressure {
            await logger?.log(message: "⚠️ 경고: 메모리 압박 감지. 캐시의 25%를 제거합니다.", level: .default)
            evict(count: cache.count / 4)
        }
        
        // 만료된 항목 제거
        evictExpiredEntries()
        
        // 캐시에서 인스턴스 조회
        if let entry = cache[key], let value = entry.value as? T {
            if policy.evictionPolicy == .lru {
                accessList.moveToFront(key: key)
            }
            cacheHits += 1
            return (value, true)
        }
        
        // 캐시 미스: 새로운 인스턴스 생성
        cacheMisses += 1
        let instance = try await factory()
        addInstanceToCache(instance, forKey: key)
        return (instance, false)
    }
    
    func getMetrics() -> (hits: Int, misses: Int) {
        return (cacheHits, cacheMisses)
    }
    
    // MARK: - Internal Cache Management
    private func addInstanceToCache<T: Sendable>(_ instance: T, forKey key: AnyDependencyKey) {
        ensureCacheCapacity()
        
        let entry = CacheEntry(value: instance, ttl: policy.ttl)
        cache[key] = entry
        
        if policy.evictionPolicy == .lru {
            accessList.add(key)
        }
        expirationHeap.enqueue(ExpirationEntry(key: key, expirationDate: entry.expirationDate, creationDate: entry.createdAt))
    }
    
    private func evictExpiredEntries() {
        while let nextToExpire = expirationHeap.peek(), nextToExpire.expirationDate <= Date() {
            guard let expiredHeapEntry = expirationHeap.dequeue() else { continue }
            if let cachedEntry = cache[expiredHeapEntry.key], cachedEntry.createdAt == expiredHeapEntry.creationDate {
                removeFromCache(key: expiredHeapEntry.key)
            }
        }
    }
    
    private func ensureCacheCapacity() {
        while cache.count >= policy.maxSize {
            evict()
        }
    }
    
    private func evict(count: Int = 1) {
        for _ in 0..<count {
            guard !cache.isEmpty else { break }
            switch policy.evictionPolicy {
            case .lru:
                if let key = accessList.removeTail() { removeFromCache(key: key) }
            case .fifo:
                if let key = cache.min(by: { $0.value.createdAt < $1.value.createdAt })?.key { removeFromCache(key: key) }
            }
        }
    }
    
    private func removeFromCache(key: AnyDependencyKey) {
        if cache.removeValue(forKey: key) != nil {
            if policy.evictionPolicy == .lru {
                accessList.remove(key: key)
            }
        }
    }
}

/// 시스템 메모리 압박 이벤트를 감지하는 액터입니다.
private actor MemoryMonitor {
    // MARK: - Properties
    private var source: DispatchSourceMemoryPressure?
    private(set) var isUnderPressure = false
    
    private static let memoryPressureCooldownNanoseconds: UInt64 = 30_000_000_000 // 30 seconds
    
    // MARK: - Public API
    func start() {
        guard source == nil else { return }
        let queue = DispatchQueue(label: "com.weaver.memorymonitor")
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: queue)
        
        source?.setEventHandler(handler: { @Sendable [weak self] in
            Task {
                await self?.handleMemoryPressure()
            }
        })
        source?.resume()
    }
    
    func stop() {
        source?.cancel()
        source = nil
    }
    
    // MARK: - Internal Logic
    private func handleMemoryPressure() {
        isUnderPressure = true
        Task {
            try? await Task.sleep(nanoseconds: Self.memoryPressureCooldownNanoseconds)
            self.isUnderPressure = false
        }
    }
}

// MARK: - ==================== Advanced Metrics Feature ====================

/// 상세한 메트릭을 수집하는 기본 구현체 액터입니다.
actor DefaultMetricsCollector: MetricsCollecting {
    private var totalResolutions = 0
    private var failedResolutions = 0
    private var totalDuration: TimeInterval = 0
    
    func recordResolution(duration: TimeInterval) {
        totalResolutions += 1
        totalDuration += duration
    }
    
    func recordFailure() {
        failedResolutions += 1
    }
    
    func recordCache(hit: Bool) { /* Caching metrics are handled by CacheManager */ }
    
    func getMetrics(cacheHits: Int, cacheMisses: Int) async -> ResolutionMetrics {
        ResolutionMetrics(
            totalResolutions: totalResolutions,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses,
            averageResolutionTime: totalResolutions > 0 ? totalDuration / Double(totalResolutions) : 0,
            failedResolutions: failedResolutions
        )
    }
}


// MARK: - ==================== Caching Data Structures ====================

private struct CacheEntry: Sendable {
    let value: any Sendable
    let createdAt: Date
    let expirationDate: Date
    
    init(value: any Sendable, ttl: TimeInterval) {
        let now = Date()
        self.value = value
        self.createdAt = now
        self.expirationDate = now.addingTimeInterval(ttl)
    }
}

private struct ExpirationEntry: Comparable, Sendable {
    let key: AnyDependencyKey
    let expirationDate: Date
    let creationDate: Date
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.expirationDate < rhs.expirationDate }
}

/// LRU 정책을 위한 이중 연결 리스트입니다.
private final class DoublyLinkedList {
    private final class ListNode {
        let key: AnyDependencyKey
        var prev: ListNode?
        var next: ListNode?
        init(key: AnyDependencyKey) { self.key = key }
    }
    
    private var head: ListNode
    private var tail: ListNode
    private var nodes: [AnyDependencyKey: ListNode] = [:]
    
    private struct DummyKey: DependencyKey { static let defaultValue: String = "" }
    
    init() {
        let dummyKey = AnyDependencyKey(DummyKey.self)
        self.head = ListNode(key: dummyKey)
        self.tail = ListNode(key: dummyKey)
        head.next = tail
        tail.prev = head
    }
    
    func add(_ key: AnyDependencyKey) {
        if let existingNode = nodes[key] {
            moveToFront(node: existingNode)
            return
        }
        let node = ListNode(key: key)
        nodes[key] = node
        addToFront(node: node)
    }
    
    func moveToFront(key: AnyDependencyKey) {
        guard let node = nodes[key] else { return }
        moveToFront(node: node)
    }
    
    func remove(key: AnyDependencyKey) {
        guard let node = nodes.removeValue(forKey: key) else { return }
        remove(node: node)
    }
    
    func removeTail() -> AnyDependencyKey? {
        guard let lastNode = tail.prev, lastNode !== head else { return nil }
        remove(node: lastNode)
        nodes.removeValue(forKey: lastNode.key)
        return lastNode.key
    }
    
    func clear() {
        head.next = tail
        tail.prev = head
        nodes.removeAll()
    }
    
    private func moveToFront(node: ListNode) {
        remove(node: node)
        addToFront(node: node)
    }
    
    private func remove(node: ListNode) {
        node.prev?.next = node.next
        node.next?.prev = node.prev
    }
    
    private func addToFront(node: ListNode) {
        node.next = head.next
        node.prev = head
        head.next?.prev = node
        head.next = node
    }
}

/// 최소 힙(Min-Heap)으로 구현된 우선순위 큐입니다.
private struct PriorityQueue<Element: Comparable & Sendable> {
    private var elements: [Element] = []
    
    var isEmpty: Bool { elements.isEmpty }
    
    func peek() -> Element? { elements.first }
    
    mutating func enqueue(_ element: Element) {
        elements.append(element)
        siftUp(from: elements.count - 1)
    }
    
    mutating func dequeue() -> Element? {
        guard !isEmpty else { return nil }
        elements.swapAt(0, elements.count - 1)
        let element = elements.removeLast()
        siftDown(from: 0)
        return element
    }
    
    mutating func clear() { elements.removeAll() }
    
    private func parentIndex(of i: Int) -> Int { (i - 1) / 2 }
    private func leftChildIndex(of i: Int) -> Int { 2 * i + 1 }
    private func rightChildIndex(of i: Int) -> Int { 2 * i + 2 }
    
    private mutating func siftUp(from index: Int) {
        var child = index
        var parent = parentIndex(of: child)
        while child > 0 && elements[child] < elements[parent] {
            elements.swapAt(child, parent)
            child = parent
            parent = parentIndex(of: child)
        }
    }
    
    private mutating func siftDown(from index: Int) {
        var parent = index
        while true {
            let left = leftChildIndex(of: parent)
            var candidate = parent
            if left < elements.count && elements[left] < elements[candidate] { candidate = left }
            let right = rightChildIndex(of: parent)
            if right < elements.count && elements[right] < elements[candidate] { candidate = right }
            if candidate == parent { return }
            elements.swapAt(parent, candidate)
            parent = candidate
        }
    }
}

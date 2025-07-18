// Weaver/Sources/Weaver/Weaver+Addons.swift

import Foundation
import os

// MARK: - ==================== Addon Activation ====================

/// 고급 캐시 및 메트릭 기능을 활성화하기 위해 `WeaverBuilder`를 확장합니다.
extension WeaverBuilder {
    /// 고급 캐시 시스템을 활성화합니다.
    @discardableResult
    public func enableAdvancedCaching(policy: CachePolicy = .default) -> Self {
        self.configuration.cachePolicy = policy
        return setCacheManagerFactory { cachePolicy, logger in
            DefaultCacheManager(policy: policy, logger: logger)
        }
    }
    
    /// 메트릭 수집 기능을 활성화합니다.
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
    
    /// Graphviz 등에서 시각화할 수 있는, 의존 관계가 포함된 DOT 형식의 문자열을 생성합니다.
    public func generateDotGraph() -> String {
        var dot = "digraph Dependencies {\n"
        dot += "  // Graph layout and style\n"
        dot += "  rankdir=TB;\n"
        dot += "  graph [splines=ortho, nodesep=0.8, ranksep=1.2];\n"
        dot += "  node [shape=box, style=\"rounded,filled\", fontname=\"Helvetica\", penwidth=1.5];\n"
        dot += "  edge [fontname=\"Helvetica\", fontsize=10, arrowsize=0.8];\n\n"

        // ✨ [로직 개선] 1. 조회용 맵 생성
        // 프로퍼티 이름(소문자)을 실제 노드 이름(Key 타입 이름)에 매핑합니다.
        // 예: "circulara" -> "CircularAKey"
        // 이 맵을 통해 `_serviceAKey` 같은 문자열에서 실제 대상 노드를 찾을 수 있습니다.
        registrations.values.forEach { registration in
            let sourceNodeName = registration.keyName.split(separator: ".").last.map(String.init) ?? registration.keyName
            
            registration.dependencies.forEach { dependencyDeclaration in
                if let dependencyRegistration = registrations.first(where: { $0.value.keyName == dependencyDeclaration }) {
                    let targetNodeName = dependencyRegistration.value.keyName.split(separator: ".").last.map(String.init) ?? dependencyRegistration.value.keyName
                    dot += "  \"\(sourceNodeName)\" -> \"\(targetNodeName)\";\n"
                } else {
                    print("Weaver Graph Warning: Could not find a matching node for dependency '\(dependencyDeclaration)' in '\(registration.keyName)'.")
                }
            }
        }
        dot += "}"
        return dot
    }
}

// MARK: - Private String Helper

/// 하위 버전 호환성을 위해 `removingsuffix` 대신 사용할 헬퍼 확장입니다.
private extension String {
    func strippingSuffix(_ suffix: String) -> String? {
        guard self.hasSuffix(suffix) else { return nil }
        return String(self.dropLast(suffix.count))
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
        // 개발 중 잘못된 설정값을 즉시 발견하여 런타임 오류를 방지합니다.
        precondition(maxSize > 0, "CachePolicy의 maxSize는 반드시 0보다 커야 합니다.")
        precondition(ttl > 0, "CachePolicy의 ttl은 반드시 0보다 커야 합니다.")

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
    let policy: CachePolicy
    private let logger: WeaverLogger?
    private var cache: [AnyDependencyKey: CacheEntry] = [:]
    private var ongoingCreations: [AnyDependencyKey: Task<any Sendable, Error>] = [:]
    /// LRU와 FIFO 정책 모두를 위한 퇴출 순서 추적기입니다.
    private let evictionOrderTracker = DoublyLinkedList()
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
        ongoingCreations.values.forEach { $0.cancel() }
        ongoingCreations.removeAll()
        evictionOrderTracker.clear()
        expirationHeap.clear()
        cacheHits = 0
        cacheMisses = 0
    }
    
    func taskForInstance<T: Sendable>(key: AnyDependencyKey, factory: @Sendable @escaping () async throws -> T) async -> (task: Task<any Sendable, Error>, isHit: Bool) {
        // 메모리 압박 상황 처리
        if await memoryMonitor.isUnderPressure {
            await logger?.log(message: "⚠️ 경고: 메모리 압박 감지. 캐시의 25%를 제거합니다.", level: .default)
            evict(count: cache.count / 4)
        }
        
        // 만료된 항목 제거
        evictExpiredEntries()
        
        // 1. 캐시에서 인스턴스 조회
        if let entry = cache[key], let value = entry.value as? T {
            if policy.evictionPolicy == .lru {
                // LRU 정책은 접근 시 순서를 갱신하여 가장 최근에 사용되었음을 표시합니다.
                evictionOrderTracker.moveToFront(key: key)
            }
            cacheHits += 1
            return (Task { value }, true)
        }

        // 2. 진행 중인 Task가 있는지 확인
        if let existingTask = ongoingCreations[key] {
            return (existingTask, false)
        }

        // 3. 새로운 Task 생성 및 등록
        cacheMisses += 1
        let newTask = Task<any Sendable, Error> {
            do {
                let instance = try await factory()
                addInstanceToCache(instance, forKey: key)
                await removeOngoingCreation(forKey: key)
                return instance
            } catch {
                await removeOngoingCreation(forKey: key)
                throw error
            }
        }
        ongoingCreations[key] = newTask
        return (newTask, false)
    }
    
    private func removeOngoingCreation(forKey key: AnyDependencyKey) async {
        ongoingCreations.removeValue(forKey: key)
    }
    
    func getMetrics() -> (hits: Int, misses: Int) {
        return (cacheHits, cacheMisses)
    }
    
    // MARK: - Internal Cache Management
    private func addInstanceToCache<T: Sendable>(_ instance: T, forKey key: AnyDependencyKey) {
        ensureCacheCapacity()
        
        let entry = CacheEntry(value: instance, ttl: policy.ttl)
        cache[key] = entry
        
        // LRU와 FIFO 모두 퇴출 순서 추적을 위해 리스트에 추가합니다.
        // LRU는 접근 시 순서가 갱신되고, FIFO는 추가된 순서가 그대로 유지됩니다.
        evictionOrderTracker.add(key)
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
            // LRU와 FIFO 정책 모두 가장 오래된 항목(리스트의 꼬리)을 제거합니다.
            if let keyToEvict = evictionOrderTracker.removeTail() {
                removeFromCache(key: keyToEvict)
            }
        }
    }
    
    private func removeFromCache(key: AnyDependencyKey) {
        if cache.removeValue(forKey: key) != nil {
            // 캐시에서 제거되면 순서 추적 리스트에서도 일관되게 제거합니다.
            evictionOrderTracker.remove(key: key)
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
            failedResolutions: failedResolutions,
            weakReferences: WeakReferenceMetrics(totalWeakReferences: 0, aliveWeakReferences: 0, deallocatedWeakReferences: 0)
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

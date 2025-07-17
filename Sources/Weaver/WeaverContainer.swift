// Weaver/Sources/Weaver/WeaverContainer.swift

import Foundation
import os

public actor WeaverContainer: Resolver {
    // MARK: - Properties
    
    public let registrations: [AnyDependencyKey: DependencyRegistration]
    nonisolated public let logger: WeaverLogger?
    
    private let parent: WeaverContainer?
    private let disposableManager: DisposableManager
    private let cacheManager: CacheManaging
    private let metricsCollector: MetricsCollecting
    
    // MARK: - Container Scope State
    private var containerCache: [AnyDependencyKey: any Sendable] = [:]
    private var ongoingCreations: [AnyDependencyKey: Task<any Sendable, Error>] = [:]
    
    /// `.weak` 스코프 의존성을 추적하기 위한 저장소입니다.
    /// `WeakReferenceTracker` 액터를 통해 스레드로부터 안전하게 상태를 관리합니다.
    private var weakReferences: [AnyDependencyKey: WeakReferenceTracker] = [:]
    
    private var shutdownTask: Task<Void, Never>?
    @TaskLocal private static var resolutionStack: [ResolutionStackEntry] = []
    
    private struct ResolutionStackEntry: Hashable {
        let key: AnyDependencyKey
        let containerID: ObjectIdentifier
    }
    
    // MARK: - Initialization & Build
    
    public static func builder() -> WeaverBuilder { WeaverBuilder() }
    
    internal init(
        registrations: [AnyDependencyKey: DependencyRegistration],
        parent: WeaverContainer?,
        logger: WeaverLogger,
        cacheManager: CacheManaging,
        metricsCollector: MetricsCollecting
    ) {
        self.registrations = registrations
        self.parent = parent
        self.logger = logger
        self.disposableManager = DisposableManager(logger: logger)
        self.cacheManager = cacheManager
        self.metricsCollector = metricsCollector
    }
    
    /// `.eagerContainer` 스코프의 의존성들을 병렬로 미리 초기화하고 진행률을 알립니다.
    internal func warmUp(onProgress: @escaping @Sendable (Double) -> Void) async {
        let eagerKeys = registrations.filter { $1.scope == .eagerContainer }.map { $0.key }
        guard !eagerKeys.isEmpty else {
            onProgress(1.0)
            return
        }
        
        await logger?.log(message: "Warming up \(eagerKeys.count) eager dependencies...", level: .debug)
        onProgress(0.0)
        
        let totalCount = eagerKeys.count
        let completedCount = AtomicInt(0)
        
        await withTaskGroup(of: Void.self) { group in
            for key in eagerKeys {
                group.addTask { [weak self] in
                    _ = try? await self?._findRegistration(for: key)
                    let newCount = completedCount.incrementAndGet()
                    let progress = Double(newCount) / Double(totalCount)
                    onProgress(progress)
                }
            }
        }
        
        await logger?.log(message: "Eager dependencies are ready.", level: .debug)
    }
    
    /// 컨테이너를 안전하게 종료하고 모든 관리 리소스를 해제합니다.
    public func shutdown() async {
        if let existingTask = shutdownTask {
            await existingTask.value
            return
        }
        
        let task = Task {
            await logger?.log(message: "Shutting down WeaverContainer.", level: .debug)
            
            await disposableManager.disposeAll()
            await cacheManager.clear()
            ongoingCreations.values.forEach { $0.cancel() }
            
            // 약한 참조 정리
            weakReferences.removeAll()
            containerCache.removeAll()
            ongoingCreations.removeAll()
        }
        self.shutdownTask = task
        await task.value
    }
    
    // MARK: - Public API
    
    public func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value {
        guard shutdownTask == nil else { throw WeaverError.shutdownInProgress }
        
        let key = AnyDependencyKey(keyType)
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            // 순환 참조 검사
            let currentEntry = ResolutionStackEntry(key: key, containerID: ObjectIdentifier(self))
            if Self.resolutionStack.contains(currentEntry) {
                let cycleMessage = (Self.resolutionStack.map { $0.key.description } + [key.description]).joined(separator: " -> ")
                await logger?.log(message: "순환 참조 감지: \(cycleMessage)", level: .fault)
                throw WeaverError.resolutionFailed(.circularDependency(path: cycleMessage))
            }
            
            let instance: any Sendable = try await Self.$resolutionStack.withValue(Self.resolutionStack + [currentEntry]) {
                try await _findRegistration(for: key)
            }
            
            guard let typedInstance = instance as? Key.Value else {
                throw WeaverError.resolutionFailed(.typeMismatch(expected: "\(Key.Value.self)", actual: "\(type(of: instance))", keyName: key.description))
            }
            
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            await metricsCollector.recordResolution(duration: duration)
            
            return typedInstance
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            await metricsCollector.recordResolution(duration: duration)
            await metricsCollector.recordFailure()
            throw error
        }
    }
    
    /// 현재 컨테이너를 부모로 하여, 새로운 모듈이 추가된 자식 컨테이너를 생성합니다.
    public func reconfigure(with modules: [Module]) async -> WeaverContainer {
        await logger?.log(
            message: "Reconfiguring container by creating a new child with \(modules.count) new module(s).",
            level: .debug
        )
        
        let builder = await WeaverContainer.builder()
            .withParent(self)
            .withLogger(self.logger ?? DefaultLogger())
            .withModules(modules)
        
        if let defaultCache = cacheManager as? DefaultCacheManager {
            let policy = registrations.values.first?.scope == .cached ? defaultCache.policy : .default
            _ = await builder.enableAdvancedCaching(policy: policy)
        }
        if metricsCollector is DefaultMetricsCollector {
            _ = await builder.enableMetricsCollection()
        }
        
        return await builder.build()
    }
    
    public func getMetrics() async -> ResolutionMetrics {
        let (hits, misses) = await cacheManager.getMetrics()
        let weakMetrics = await getWeakReferenceMetrics()
        let baseMetrics = await metricsCollector.getMetrics(cacheHits: hits, cacheMisses: misses)
        
        return ResolutionMetrics(
            totalResolutions: baseMetrics.totalResolutions,
            cacheHits: hits,
            cacheMisses: misses,
            averageResolutionTime: baseMetrics.averageResolutionTime,
            failedResolutions: baseMetrics.failedResolutions,
            weakReferences: weakMetrics
        )
    }
    
    /// 약한 참조 메트릭을 가져옵니다.
    private func getWeakReferenceMetrics() async -> WeakReferenceMetrics {
        var aliveCount = 0
        var totalCount = 0
        
        for (_, holder) in weakReferences {
            totalCount += 1
            if await holder.isAlive {
                aliveCount += 1
            }
        }
        
        let deallocatedCount = totalCount - aliveCount
        
        return WeakReferenceMetrics(
            totalWeakReferences: totalCount,
            aliveWeakReferences: aliveCount,
            deallocatedWeakReferences: deallocatedCount
        )
    }
    
    // MARK: - Internal Resolution Logic
    
    private func _findRegistration(for key: AnyDependencyKey) async throws -> any Sendable {
        guard let registration = registrations[key] else {
            if let parent {
                return try await parent._findRegistration(for: key)
            }
            throw WeaverError.resolutionFailed(.keyNotFound(keyName: key.description))
        }
        
        do {
            switch registration.scope {
            case .container, .eagerContainer:
                return try await getOrCreateContainerInstance(key: key, registration: registration)
            case .weak:
                return try await getOrCreateWeakInstance(key: key, registration: registration)
            case .cached:
                let (task, isHit) = await cacheManager.taskForInstance(key: key) {
                    try await registration.factory(self)
                }
                await metricsCollector.recordCache(hit: isHit)
                return try await task.value
            }
        } catch let error as WeaverError {
            throw error
        } catch {
            throw WeaverError.resolutionFailed(.factoryFailed(keyName: registration.keyName, underlying: error))
        }
    }
    
    // MARK: - Container Scope Helpers
    
    private func getOrCreateContainerInstance(key: AnyDependencyKey, registration: DependencyRegistration) async throws -> any Sendable {
        // 캐시 확인
        if let cachedValue = containerCache[key] {
            return cachedValue
        }
        
        // 진행 중인 생성 작업 확인
        if let task = ongoingCreations[key] {
            return try await task.value
        }
        
        // 인스턴스 생성 및 캐시
        return try await createAndCacheInstance(key: key, registration: registration)
    }
    
    // ✨ [핵심 개선] 약한 참조 인스턴스를 생성하고 관리하는 전용 메서드입니다.
    private func getOrCreateWeakInstance(key: AnyDependencyKey, registration: DependencyRegistration) async throws -> any Sendable {
        // 1. 기존 약한 참조 확인: `WeakReferenceTracker`를 통해 인스턴스가 메모리에 살아있는지 확인합니다.
        if let tracker = weakReferences[key] {
            if await tracker.isAlive, let value = await tracker.getValue() {
                await logger?.log(message: "Weak reference hit for \(key.description)", level: .debug)
                return value // 살아있으면 바로 반환합니다.
            }
        }
        
        // 2. 약한 참조가 해제된 경우 정리: `weakReferences` 딕셔너리에서 해당 항목을 명시적으로 제거하여
        //    메모리 누수를 방지하고 상태를 일관성 있게 관리합니다.
        if weakReferences[key] != nil {
            weakReferences.removeValue(forKey: key)
            await logger?.log(message: "Weak reference deallocated for \(key.description). Will create a new instance.", level: .debug)
        }
        
        // 3. 진행 중인 생성 작업 확인: 다른 스레드에서 이미 생성 중이라면 해당 Task의 결과를 기다립니다.
        if let task = ongoingCreations[key] {
            let instance = try await task.value
            try setupWeakReference(key: key, instance: instance)
            return instance
        }
        
        // 4. 새로운 약한 참조 인스턴스 생성: 위 모든 조건에 해당하지 않으면 새로운 인스턴스를 생성합니다.
        return try await createWeakInstance(key: key, registration: registration)
    }
    
    private func createWeakInstance(key: AnyDependencyKey, registration: DependencyRegistration) async throws -> any Sendable {
        let newTask = Task {
            try await registration.factory(self)
        }
        ongoingCreations[key] = newTask
        
        do {
            let instance = try await newTask.value
            try setupWeakReference(key: key, instance: instance) // 생성 후 약한 참조 추적기에 등록합니다.
            ongoingCreations.removeValue(forKey: key)
            
            if let disposable = instance as? Disposable {
                await disposableManager.add(disposable)
            }
            return instance
        } catch {
            ongoingCreations.removeValue(forKey: key) // 실패 시에도 반드시 제거합니다.
            throw error
        }
    }
    
    /// ✨ [핵심 개선] 생성된 인스턴스를 `WeakReferenceTracker`에 등록합니다.
    private func setupWeakReference(key: AnyDependencyKey, instance: any Sendable) throws {
        // `registerWeak` guarantees `instance` is a class (`AnyObject`).
        let object = instance as AnyObject

        // This is safe because `registerWeak` enforces `AnyObject & Sendable`.
        let sendableObject = unsafeBitCast(object, to: (any AnyObject & Sendable).self)

        // 약한 참조 추적기 생성 및 등록
        let tracker = WeakReferenceTracker(sendableObject)
        weakReferences[key] = tracker
    }
    
    private func createAndCacheInstance(key: AnyDependencyKey, registration: DependencyRegistration) async throws -> any Sendable {
        let newTask = Task {
            try await registration.factory(self)
        }
        ongoingCreations[key] = newTask
        
        do {
            let instance = try await newTask.value
            containerCache[key] = instance
            ongoingCreations.removeValue(forKey: key)
            
            if let disposable = instance as? Disposable {
                await disposableManager.add(disposable)
            }
            return instance
        } catch {
            ongoingCreations.removeValue(forKey: key)
            throw error
        }
    }
}

// MARK: - ==================== Swift 6 동시성 기반 약한 참조 시스템 ====================

/// Swift 6 동시성 환경에서 약한 참조를 안전하게 추적하는 액터
private actor WeakReferenceTracker: Sendable {
    private weak var _weakObject: (any AnyObject & Sendable)?
    private let creationTime: CFAbsoluteTime
    private let objectDescription: String
    
    init(_ object: any AnyObject & Sendable) {
        self._weakObject = object
        self.creationTime = CFAbsoluteTimeGetCurrent()
        self.objectDescription = String(describing: type(of: object))
    }
    
    /// 약한 참조가 아직 살아있는지 확인
    var isAlive: Bool {
        _weakObject != nil
    }
    
    /// 약한 참조 객체 반환 (nil이면 해제됨)
    func getValue() -> (any Sendable)? {
        _weakObject
    }
    
    /// 생성 이후 경과 시간
    var age: TimeInterval {
        CFAbsoluteTimeGetCurrent() - creationTime
    }
    
    /// 디버깅을 위한 설명
    var debugDescription: String {
        let status = isAlive ? "alive" : "deallocated"
        return "\(objectDescription) (\(status), age: \(String(format: "%.2f", age))s)"
    }
}

// MARK: - ==================== Models & Support Types ====================

/// 의존성의 생명주기를 정의하는 스코프 타입입니다.
public enum Scope: String, Sendable {
    case container
    case cached
    case eagerContainer
    case weak
}

/// `DependencyKey`의 타입 정보를 타입 소거 형태로 감싸는 구조체입니다.
public struct AnyDependencyKey: Hashable, CustomStringConvertible, Sendable {
    private let id: ObjectIdentifier
    private let name: String
    
    public init<Key: DependencyKey>(_ keyType: Key.Type) {
        self.id = ObjectIdentifier(keyType)
        self.name = String(describing: keyType)
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public var description: String { name }
}

/// 의존성 등록 정보를 담는 구조체입니다.
public struct DependencyRegistration: Sendable {
    public let scope: Scope
    public let factory: @Sendable (Resolver) async throws -> any Sendable
    public let keyName: String
    public let dependencies: [String]
}

/// 약한 참조 메트릭 정보
public struct WeakReferenceMetrics: Sendable {
    public let totalWeakReferences: Int
    public let aliveWeakReferences: Int
    public let deallocatedWeakReferences: Int
    
    public var deallocatedRate: Double {
        totalWeakReferences > 0 ? Double(deallocatedWeakReferences) / Double(totalWeakReferences) : 0
    }
}

/// 의존성 해결 통계 정보를 담는 구조체입니다.
public struct ResolutionMetrics: Sendable, CustomStringConvertible {
    public let totalResolutions: Int
    public let cacheHits: Int
    public let cacheMisses: Int
    public let averageResolutionTime: TimeInterval
    public let failedResolutions: Int
    public let weakReferences: WeakReferenceMetrics
    
    public var cacheHitRate: Double {
        (cacheHits + cacheMisses) > 0 ? Double(cacheHits) / Double(cacheHits + cacheMisses) : 0
    }
    
    public var successRate: Double {
        totalResolutions > 0 ? Double(totalResolutions - failedResolutions) / Double(totalResolutions) : 0
    }
    
    public var description: String {
        return """
        Resolution Metrics:
        - Total Resolutions: \(totalResolutions)
        - Success Rate: \(String(format: "%.1f%%", successRate * 100))
        - Failed Resolutions: \(failedResolutions)
        - Cache Hit Rate: \(String(format: "%.1f%%", cacheHitRate * 100)) (Hits: \(cacheHits), Misses: \(cacheMisses))
        - Avg. Resolution Time: \(String(format: "%.4fms", averageResolutionTime * 1000))
        - Weak References: \(weakReferences.aliveWeakReferences)/\(weakReferences.totalWeakReferences) alive (\(String(format: "%.1f%%", (1 - weakReferences.deallocatedRate) * 100)))
        """
    }
}

/// `WeaverContainer`의 내부 동작을 제어하는 설정 구조체입니다.
public struct ContainerConfiguration: Sendable {
    var cachePolicy: CachePolicy = .default
}

/// 메트릭 수집 기능이 비활성화되었을 때 사용되는 기본 구현체입니다.
final class DummyMetricsCollector: MetricsCollecting, Sendable {
    func recordResolution(duration: TimeInterval) async {}
    func recordFailure() async {}
    func recordCache(hit: Bool) async {}
    func getMetrics(cacheHits: Int, cacheMisses: Int) async -> ResolutionMetrics {
        return ResolutionMetrics(
            totalResolutions: 0,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses,
            averageResolutionTime: 0,
            failedResolutions: 0,
            weakReferences: WeakReferenceMetrics(
                totalWeakReferences: 0,
                aliveWeakReferences: 0,
                deallocatedWeakReferences: 0
            )
        )
    }
}

/// 캐시 기능이 비활성화되었을 때 사용되는 기본 구현체입니다.
final class DummyCacheManager: CacheManaging, Sendable {
    func taskForInstance<T: Sendable>(
        key: AnyDependencyKey,
        factory: @Sendable @escaping () async throws -> T
    ) async -> (task: Task<any Sendable, Error>, isHit: Bool) {
        return (Task { try await factory() }, false)
    }
    
    func getMetrics() async -> (hits: Int, misses: Int) {
        return (0, 0)
    }
    
    func clear() async {}
}

// MARK: - ==================== Internal Helpers ====================

/// `.container` 스코프이면서 `Disposable`을 채택한 인스턴스들의 생명주기를 관리하는 액터입니다.
internal actor DisposableManager: Sendable {
    private var instances: [any Disposable] = []
    private let logger: WeaverLogger?
    
    init(logger: WeaverLogger?) {
        self.logger = logger
    }
    
    func add(_ disposable: any Disposable) {
        instances.append(disposable)
    }
    
    func disposeAll() async {
        guard !instances.isEmpty else { return }
        
        await logger?.log(message: "Disposing \(instances.count) instances.", level: .debug)
        
        await withTaskGroup(of: Void.self) { group in
            for instance in instances {
                group.addTask {
                    await instance.dispose()
                }
            }
        }
        
        instances.removeAll()
    }
}

/// 동시성 환경에서 정수 값을 안전하게 조작하기 위한 헬퍼 클래스입니다.
private final class AtomicInt: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int
    
    init(_ value: Int = 0) {
        self.value = value
    }
    
    @discardableResult
    func incrementAndGet() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}


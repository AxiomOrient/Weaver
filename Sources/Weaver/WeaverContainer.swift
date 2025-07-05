// Weaver/Sources/Weaver/WeaverContainer.swift

import Foundation
import os

// MARK: - ==================== WeaverContainer ====================

/// 의존성을 관리하고 해결하는 핵심 DI 컨테이너 액터(Actor)입니다.
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
            onProgress(1.0) // 초기화할 대상이 없으면 즉시 100% 완료
            return
        }
        
        await logger?.log(message: "Warming up \(eagerKeys.count) eager dependencies...", level: .debug)
        onProgress(0.0) // 초기화 시작
        
        let totalCount = eagerKeys.count
        let completedCount = AtomicInt(0)
        
        await withTaskGroup(of: Void.self) { group in
            for key in eagerKeys {
                group.addTask {
                    _ = try? await self._findRegistration(for: key)
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
        }
        self.shutdownTask = task
        await task.value
        
        self.containerCache.removeAll()
        self.ongoingCreations.removeAll()
    }
    
    // MARK: - Public API
    
    public func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value {
        guard shutdownTask == nil else { throw WeaverError.shutdownInProgress }
        
        let key = AnyDependencyKey(keyType)
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            // 순환 참조 검사
            if Self.resolutionStack.contains(where: { $0.key == key && $0.containerID == ObjectIdentifier(self) }) {
                let cycleMessage = (Self.resolutionStack.map { $0.key.description } + [key.description]).joined(separator: " -> ")
                await logger?.log(message: "순환 참조 감지: \(cycleMessage)", level: .fault)
                throw WeaverError.resolutionFailed(.circularDependency(path: cycleMessage))
            }
            
            let instance: any Sendable = try await Self.$resolutionStack.withValue(Self.resolutionStack + [ResolutionStackEntry(key: key, containerID: ObjectIdentifier(self))]) {
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
    ///
    /// 이 메서드는 기존 컨테이너의 상태를 변경하지 않고(immutable), 확장된 새로운 컨테이너를 반환합니다.
    /// 이를 통해 앱 실행 중 동적으로 기능을 추가하거나 A/B 테스트 등을 위한 구성을 안전하게 만들 수 있습니다.
    ///
    /// - Parameter modules: 새로 추가하거나 교체할 로직을 담은 `Module`의 배열.
    /// - Returns: 현재 컨테이너를 부모로 가지는, 새롭게 설정된 `WeaverContainer` 인스턴스.
    public func reconfigure(with modules: [Module]) async -> WeaverContainer {
        await logger?.log(
            message: "Reconfiguring container by creating a new child with \(modules.count) new module(s).",
            level: .debug
        )
        
        // 새로운 빌더를 생성합니다.
        let builder = await WeaverContainer.builder()
        // ✨ 핵심: 현재 컨테이너(self)를 부모로 설정합니다.
            .withParent(self)
        // 기존 설정을 계승합니다 (Logger, Addons 등).
            .withLogger(self.logger ?? DefaultLogger())
        // 새 모듈들을 추가합니다.
            .withModules(modules)
        
        // 만약 현재 컨테이너가 고급 캐싱/메트릭을 사용 중이었다면, 새 컨테이너도 동일하게 설정합니다.
        if cacheManager is DefaultCacheManager {
            _ = await builder.enableAdvancedCaching(policy: self.registrations.values.first?.scope == .cached ? (cacheManager as! DefaultCacheManager).policy : .default) // 정책은 다시 설정해야 할 수 있음
        }
        if metricsCollector is DefaultMetricsCollector {
            _ = await builder.enableMetricsCollection()
        }
        
        // 새로운 자식 컨테이너를 빌드하여 반환합니다.
        return await builder.build()
    }
    
    public func getMetrics() async -> ResolutionMetrics {
        let (hits, misses) = await cacheManager.getMetrics()
        return await metricsCollector.getMetrics(cacheHits: hits, cacheMisses: misses)
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
            case .container, .eagerContainer, .weak:
                return try await getOrCreateContainerInstance(key: key, registration: registration)
            case .cached:
                let (task, isHit) = await cacheManager.taskForInstance(key: key) { try await registration.factory(self) }
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
        // 1. 캐시 확인
        if let cachedValue = containerCache[key] {
            if registration.scope == .weak {
                if let weakBox = cachedValue as? WeakBox, let value = weakBox.value {
                    // `value`는 AnyObject 타입이므로, `any Sendable`로 안전하게 캐스팅하여 반환합니다.
                    // 이 캐스팅은 `createAndCacheInstance`에서 Sendable을 보장하므로 항상 성공해야 합니다.
                    guard let sendableValue = value as? any Sendable else {
                        throw WeaverError.resolutionFailed(.typeMismatch(expected: "any Sendable", actual: "\(type(of: value))", keyName: key.description))
                    }
                    return sendableValue
                }
                // 약한 참조가 해제되었다면 캐시에서 제거하고 아래 생성 로직으로 넘어갑니다.
                containerCache.removeValue(forKey: key)
            } else {
                return cachedValue
            }
        }

        // 2. 진행 중인 생성 작업 확인
        if let task = ongoingCreations[key] {
            return try await task.value
        }
        
        // 3. 인스턴스 생성 및 캐시
        return try await createAndCacheInstance(key: key, registration: registration)
    }
    
    private func createAndCacheInstance(key: AnyDependencyKey, registration: DependencyRegistration) async throws -> any Sendable {
        let newTask = Task {
            try await registration.factory(self)
        }
        
        ongoingCreations[key] = newTask
        
        do {
            let instance = try await newTask.value
            
            if registration.scope == .weak {
                // .weak 스코프는 클래스 타입(AnyObject)이어야 약한 참조가 가능합니다.
                guard let object = instance as? AnyObject else {
                    throw WeaverError.resolutionFailed(.typeMismatch(expected: "AnyObject (class type)", actual: "\(type(of: instance))", keyName: key.description))
                }
                containerCache[key] = WeakBox(object)
            } else {
                containerCache[key] = instance
            }
            
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

// MARK: - ==================== Internal Helpers ====================

/// 약한 참조(weak reference)를 저장하기 위한 래퍼 클래스입니다.
private final class WeakBox: @unchecked Sendable {
    weak var value: AnyObject?
    init(_ value: AnyObject) {
        self.value = value
    }
}

/// `.container` 스코프이면서 `Disposable`을 채택한 인스턴스들의 생명주기를 관리하는 액터입니다.
internal actor DisposableManager {
    private var instances: [any Disposable] = []
    private let logger: WeaverLogger?
    
    init(logger: WeaverLogger?) { self.logger = logger }
    func add(_ disposable: any Disposable) { instances.append(disposable) }
    
    func disposeAll() async {
        guard !instances.isEmpty else { return }
        await logger?.log(message: "Disposing \(instances.count) instances.", level: .debug)
        await withTaskGroup(of: Void.self) { group in
            for instance in instances { group.addTask { await instance.dispose() } }
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


// MARK: - ==================== Models & Support Types ====================

/// 의존성의 생명주기를 정의하는 스코프 타입입니다.
public enum Scope: String, Sendable {
    /// 컨테이너와 생명주기를 함께하는 가장 일반적인 스코프입니다.
    case container
    /// 고급 캐시 정책(TTL, LRU)에 따라 관리되는 스코프입니다.
    case cached
    /// 컨테이너 빌드 시점에 즉시 초기화되는 스코프입니다.
    case eagerContainer
    /// 의존성을 약한 참조(weak reference)로 관리하는 스코프입니다.
    /// 순환 참조 방지나 메모리에 민감한 객체에 유용합니다.
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
    /// 이 의존성이 의존하는 다른 의존성들의 키 타입 이름 목록
    public let dependencies: [String]
}

/// 의존성 해결 통계 정보를 담는 구조체입니다.
public struct ResolutionMetrics: Sendable, CustomStringConvertible {
    public let totalResolutions: Int
    public let cacheHits: Int
    public let cacheMisses: Int
    public let averageResolutionTime: TimeInterval
    public let failedResolutions: Int
    
    public var cacheHitRate: Double { (cacheHits + cacheMisses) > 0 ? Double(cacheHits) / Double(cacheHits + cacheMisses) : 0 }
    public var successRate: Double { totalResolutions > 0 ? Double(totalResolutions - failedResolutions) / Double(totalResolutions) : 0 }
    
    public var description: String {
        return """
        Resolution Metrics:
        - Total Resolutions: \(totalResolutions)
        - Success Rate: \(String(format: "%.1f%%", successRate * 100))
        - Failed Resolutions: \(failedResolutions)
        - Cache Hit Rate: \(String(format: "%.1f%%", cacheHitRate * 100)) (Hits: \(cacheHits), Misses: \(cacheMisses))
        - Avg. Resolution Time: \(String(format: "%.4fms", averageResolutionTime * 1000))
        """
    }
}

/// `WeaverContainer`의 내부 동작을 제어하는 설정 구조체입니다.
public struct ContainerConfiguration: Sendable {
    var cachePolicy: CachePolicy = .default
}

// MARK: - ==================== Errors ====================

/// Weaver 라이브러리에서 발생하는 최상위 에러 타입입니다.
public enum WeaverError: Error, LocalizedError, Sendable {
    case containerNotFound, resolutionFailed(ResolutionError), shutdownInProgress
    public var errorDescription: String? {
        switch self {
        case .containerNotFound: return "활성화된 WeaverContainer를 찾을 수 없습니다."
        case .resolutionFailed(let error): return error.localizedDescription
        case .shutdownInProgress: return "컨테이너가 종료 처리 중입니다."
        }
    }
}

/// 의존성 해결 과정에서 발생하는 구체적인 에러 타입입니다.
public enum ResolutionError: Error, LocalizedError, Sendable {
    case circularDependency(path: String)
    case factoryFailed(keyName: String, underlying: any Error & Sendable)
    case typeMismatch(expected: String, actual: String, keyName: String)
    case keyNotFound(keyName: String)
    case weakObjectDeallocated(keyName: String)
    
    public var errorDescription: String? {
        switch self {
        case .circularDependency(let path): return "순환 참조가 감지되었습니다: \(path)"
        case .factoryFailed(let keyName, let underlying): return "'\(keyName)' 의존성 생성(factory)에 실패했습니다: \(underlying.localizedDescription)"
        case .typeMismatch(let expected, let actual, let keyName): return "'\(keyName)' 의존성의 타입이 일치하지 않습니다. 예상: \(expected), 실제: \(actual). '.weak' 스코프는 클래스(AnyObject) 타입만 지원합니다."
        case .keyNotFound(let keyName): return "'\(keyName)' 키에 대한 등록 정보를 찾을 수 없습니다."
        case .weakObjectDeallocated(let keyName): return "'\(keyName)'에 대한 약한 참조(weak) 의존성이 이미 메모리에서 해제되었습니다."
        }
    }
}

// MARK: - ==================== Default Implementations ====================

/// `TaskLocal`을 사용하여 의존성 해결 범위를 관리하는 기본 구현체입니다.
public struct DefaultDependencyScope: DependencyScope {
    @TaskLocal private static var _current: WeaverContainer?
    
    public var current: WeaverContainer? {
        get { Self._current }
    }
    
    public func withScope<R: Sendable>(_ container: WeaverContainer, operation: @Sendable () async throws -> R) async rethrows -> R {
        try await Self.$_current.withValue(container, operation: operation)
    }
}

/// 기본 로거 구현체입니다.
public actor DefaultLogger: WeaverLogger {
    private let logger = Logger(subsystem: "com.weaver.di", category: "Weaver")
    public init() {}
    public func log(message: String, level: OSLogType) {
        logger.log(level: level, "\(message)")
    }
}

/// 메트릭 수집 기능이 비활성화되었을 때 사용되는 기본 구현체입니다.
final class DummyMetricsCollector: MetricsCollecting {
    func recordResolution(duration: TimeInterval) async {}
    func recordFailure() async {}
    func recordCache(hit: Bool) async {}
    func getMetrics(cacheHits: Int, cacheMisses: Int) async -> ResolutionMetrics {
        return ResolutionMetrics(totalResolutions: 0, cacheHits: cacheHits, cacheMisses: cacheMisses, averageResolutionTime: 0, failedResolutions: 0)
    }
}

/// 캐시 기능이 비활성화되었을 때 사용되는 기본 구현체입니다.
final class DummyCacheManager: CacheManaging {
    func taskForInstance<T: Sendable>(key: AnyDependencyKey, factory: @Sendable @escaping () async throws -> T) async -> (task: Task<any Sendable, Error>, isHit: Bool) {
        return (Task { try await factory() }, false)
    }
    func getMetrics() async -> (hits: Int, misses: Int) { (0, 0) }
    func clear() async {}
}

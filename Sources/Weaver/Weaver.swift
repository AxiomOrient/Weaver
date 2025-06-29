// Weaver.swift

import Foundation
import os

// MARK: - ==================== Weaver Namespace ====================

/// Weaver의 전역적인 접근 및 범위 관리를 위한 네임스페이스입니다.
@MainActor
public enum Weaver {
    /// 전역적으로 사용될 의존성 범위 관리자입니다.
    public static var scope: DependencyScope = DefaultDependencyScope()
    
    /// 현재 작업 범위에 활성화된 `WeaverContainer`입니다.
    public static var current: WeaverContainer? {
        get async { await scope.current }
    }
    
    /// 특정 컨테이너를 현재 작업 범위로 설정하고 주어진 `operation`을 실행합니다.
    public static func withScope<R: Sendable>(_ container: WeaverContainer, operation: @Sendable () async throws -> R) async rethrows -> R {
        try await scope.withScope(container, operation: operation)
    }
}

// MARK: - ==================== @Inject Property Wrapper ====================

/// 의존성 주입을 위한 프로퍼티 래퍼입니다.
@propertyWrapper
public struct Inject<Key: DependencyKey>: Sendable {
    private let keyType: Key.Type
    private let storage = ValueStorage<Key.Value>()
    
    public init(_ keyType: Key.Type) {
        self.keyType = keyType
    }
    
    /// 래핑된 프로퍼티는 프로퍼티 래퍼 자신을 반환하여, `callAsFunction` 등의 메서드에 접근할 수 있도록 합니다.
    public var wrappedValue: Self {
        return self
    }
    
    /// `$` 접두사를 통해 접근하는 projectedValue는 에러를 던지는(throwing) API 등 대체 기능을 제공합니다.
    public var projectedValue: InjectProjection<Key> {
        InjectProjection(getOrResolveValue: { @Sendable in
            try await self.getOrResolveValue()
        })
    }
    
    /// 기본 의존성 접근 방식입니다. `await service()`와 같이 함수처럼 호출하여 사용합니다.
    ///
    /// 의존성 해결에 실패할 경우 `Key.defaultValue`를 반환하고, 디버깅을 위해 로그를 남깁니다.
    public func callAsFunction() async -> Key.Value {
        do {
            return try await getOrResolveValue()
        } catch {
            let errorMessage = "의존성 해결 실패: \(Key.self). 기본값을 반환합니다. 에러: \(error.localizedDescription)"
            Task { await Weaver.current?.logger?.log(message: errorMessage, level: .debug) }
            return Key.defaultValue
        }
    }
    
    private func getOrResolveValue() async throws -> Key.Value {
        if let cachedResult = await storage.getResult() {
            return try cachedResult.get()
        }
        let newResult: Result<Key.Value, Error>
        do {
            guard let container = await Weaver.current else {
                throw WeaverError.containerNotFound
            }
            let value = try await container.resolve(keyType)
            newResult = .success(value)
        } catch {
            newResult = .failure(error)
        }
        await storage.setResult(newResult)
        return try newResult.get()
    }
    
    private actor ValueStorage<Value: Sendable> {
        private var resolutionResult: Result<Value, Error>?
        func getResult() -> Result<Value, Error>? { resolutionResult }
        func setResult(_ newResult: Result<Value, Error>) { resolutionResult = newResult }
    }
}

/// `@Inject`의 `projectedValue`를 통해 제공되는 기능을 담는 구조체입니다.
public struct InjectProjection<Key: DependencyKey>: Sendable {
    fileprivate let getOrResolveValue: @Sendable () async throws -> Key.Value
    
    public var resolved: Key.Value {
        get async throws {
            try await getOrResolveValue()
        }
    }
}

// MARK: - ==================== WeaverContainer ====================

/// 의존성을 관리하고 해결하는 핵심 DI 컨테이너 액터입니다.
public actor WeaverContainer: Resolver {
    // MARK: - Properties
    
    public let registrations: [AnyDependencyKey: DependencyRegistration]
    nonisolated public let logger: WeaverLogger?
    
    private let parent: WeaverContainer?
    private let scopeManager: ScopeManager
    private let disposableManager: DisposableManager
    private let cacheManager: CacheManaging
    private let metricsCollector: MetricsCollecting
    
    private var shutdownTask: Task<Void, Never>?
    @TaskLocal private static var resolutionStack: [AnyDependencyKey] = []
    
    // MARK: - Initialization & Build
    
    /// `WeaverContainer`를 생성하기 위한 빌더를 반환합니다.
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
        self.scopeManager = ScopeManager(logger: logger)
        self.disposableManager = DisposableManager(logger: logger)
        self.cacheManager = cacheManager
        self.metricsCollector = metricsCollector
    }
    
    /// 컨테이너를 안전하게 종료하고 모든 관리 리소스를 해제합니다.
    public func shutdown() async {
        if let shutdownTask {
            await shutdownTask.value
            return
        }
        self.shutdownTask = Task {
            await logger?.log(message: "Shutting down WeaverContainer.", level: .debug)
            await disposableManager.disposeAll()
            await scopeManager.clear()
            await cacheManager.clear()
        }
        await self.shutdownTask?.value
    }
    
    // MARK: - Public API
    
    public func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value {
        guard shutdownTask == nil else { throw WeaverError.shutdownInProgress }
        
        let key = AnyDependencyKey(keyType)
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let value: Key.Value = try await resolve(key: key, as: Key.Value.self)
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            await metricsCollector.recordResolution(duration: duration)
            return value
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            await metricsCollector.recordResolution(duration: duration)
            await metricsCollector.recordFailure()
            throw error
        }
    }
    
    /// 현재까지 수집된 의존성 해결 메트릭을 반환합니다.
    public func getMetrics() async -> ResolutionMetrics {
        let (hits, misses) = await cacheManager.getMetrics()
        return await metricsCollector.getMetrics(cacheHits: hits, cacheMisses: misses)
    }
    
    // MARK: - Internal Resolution Logic
    
    private func resolve<T: Sendable>(key: AnyDependencyKey, as type: T.Type) async throws -> T {
        if Self.resolutionStack.contains(key) {
            let cycleMessage = (Self.resolutionStack.map(\.description) + [key.description]).joined(separator: " -> ")
            await logger?.log(message: "순환 참조 감지: \(cycleMessage)", level: .fault)
            throw WeaverError.resolutionFailed(.circularDependency(path: cycleMessage))
        }
        
        return try await Self.$resolutionStack.withValue(Self.resolutionStack + [key]) {
            if let registration = registrations[key] {
                let instance = try await resolve(key: key, from: registration)
                guard let typedInstance = instance as? T else {
                    let error = ResolutionError.typeMismatch(expected: "\(T.self)", actual: "\(Swift.type(of: instance))", keyName: registration.keyName)
                    throw WeaverError.resolutionFailed(error)
                }
                return typedInstance
            } else if let parent = parent {
                return try await Self.$resolutionStack.withValue([]) {
                    try await parent.resolve(key: key, as: T.self)
                }
            } else {
                throw WeaverError.resolutionFailed(.keyNotFound(keyName: key.description))
            }
        }
    }
    
    private func resolve(key: AnyDependencyKey, from registration: DependencyRegistration) async throws -> any Sendable {
        let instance: any Sendable
        do {
            switch registration.scope {
            case .container:
                instance = try await scopeManager.getOrCreateInstance(key: key) { try await registration.factory(self) }
            case .cached:
                let (resolvedInstance, isHit) = try await cacheManager.getOrCreateInstance(key: key) { try await registration.factory(self) }
                await metricsCollector.recordCache(hit: isHit)
                instance = resolvedInstance
            case .transient:
                instance = try await registration.factory(self)
            }
        } catch let error as WeaverError {
            throw error
        } catch {
            throw WeaverError.resolutionFailed(.factoryFailed(keyName: registration.keyName, underlying: error))
        }
        
        if registration.scope == .container, let disposable = instance as? Disposable {
            await disposableManager.add(disposable)
        }
        return instance
    }
}

// MARK: - ==================== Internal Managers ====================

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

/// `.container` 스코프 인스턴스를 관리하는 액터입니다.
internal actor ScopeManager {
    private var containerCache: [AnyDependencyKey: any Sendable] = [:]
    private var ongoingCreations: [AnyDependencyKey: Task<any Sendable, Error>] = [:]
    private let logger: WeaverLogger?
    
    init(logger: WeaverLogger?) { self.logger = logger }
    
    func getOrCreateInstance<T: Sendable>(key: AnyDependencyKey, factory: @Sendable @escaping () async throws -> T) async throws -> T {
        if let cachedInstance = containerCache[key] {
            guard let typedInstance = cachedInstance as? T else {
                throw WeaverError.resolutionFailed(.typeMismatch(expected: "\(T.self)", actual: "\(Swift.type(of: cachedInstance))", keyName: key.description))
            }
            return typedInstance
        }

        if let existingTask = ongoingCreations[key] {
            let instance = try await existingTask.value
            guard let typedInstance = instance as? T else {
                throw WeaverError.resolutionFailed(.typeMismatch(expected: "\(T.self)", actual: "\(Swift.type(of: instance))", keyName: key.description))
            }
            return typedInstance
        }

        let creationTask = Task<any Sendable, Error> {
            do {
                let instance = try await factory()
                containerCache[key] = instance
                return instance
            } catch {
                throw error
            }
        }
        
        ongoingCreations[key] = creationTask
        
        do {
            let instance = try await creationTask.value
            ongoingCreations[key] = nil
            guard let typedInstance = instance as? T else {
                throw WeaverError.resolutionFailed(.typeMismatch(expected: "\(T.self)", actual: "\(Swift.type(of: instance))", keyName: key.description))
            }
            return typedInstance
        } catch {
            ongoingCreations[key] = nil
            throw error
        }
    }
    
    func clear() {
        containerCache.removeAll()
        ongoingCreations.values.forEach { $0.cancel() }
        ongoingCreations.removeAll()
    }
}


// MARK: - ==================== Models & Support Types ====================

/// 의존성의 생명주기를 정의하는 스코프 타입입니다.
public enum Scope: Sendable {
    case container, cached, transient
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
    
    public var errorDescription: String? {
        switch self {
        case .circularDependency(let path): return "순환 참조가 감지되었습니다: \(path)"
        case .factoryFailed(let keyName, let underlying): return "'\(keyName)' 의존성 생성(factory)에 실패했습니다: \(underlying.localizedDescription)"
        case .typeMismatch(let expected, let actual, let keyName): return "'\(keyName)' 의존성의 타입이 일치하지 않습니다. 예상: \(expected), 실제: \(actual)"
        case .keyNotFound(let keyName): return "'\(keyName)' 키에 대한 등록 정보를 찾을 수 없습니다."
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
    func getOrCreateInstance<T: Sendable>(key: AnyDependencyKey, factory: @Sendable @escaping () async throws -> T) async throws -> (value: T, isHit: Bool) {
        (try await factory(), false)
    }
    func getMetrics() async -> (hits: Int, misses: Int) { (0, 0) }
    func clear() async {}
}

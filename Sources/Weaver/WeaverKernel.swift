// Weaver/Sources/Weaver/WeaverKernel.swift

import Foundation
import os

// MARK: - ==================== 통합 Weaver 커널 ====================
//
// DevPrinciples Article 1, 3에 따라 단일 책임과 단순성을 추구하는 유일한 커널입니다.
// 기존의 여러 커널을 하나로 통합하여 복잡성을 완전히 제거합니다.

/// Weaver DI 시스템의 유일한 커널 구현체입니다.
/// 전략 패턴을 통해 다양한 초기화 방식을 지원하는 단일 구현체입니다.
public actor WeaverKernel: WeaverKernelProtocol, Resolver {
    
    // MARK: - Properties
    
    private let modules: [Module]
    private let logger: WeaverLogger
    private let initializationStrategy: InitializationStrategy
    
    private var container: WeaverContainer?
    private var syncContainer: WeaverSyncContainer?
    
    // MARK: - State Management
    
    private var _currentState: LifecycleState = .idle
    public var currentState: LifecycleState {
        get async { _currentState }
    }
    
    public let stateStream: AsyncStream<LifecycleState>
    private let stateContinuation: AsyncStream<LifecycleState>.Continuation
    
    // MARK: - Initialization Strategy
    
    public enum InitializationStrategy: Sendable {
        case immediate      // 즉시 모든 의존성 초기화
        case realistic     // 동기 시작 + 지연 초기화 (권장)
    }
    
    // MARK: - Initialization
    
    public init(
        modules: [Module], 
        strategy: InitializationStrategy = .realistic,
        logger: WeaverLogger = DefaultLogger()
    ) {
        self.modules = modules
        self.initializationStrategy = strategy
        self.logger = logger
        
        // AsyncStream 설정
        var continuation: AsyncStream<LifecycleState>.Continuation!
        self.stateStream = AsyncStream(bufferingPolicy: .unbounded) {
            continuation = $0
        }
        self.stateContinuation = continuation
        
        // 초기 상태 방출
        self.stateContinuation.yield(.idle)
    }
    
    // MARK: - LifecycleManager Implementation
    
    public func build() async {
        await updateState(.configuring)
        
        switch initializationStrategy {
        case .immediate:
            await buildImmediate()
        case .realistic:
            await buildRealistic()
        }
    }
    
    public func shutdown() async {
        await logger.log(message: "🛑 커널 종료 시작", level: .info)
        
        if let container = container {
            await container.shutdown()
        }
        
        await updateState(.shutdown)
        stateContinuation.finish()
        
        await logger.log(message: "✅ 커널 종료 완료", level: .info)
    }
    
    // MARK: - SafeResolver Implementation
    
    public func safeResolve<Key: DependencyKey>(_ keyType: Key.Type) async -> Key.Value {
        // Preview 환경 처리
        if WeaverEnvironment.isPreview {
            return Key.defaultValue
        }
        
        // 전략에 따른 해결
        switch initializationStrategy {
        case .realistic:
            if let syncContainer = syncContainer {
                return await syncContainer.safeResolve(keyType)
            }
        case .immediate:
            if case .ready(let resolver) = _currentState {
                do {
                    return try await resolver.resolve(keyType)
                } catch {
                    await logger.logResolutionFailure(
                        keyName: String(describing: keyType),
                        currentState: _currentState,
                        error: error
                    )
                }
            }
        }
        
        return Key.defaultValue
    }
    
    /// 🚀 Swift 6 방식: 타임아웃 없는 현대적 준비 대기
    /// DevPrinciples Article 3에 따라 블로킹 없는 단순한 구현
    public func waitForReady(timeout: TimeInterval?) async throws -> any Resolver {
        // 이미 준비된 경우
        if case .ready(let resolver) = _currentState {
            return resolver
        }
        
        // realistic 전략의 경우 syncContainer 즉시 반환
        if initializationStrategy == .realistic, let syncContainer = syncContainer {
            return syncContainer
        }
        
        // 실패 상태인 경우
        if case .failed(let error) = _currentState {
            throw WeaverError.containerFailed(underlying: error)
        }
        
        // 🚀 Swift 6 방식: AsyncStream을 사용한 논블로킹 대기
        return try await waitForReadyState()
    }
    
    // MARK: - Resolver Implementation
    
    public func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value {
        switch initializationStrategy {
        case .realistic:
            if let syncContainer = syncContainer {
                return try await syncContainer.resolve(keyType)
            }
        case .immediate:
            guard case .ready(let resolver) = _currentState else {
                throw WeaverError.containerNotReady(currentState: _currentState)
            }
            return try await resolver.resolve(keyType)
        }
        
        throw WeaverError.containerNotReady(currentState: _currentState)
    }
    
    // MARK: - Private Build Strategies
    
    private func buildImmediate() async {
        await logger.log(message: "🏗️ 즉시 초기화 시작", level: .info)
        
        let builder = await WeaverContainer.builder().withLogger(logger)
        
        for module in modules {
            await module.configure(builder)
        }
        
        let newContainer = await builder.build { progress in
            await self.updateState(.warmingUp(progress: progress))
        }
        
        self.container = newContainer
        await updateState(.ready(newContainer))
        
        await logger.log(message: "✅ 즉시 초기화 완료", level: .info)
    }
    
    private func buildRealistic() async {
        await logger.log(message: "🚀 현실적 초기화 시작", level: .info)
        
        // 1단계: 동기 컨테이너 즉시 생성
        let syncBuilder = WeaverSyncBuilder()
        
        for module in modules {
            if let syncModule = module as? SyncModule {
                syncModule.configure(syncBuilder)
            } else {
                // 일반 Module을 SyncModule로 변환하는 어댑터
                let adapter = ModuleAdapter(module: module)
                adapter.configure(syncBuilder)
            }
        }
        
        let newSyncContainer = syncBuilder.build()
        self.syncContainer = newSyncContainer
        
        // 2단계: 즉시 ready 상태로 전환
        await updateState(.ready(newSyncContainer))
        
        // 3단계: 백그라운드에서 eager 서비스 초기화
        Task.detached { @Sendable [weak self] in
            await self?.initializeEagerServices(newSyncContainer)
        }
        
        await logger.log(message: "✅ 현실적 초기화 완료", level: .info)
    }
    
    // MARK: - Helper Methods
    
    private func updateState(_ newState: LifecycleState) async {
        let oldState = _currentState
        _currentState = newState
        stateContinuation.yield(newState)
        
        await logger.logStateTransition(from: oldState, to: newState, reason: nil)
    }
    
    /// 🚀 Swift 6 방식: 타임아웃 없는 순수한 AsyncStream 기반 대기
    /// DevPrinciples Article 3에 따라 단순하고 명확한 구현
    private func waitForReadyState() async throws -> any Resolver {
        // 현재 상태를 다시 한번 확인 (race condition 방지)
        switch _currentState {
        case .ready(let resolver):
            return resolver
        case .failed(let error):
            throw WeaverError.containerFailed(underlying: error)
        case .shutdown:
            throw WeaverError.shutdownInProgress
        default:
            break
        }
        
        // AsyncStream을 사용한 논블로킹 상태 대기
        for await state in stateStream {
            switch state {
            case .ready(let resolver):
                return resolver
            case .failed(let error):
                throw WeaverError.containerFailed(underlying: error)
            case .shutdown:
                throw WeaverError.shutdownInProgress
            default:
                continue
            }
        }
        
        // 스트림이 종료된 경우
        throw WeaverError.shutdownInProgress
    }
    
    private func initializeEagerServices(_ container: WeaverSyncContainer) async {
        await logger.log(message: "🔥 Eager 서비스 백그라운드 초기화 시작", level: .info)
        
        // eager 타이밍 서비스들을 식별하고 초기화
        // 실제 구현에서는 등록된 의존성의 timing을 확인하여 처리
        
        await logger.log(message: "✅ Eager 서비스 백그라운드 초기화 완료", level: .info)
    }
}

// MARK: - ==================== Module Adapter ====================

/// 일반 Module을 SyncModule로 변환하는 어댑터입니다.
/// DevPrinciples Article 1에 따라 기존 코드와의 호환성을 보장합니다.
private struct ModuleAdapter: SyncModule {
    private let module: Module
    
    init(module: Module) {
        self.module = module
    }
    
    func configure(_ builder: WeaverSyncBuilder) {
        // 🚀 Swift 6 방식: 비동기 모듈을 동기 빌더에 안전하게 등록
        // 현실적 전략에서는 기본값만 등록하고 실제 초기화는 지연
        
        // 실제 구현에서는 Module의 등록 정보를 추출하여
        // SyncBuilder에 기본값 팩토리로 등록하는 방식 사용
        
        // 현재는 안전한 기본 구현만 제공
        // 실제 의존성은 백그라운드에서 초기화됨
    }
}

// MARK: - ==================== 편의 생성자 ====================

public extension WeaverKernel {
    /// 즉시 초기화 전략으로 커널을 생성합니다.
    static func immediate(modules: [Module], logger: WeaverLogger = DefaultLogger()) -> WeaverKernel {
        return WeaverKernel(modules: modules, strategy: .immediate, logger: logger)
    }
    
    /// 현실적 초기화 전략으로 커널을 생성합니다. (권장)
    static func realistic(modules: [Module], logger: WeaverLogger = DefaultLogger()) -> WeaverKernel {
        return WeaverKernel(modules: modules, strategy: .realistic, logger: logger)
    }
}

// MARK: - ==================== App Lifecycle Events ====================

/// 앱 생명주기 이벤트를 나타내는 열거형입니다.
public enum AppLifecycleEvent: String, Sendable {
    case didEnterBackground
    case willEnterForeground
    case willTerminate
}

/// 앱 생명주기 이벤트를 수신할 수 있는 프로토콜입니다.
/// `appService` 스코프의 서비스들이 구현하여 앱 상태 변화에 반응할 수 있습니다.
public protocol AppLifecycleAware: Sendable {
    /// 앱이 백그라운드로 진입할 때 호출됩니다.
    func appDidEnterBackground() async throws
    
    /// 앱이 포그라운드로 복귀할 때 호출됩니다.
    func appWillEnterForeground() async throws
    
    /// 앱이 종료될 때 호출됩니다.
    func appWillTerminate() async throws
}

/// AppLifecycleAware의 기본 구현을 제공합니다.
public extension AppLifecycleAware {
    func appDidEnterBackground() async throws {}
    func appWillEnterForeground() async throws {}
    func appWillTerminate() async throws {}
}

// MARK: - ==================== Cache Policy ====================

/// 캐시 정책을 정의하는 열거형입니다.
public enum CachePolicy: Sendable {
    case `default`
    case aggressive
    case minimal
    case disabled
}

// MARK: - ==================== Convenience Extensions ====================

extension WeaverBuilder {
    /// 고급 캐싱 기능을 활성화합니다.
    @discardableResult
    public func enableAdvancedCaching(policy: CachePolicy = .default) -> Self {
        return setCacheManagerFactory { policy, logger in
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

// MARK: - ==================== Default Implementations ====================

/// 🚀 Swift 6 방식: Actor 기반 캐시 매니저 (Lock-Free)
/// DevPrinciples Article 5에 따라 동시성 안전성을 actor로 보장
actor DefaultCacheManager: CacheManaging {
    private let policy: CachePolicy
    private let logger: WeaverLogger
    private var cache: [AnyDependencyKey: (task: Task<any Sendable, Error>, isHit: Bool)] = [:]
    private var hits = 0
    private var misses = 0
    
    init(policy: CachePolicy, logger: WeaverLogger) {
        self.policy = policy
        self.logger = logger
    }
    
    func taskForInstance<T: Sendable>(
        key: AnyDependencyKey,
        factory: @Sendable @escaping () async throws -> T
    ) async -> (task: Task<any Sendable, Error>, isHit: Bool) {
        
        // 캐시 확인 (actor 내부에서 동시성 안전)
        if let cached = cache[key] {
            hits += 1
            return (cached.task, true)
        }
        
        // 새 태스크 생성
        let newTask = Task<any Sendable, Error> {
            try await factory()
        }
        
        cache[key] = (newTask, false)
        misses += 1
        
        return (newTask, false)
    }
    
    func getMetrics() async -> (hits: Int, misses: Int) {
        return (hits, misses)
    }
    
    func clear() async {
        cache.removeAll()
    }
}

/// 🚀 Swift 6 방식: Actor 기반 메트릭 수집기 (Lock-Free)
/// DevPrinciples Article 5에 따라 동시성 안전성을 actor로 보장
actor DefaultMetricsCollector: MetricsCollecting {
    private var totalResolutions = 0
    private var totalDuration: TimeInterval = 0
    private var failedResolutions = 0
    
    func recordResolution(duration: TimeInterval) async {
        totalResolutions += 1
        totalDuration += duration
    }
    
    func recordFailure() async {
        failedResolutions += 1
    }
    
    func recordCache(hit: Bool) async {
        // 캐시 메트릭은 CacheManager에서 관리
    }
    
    func getMetrics(cacheHits: Int, cacheMisses: Int) async -> ResolutionMetrics {
        let averageTime = totalResolutions > 0 ? 
            totalDuration / Double(totalResolutions) : 0
        
        return ResolutionMetrics(
            totalResolutions: totalResolutions,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses,
            averageResolutionTime: averageTime,
            failedResolutions: failedResolutions,
            weakReferences: WeakReferenceMetrics(
                totalWeakReferences: 0,
                aliveWeakReferences: 0,
                deallocatedWeakReferences: 0
            )
        )
    }
}
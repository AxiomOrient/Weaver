// Weaver/Sources/Weaver/WeaverKernel.swift

import Foundation
import os

// MARK: - ==================== 스코프 기반 점진적 로딩 커널 ====================
//
// 핵심 설계 원칙:
// 1. 앱 시작 시 최소한의 동기 의존성만 등록 (bootstrap 스코프)
// 2. 스코프별 점진적 로딩으로 앱 반응성 보장
// 3. 사용 시점에 필요한 스코프만 활성화
// 4. 명확한 스코프 생명주기 관리

/// 스코프 기반 점진적 로딩을 지원하는 DI 커널입니다.
/// 앱 시작 시 동기/비동기 문제를 해결하기 위해 스코프 단위로 의존성을 관리합니다.
public actor WeaverKernel: WeaverKernelProtocol, Resolver {
    
    // MARK: - Properties
    
    private let modules: [Module]
    private let logger: WeaverLogger
    
    // 스코프별 컨테이너 관리
    private var scopeContainers: [Scope: WeaverContainer] = [:]
    private var activatedScopes: Set<Scope> = []
    
    // 스코프별 등록 정보 캐시
    private var scopeRegistrations: [Scope: [AnyDependencyKey: DependencyRegistration]] = [:]
    
    // MARK: - State Management
    
    private var _currentState: LifecycleState = .idle
    public var currentState: LifecycleState {
        get async { _currentState }
    }
    
    public let stateStream: AsyncStream<LifecycleState>
    private let stateContinuation: AsyncStream<LifecycleState>.Continuation
    
    // MARK: - Initialization
    
    public init(
        modules: [Module],
        logger: WeaverLogger = DefaultLogger()
    ) {
        self.modules = modules
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
        
        // 1단계: 모든 모듈에서 등록 정보 수집
        await collectRegistrations()
        
        // 2단계: Startup 스코프만 즉시 활성화
        await activateScope(.startup)
        
        // 3단계: Ready 상태로 전환
        await updateState(.ready(self))
        
        await logger.log(message: "✅ 커널 빌드 완료 - Startup 스코프 활성화됨", level: .info)
    }
    
    public func shutdown() async {
        await logger.log(message: "🛑 커널 종료 시작", level: .info)
        
        // 활성화된 스코프들을 역순으로 종료
        let scopesToShutdown = Array(activatedScopes).sorted { lhs, rhs in
            getScopeShutdownPriority(lhs) > getScopeShutdownPriority(rhs)
        }
        
        for scope in scopesToShutdown {
            if let container = scopeContainers[scope] {
                await container.shutdown()
                await logger.log(message: "🛑 스코프 종료: \(scope)", level: .debug)
            }
        }
        
        scopeContainers.removeAll()
        activatedScopes.removeAll()
        scopeRegistrations.removeAll()
        
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
        
        do {
            return try await resolve(keyType)
        } catch {
            await logger.logResolutionFailure(
                keyName: String(describing: keyType),
                currentState: _currentState,
                error: error
            )
            return Key.defaultValue
        }
    }
    
    /// 커널이 준비 상태인지 확인하고 준비된 경우 resolver를 반환합니다.
    /// 비동기 라이브러리에서는 대기하지 않고 즉시 상태를 확인합니다.
    public func waitForReady() async throws -> any Resolver {
        // 이미 준비된 경우
        if case .ready(let resolver) = _currentState {
            return resolver
        }
        
        // shutdown 상태인 경우
        if case .shutdown = _currentState {
            throw WeaverError.shutdownInProgress
        }
        
        // 실패 상태인 경우
        if case .failed(let error) = _currentState {
            throw WeaverError.containerFailed(underlying: error)
        }
        
        // startup 스코프가 활성화되어 있으면 준비된 것으로 간주
        if activatedScopes.contains(.startup) {
            return self
        }
        
        // 준비되지 않은 상태
        throw WeaverError.containerNotReady(currentState: _currentState)
    }
    
    // MARK: - Resolver Implementation
    
    public func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value {
        let key = AnyDependencyKey(keyType)
        
        // 1. 어느 스코프에 등록되어 있는지 찾기
        guard let targetScope = findScopeForKey(key) else {
            throw WeaverError.resolutionFailed(.keyNotFound(keyName: key.description))
        }
        
        // 2. 해당 스코프가 활성화되어 있지 않으면 활성화
        if !activatedScopes.contains(targetScope) {
            await activateScope(targetScope)
        }
        
        // 3. 스코프 컨테이너에서 해결
        guard let container = scopeContainers[targetScope] else {
            throw WeaverError.resolutionFailed(.keyNotFound(keyName: key.description))
        }
        
        return try await container.resolve(keyType)
    }
    
    // MARK: - Scope Management
    
    /// 모든 모듈에서 등록 정보를 수집하고 스코프별로 분류합니다.
    private func collectRegistrations() async {
        await logger.log(message: "� 모실듈 등록 정보 수집 시작", level: .debug)
        
        let builder = await WeaverContainer.builder().withLogger(logger)
        
        // 모든 모듈 구성
        for module in modules {
            await module.configure(builder)
        }
        
        // 등록 정보를 스코프별로 분류
        let allRegistrations = await builder.getRegistrations()
        
        for (key, registration) in allRegistrations {
            let scope = registration.scope
            if scopeRegistrations[scope] == nil {
                scopeRegistrations[scope] = [:]
            }
            scopeRegistrations[scope]![key] = registration
        }
        
        await logger.log(
            message: "✅ 등록 정보 수집 완료 - 스코프별 분류: \(scopeRegistrations.keys.map { "\($0)" }.joined(separator: ", "))",
            level: .debug
        )
    }
    
    /// 지정된 스코프를 활성화합니다.
    private func activateScope(_ scope: Scope) async {
        guard !activatedScopes.contains(scope) else {
            return // 이미 활성화됨
        }
        
        await logger.log(message: "🚀 스코프 활성화 시작: \(scope)", level: .debug)
        
        // 의존성이 있는 스코프들을 먼저 활성화
        let dependencies = getScopeDependencies(scope)
        for dependency in dependencies {
            if !activatedScopes.contains(dependency) {
                await activateScope(dependency)
            }
        }
        
        // 스코프별 등록 정보로 컨테이너 생성
        guard let registrations = scopeRegistrations[scope], !registrations.isEmpty else {
            await logger.log(message: "⚠️ 스코프에 등록된 의존성이 없음: \(scope)", level: .debug)
            activatedScopes.insert(scope)
            return
        }
        
        let builder = await WeaverContainer.builder()
            .withLogger(logger)
            .withRegistrations(registrations)
        
        let container = await builder.build { progress in
            await self.logger.log(
                message: "📊 스코프 \(scope) 초기화 진행률: \(Int(progress * 100))%",
                level: .debug
            )
        }
        
        scopeContainers[scope] = container
        activatedScopes.insert(scope)
        
        await logger.log(message: "✅ 스코프 활성화 완료: \(scope)", level: .debug)
    }
    
    /// 키가 어느 스코프에 등록되어 있는지 찾습니다.
    private func findScopeForKey(_ key: AnyDependencyKey) -> Scope? {
        for (scope, registrations) in scopeRegistrations {
            if registrations[key] != nil {
                return scope
            }
        }
        return nil
    }
    
    /// 스코프의 의존성을 반환합니다.
    private func getScopeDependencies(_ scope: Scope) -> [Scope] {
        switch scope {
        case .startup:
            return [] // 최상위 스코프 - 앱 시작 시 필수
        case .shared:
            return [.startup] // startup에 의존
        case .whenNeeded:
            return [.startup] // startup에 의존
        case .weak:
            return [.startup] // startup에 의존
        }
    }
    
    /// 스코프 종료 우선순위를 반환합니다 (높을수록 먼저 종료).
    private func getScopeShutdownPriority(_ scope: Scope) -> Int {
        switch scope {
        case .whenNeeded:
            return 3 // 가장 먼저 종료
        case .shared:
            return 2
        case .weak:
            return 1
        case .startup:
            return 0 // 가장 마지막에 종료
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateState(_ newState: LifecycleState) async {
        let oldState = _currentState
        _currentState = newState
        stateContinuation.yield(newState)
        
        await logger.logStateTransition(from: oldState, to: newState, reason: nil)
    }
}

// MARK: - ==================== 편의 생성자 ====================

public extension WeaverKernel {
    /// 스코프 기반 커널을 생성합니다.
    static func scoped(modules: [Module], logger: WeaverLogger = DefaultLogger()) -> WeaverKernel {
        return WeaverKernel(modules: modules, logger: logger)
    }
}

// MARK: - ==================== 앱 생명주기 이벤트 ====================

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

// MARK: - ==================== 캐시 정책 ====================

/// 캐시 정책을 정의하는 열거형입니다.
public enum CachePolicy: Sendable {
    case `default`
    case aggressive
    case minimal
    case disabled
}


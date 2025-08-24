// Weaver/Sources/Weaver/WeaverKernel.swift

import Foundation
import os
import _Concurrency

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
    // 해석 가속화를 위한 키→스코프 인덱스 (PHASE2: O(1) 해상도)
    private var keyScopeIndex: [ObjectIdentifier: Scope] = [:]
    
    // 병렬 초기화 코디네이터
    private let startupCoordinator: StartupCoordinator
    
    // MARK: - State Management
    
    private var currentLifecycleState: LifecycleState = .idle
    public var currentState: LifecycleState {
        get async { currentLifecycleState }
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
        self.startupCoordinator = StartupCoordinator(logger: logger)
        
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
    
    public func build() async throws {
        await updateState(.configuring)
        
        do {
            // 1단계: 모든 모듈에서 등록 정보 수집
            try await collectRegistrations()
            
            // 2단계: Startup 스코프만 즉시 활성화
            try await activateScope(.startup)
            
            // 3단계: Ready 상태로 전환
            await updateState(.ready(self))
            
            await logger.log(message: "✅ 커널 빌드 완료 - Startup 스코프 활성화됨", level: .info)
            
        } catch {
            await updateState(.failed(error))
            await logger.log(message: "🚨 커널 빌드 실패: \(error.localizedDescription)", level: .error)
            
            throw error
        }
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
    
    /// 단순화된 safeResolve - DependencyValues 시스템과 통합
    public func safeResolve<Key: DependencyKey>(_ keyType: Key.Type) async -> Key.Value {
        // DependencyValues 시스템에 컨텍스트별 해결 위임
        // 이리 인해 Preview/Test 환경 처리가 일관성 있게 수행됨
        let currentContext = await DependencyValues.currentContext
        
        // Preview/Test 환경에서는 단순하게 컨텍스트 값 반환
        if currentContext == .preview {
            return keyType.previewValue
        }
        if currentContext == .test {
            return keyType.testValue
        }
        
        // Live 환경에서만 복잡한 의존성 해결 수행
        do {
            return try await resolve(keyType)
        } catch {
            // 로깅 최소화
            if WeaverEnvironment.isDevelopment {
                await logger.logResolutionFailure(
                    keyName: String(describing: keyType),
                    currentState: currentLifecycleState,
                    error: error
                )
            }
            
            // 타입 기반 API 지원
            let key = AnyDependencyKey(keyType)
            if let directDefault = await getDirectDefaultValue(for: key, as: Key.Value.self) {
                return directDefault
            }
            
            return keyType.liveValue
        }
    }
    
    /// 커널이 준비 상태인지 확인하고 준비된 경우 resolver를 반환합니다.
    /// 준비되지 않은 경우 즉시 적절한 에러를 발생시킵니다.
    public func ensureReady() async throws -> any Resolver {
        // 이미 준비된 경우
        if case .ready(let resolver) = currentLifecycleState {
            return resolver
        }
        
        // shutdown 상태인 경우
        if case .shutdown = currentLifecycleState {
            throw WeaverError.shutdownInProgress
        }
        
        // 실패 상태인 경우
        if case .failed(let error) = currentLifecycleState {
            throw WeaverError.containerFailed(underlying: error)
        }
        
        // startup 스코프가 활성화되어 있으면 준비된 것으로 간주
        if activatedScopes.contains(.startup) {
            return self
        }
        
        // 준비되지 않은 상태
        throw WeaverError.containerNotReady(currentState: currentLifecycleState)
    }
    
    // MARK: - Resolver Implementation
    
    public func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value {
        let keyId = ObjectIdentifier(keyType)
        guard let scope = keyScopeIndex[keyId] else {
            throw WeaverError.resolutionFailed(.keyNotFound(keyName: String(describing: keyType)))
        }
        
        // 스코프가 비활성 상태일 경우 안전하게 활성화합니다.
        try await activateScope(scope)
        
        // 활성화된 스코프의 컨테이너에서 의존성을 해결합니다.
        guard let container = scopeContainers[scope] else {
            // activateScope가 성공했다면 이 경로는 실행되지 않아야 합니다.
            // 이는 시스템의 내부 상태가 일관되지 않음을 의미하므로, 런타임 에러를 발생시켜 즉시 문제를 파악하도록 합니다.
            fatalError("Weaver Internal Inconsistency: Scope '\(scope)' was activated, but its container is missing.")
        }
        
        return try await container.resolve(keyType)
    }
    
    // MARK: - Scope Management
    
    /// 모든 모듈에서 등록 정보를 수집하고 스코프별로 분류합니다.
    private func collectRegistrations() async throws {
        await logger.log(message: "모듈 등록 정보 수집 시작", level: .debug)
        
        let builder = await WeaverContainer.builder().withLogger(logger)
        
        // 모든 모듈 구성
        for module in modules {
            await module.configure(builder)
        }
        
        // 🔧 [NEW] 빌드 타임 의존성 그래프 검증
        let allRegistrations = await builder.getRegistrations()
        let dependencyGraph = DependencyGraph(registrations: allRegistrations)
        let validation = dependencyGraph.validate()
        
        switch validation {
        case .valid:
            await logger.log(message: "✅ 의존성 그래프 검증 완료", level: .debug)
        case .circular(let cyclePath):
            let error = DependencySetupError.circularDependency(cyclePath)
            await logger.log(message: "🚨 순환 참조 감지: \(cyclePath.joined(separator: " → "))", level: .error)
            throw error
        case .missing(let missingDeps):
            let error = DependencySetupError.missingDependencies(missingDeps)
            await logger.log(message: "🚨 누락된 의존성: \(missingDeps.joined(separator: ", "))", level: .error)
            throw error
        case .invalid(let key, let underlyingError):
            let error = DependencySetupError.invalidConfiguration(key, underlyingError)
            await logger.log(message: "🚨 잘못된 설정: \(key) - \(underlyingError.localizedDescription)", level: .error)
            throw error
        }
        
        // 등록 정보를 스코프별로 분류 + 키→스코프 인덱스 구성
        keyScopeIndex.removeAll(keepingCapacity: true)
        for (key, registration) in allRegistrations {
            let scope = registration.scope
            if scopeRegistrations[scope] == nil {
                scopeRegistrations[scope] = [:]
            }
            scopeRegistrations[scope]![key] = registration
            
            // PHASE2: 키 -> 스코프 인덱스 빌드
            let keyId = ObjectIdentifier(key.keyType)
            keyScopeIndex[keyId] = scope
        }
        
        await logger.log(
            message: "✅ 등록 정보 수집 완료 - 스코프별 분류: \(scopeRegistrations.keys.map { "\($0)" }.joined(separator: ", "))",
            level: .debug
        )
    }
    
    /// 지정된 스코프를 활성화합니다.
    /// startup 스코프의 경우 병렬 초기화를 수행합니다.
    private func activateScope(_ scope: Scope) async throws {
        guard !activatedScopes.contains(scope) else {
            return // 이미 활성화됨
        }
        
        await logger.log(message: "🚀 스코프 활성화 시작: \(scope)", level: .debug)
        
        // 의존성이 있는 스코프들을 먼저 활성화
        let dependencies = getScopeDependencies(scope)
        for dependency in dependencies {
            if !activatedScopes.contains(dependency) {
                try await activateScope(dependency)
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
        
        // startup 스코프의 경우 병렬 초기화 진행률 추적
        if scope == .startup {
            let container = try await builder.build()

            // startup 스코프 병렬 초기화 실행
            await logger.log(message: "🔄 startup 스코프 병렬 초기화 시작", level: .info)

            let result = await startupCoordinator.initializeStartupServices(
                registrations: registrations,
                container: container
            )

            // 병렬 초기화 결과 처리
            switch result {
            case .success(let metrics):
                await logger.log(
                    message: "✅ startup 병렬 초기화 성공 - \(String(format: "%.2f", metrics.totalStartupTime * 1000))ms, 효율성: \(String(format: "%.1f", metrics.parallelizationEfficiency * 100))%",
                    level: .info
                )

                // 상세 메트릭 로깅 (개발 환경에서만)
                if WeaverEnvironment.isDevelopment {
                    await logger.log(
                        message:
                          "📈 병렬 초기화 메트릭 - " +
                          "계층: \(metrics.layersCount), " +
                          "서비스: \(metrics.servicesCount), " +
                          "병렬효율: \(Int(metrics.parallelizationEfficiency * 100))%, " +
                          "총: \(metrics.totalStartupTime)s / 순차: \(metrics.serializedTime)s",
                        level: .debug
                    )
                }

            case .partialFailure(let successful, let failed, let metrics):
                await logger.log(
                    message: "⚠️ startup 부분 초기화 실패 - 성공: \(successful.count), 실패: \(failed.count), 시간: \(String(format: "%.2f", metrics.totalStartupTime * 1000))ms",
                    level: .error
                )

                // 실패한 서비스들 로깅
                for (key, error) in failed {
                    await logger.log(
                        message: "❌ 서비스 초기화 실패: \(key.description) - \(error.localizedDescription)",
                        level: .error
                    )
                }

                // 부분 실패는 에러로 전파하지 않고 계속 진행
                // (핵심이 아닌 서비스의 실패로 전체 앱이 시작되지 않는 것을 방지)

            case .failure(let error, let metrics):
                await logger.log(
                    message: "🚨 startup 병렬 초기화 실패: \(error.localizedDescription) (시간: \(String(format: "%.2f", metrics.totalStartupTime * 1000))ms)",
                    level: .error
                )
                throw error
            }

            scopeContainers[scope] = container

        } else {
            // 다른 스코프는 기존 방식으로 초기화
            let container = try await builder.build()
            scopeContainers[scope] = container
        }
        
        activatedScopes.insert(scope)
        
        await logger.log(message: "✅ 스코프 활성화 완료: \(scope)", level: .debug)
    }
    
    /// 의존성 해결 시 스코프 검색 우선순위를 반환합니다.
    /// 중요도가 높고 안정적인 스코프부터 검색합니다.
    private func getResolutionSearchOrder() -> [Scope] {
        return [
            .startup,     // 1순위: 앱 필수 서비스
            .shared,      // 2순위: 공유 서비스  
            .whenNeeded,  // 3순위: 지연 로딩 서비스
            .weak,        // 4순위: 약한 참조 서비스
            .transient    // 5순위: 일회성 서비스 (실제로는 캐시되지 않으므로 검색 의미 없음)
        ]
    }
    
    /// 타입 기반 편의 API에서 제공된 직접 기본값을 찾아 반환합니다.
    /// 타입 안전성을 보장하기 위해 캐스팅을 수행합니다.
    private func getDirectDefaultValue<T>(for key: AnyDependencyKey, as targetType: T.Type) async -> T? {
        // 모든 스코프에서 해당 키의 등록 정보 검색
        for (_, registrations) in scopeRegistrations {
            if let registration = registrations[key],
               let directDefault = registration.directDefaultValue {
                // 타입 안전한 캐스팅 시도
                if let typedDefault = directDefault as? T {
                    return typedDefault
                } else {
                    await logger.log(
                        message: "⚠️ Direct default value type mismatch for \(key.description): expected \(targetType), got \(type(of: directDefault))",
                        level: .error
                    )
                }
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
        case .transient:
            return [] // 독립적 - 다른 스코프에 의존하지 않음
        }
    }
    
    /// 스코프 종료 우선순위를 반환합니다 (높을수록 먼저 종료).
    private func getScopeShutdownPriority(_ scope: Scope) -> Int {
        switch scope {
        case .transient:
            return 4 // 가장 먼저 종료 (캐시되지 않으므로 실제로는 종료할 것이 없음)
        case .whenNeeded:
            return 3
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
        let oldState = currentLifecycleState
        currentLifecycleState = newState
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

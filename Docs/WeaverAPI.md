Weaver 라이브러리 Public API 문서
📚 목차
핵심 프로토콜
의존성 주입 컨테이너
빌더 패턴
커널 시스템
Property Wrapper
SwiftUI 통합
에러 처리
성능 모니터링
유틸리티
핵심 프로토콜
DependencyKey
의존성을 정의하는 키 타입에 대한 프로토콜입니다.

public protocol DependencyKey: Sendable {
    associatedtype Value: Sendable
    static var defaultValue: Value { get }
}
사용 예시:

struct LoggerKey: DependencyKey {
    typealias Value = Logger
    static var defaultValue: Logger { ConsoleLogger() }
}
Resolver
의존성을 해결하는 기능을 정의하는 프로토콜입니다.

public protocol Resolver: Sendable {
    func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value
}
Module
관련 의존성들을 그룹화하고 등록 로직을 모듈화하기 위한 프로토콜입니다.

public protocol Module: Sendable {
    func configure(_ builder: WeaverBuilder) async
}
사용 예시:

struct NetworkModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(NetworkServiceKey.self) { _ in
            URLSessionNetworkService()
        }
    }
}
Disposable
컨테이너 소멸 시 정리 작업이 필요한 인스턴스가 채택하는 프로토콜입니다.

public protocol Disposable: Sendable {
    func dispose() async throws
}
의존성 주입 컨테이너
WeaverContainer
비동기 의존성 주입 컨테이너입니다.

public actor WeaverContainer: Resolver {
    // 빌더 패턴으로 컨테이너 생성
    public static func builder() -> WeaverBuilder
    
    // 의존성 해결
    public func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value
    
    // 성능 메트릭 조회
    public func getMetrics() async -> ResolutionMetrics
    
    // 컨테이너 종료
    public func shutdown() async
    
    // 메모리 정리
    public func performMemoryCleanup(forced: Bool = false) async
    
    // 자식 컨테이너 생성
    public func reconfigure(with modules: [Module]) async -> WeaverContainer
    
    // 앱 생명주기 이벤트 처리
    public func handleAppDidEnterBackground() async
    public func handleAppWillEnterForeground() async
}
WeaverSyncContainer
동기적 등록과 지연 생성을 지원하는 DI 컨테이너입니다.

public final class WeaverSyncContainer: Sendable {
    // 빌더 패턴으로 컨테이너 생성
    public static func builder() -> WeaverSyncBuilder
    
    // 동기적 의존성 해결 (캐시된 경우만)
    public func resolveSync<Key: DependencyKey>(_ keyType: Key.Type) -> Key.Value?
    
    // 비동기 의존성 해결
    public func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value
    
    // 안전한 의존성 해결 (실패시 기본값)
    public func safeResolve<Key: DependencyKey>(_ keyType: Key.Type) async -> Key.Value
}
빌더 패턴
WeaverBuilder
WeaverContainer를 생성하기 위한 빌더 액터입니다.

public actor WeaverBuilder {
    public init()
    
    // 의존성 등록
    @discardableResult
    public func register<Key: DependencyKey>(
        _ keyType: Key.Type,
        scope: Scope = .container,
        timing: InitializationTiming = .onDemand,
        dependencies: [String] = [],
        factory: @escaping @Sendable (Resolver) async throws -> Key.Value
    ) -> Self
    
    // 약한 참조 의존성 등록 (클래스 타입만)
    @discardableResult
    public func registerWeak<Key: DependencyKey>(
        _ keyType: Key.Type,
        timing: InitializationTiming = .onDemand,
        dependencies: [String] = [],
        factory: @escaping @Sendable (Resolver) async throws -> Key.Value
    ) -> Self where Key.Value: AnyObject
    
    // 모듈 추가
    @discardableResult
    public func withModules(_ modules: [Module]) -> Self
    
    // 부모 컨테이너 설정
    @discardableResult
    public func withParent(_ container: WeaverContainer) -> Self
    
    // 로거 설정
    @discardableResult
    public func withLogger(_ logger: WeaverLogger) -> Self
    
    // 의존성 오버라이드 (테스트용)
    @discardableResult
    public func override<Key: DependencyKey>(
        _ keyType: Key.Type,
        scope: Scope = .container,
        factory: @escaping @Sendable (Resolver) async throws -> Key.Value
    ) -> Self
    
    // 컨테이너 빌드
    public func build() async -> WeaverContainer
    public func build(onAppServiceProgress: @escaping @Sendable (Double) async -> Void) async -> WeaverContainer
}
WeaverSyncBuilder
WeaverSyncContainer를 생성하기 위한 동기 빌더입니다.

public final class WeaverSyncBuilder: Sendable {
    public init()
    
    // 의존성 등록
    @discardableResult
    public func register<Key: DependencyKey>(
        _ keyType: Key.Type,
        scope: Scope = .container,
        timing: InitializationTiming = .onDemand,
        factory: @escaping @Sendable (any Resolver) async throws -> Key.Value
    ) -> Self
    
    // 약한 참조 등록
    @discardableResult
    public func registerWeak<Key: DependencyKey>(
        _ keyType: Key.Type,
        timing: InitializationTiming = .onDemand,
        factory: @escaping @Sendable (any Resolver) async throws -> Key.Value
    ) -> Self where Key.Value: AnyObject
    
    // 모듈 추가
    @discardableResult
    public func withModules(_ modules: [SyncModule]) -> Self
    
    // 컨테이너 빌드
    public func build() -> WeaverSyncContainer
}
커널 시스템
WeaverKernel
Weaver DI 시스템의 통합 커널입니다.

public actor WeaverKernel: WeaverKernelProtocol, Resolver {
    // 초기화 전략
    public enum InitializationStrategy: Sendable {
        case immediate      // 즉시 모든 의존성 초기화
        case realistic     // 동기 시작 + 지연 초기화 (권장)
    }
    
    // 초기화
    public init(
        modules: [Module], 
        strategy: InitializationStrategy = .realistic,
        logger: WeaverLogger = DefaultLogger()
    )
    
    // 편의 생성자
    public static func immediate(modules: [Module], logger: WeaverLogger = DefaultLogger()) -> WeaverKernel
    public static func realistic(modules: [Module], logger: WeaverLogger = DefaultLogger()) -> WeaverKernel
    
    // LifecycleManager 구현
    public var stateStream: AsyncStream<LifecycleState> { get }
    public func build() async
    public func shutdown() async
    
    // SafeResolver 구현
    public var currentState: LifecycleState { get async }
    public func safeResolve<Key: DependencyKey>(_ keyType: Key.Type) async -> Key.Value
    public func waitForReady(timeout: TimeInterval?) async throws -> any Resolver
    
    // Resolver 구현
    public func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value
}
LifecycleState
컨테이너의 생명주기 상태를 나타내는 열거형입니다.

public enum LifecycleState: Sendable, Equatable {
    case idle
    case configuring
    case warmingUp(progress: Double)
    case ready(Resolver)
    case failed(any Error & Sendable)
    case shutdown
}
Property Wrapper
@Inject
의존성을 선언하고 주입받기 위한 프로퍼티 래퍼입니다.

@propertyWrapper
public struct Inject<Key: DependencyKey>: Sendable {
    public init(_ keyType: Key.Type)
    
    public var wrappedValue: Self { get }
    public var projectedValue: InjectProjection<Key> { get }
    
    // 안전한 의존성 접근 (크래시 없음)
    public func callAsFunction() async -> Key.Value
}

public struct InjectProjection<Key: DependencyKey>: Sendable {
    // 에러를 던지는 의존성 해결
    public func resolve() async throws -> Key.Value
}
사용 예시:

class MyService {
    @Inject(LoggerKey.self) private var logger
    @Inject(NetworkServiceKey.self) private var networkService
    
    func doSomething() async {
        // 안전한 접근 (기본값 반환)
        let log = await logger()
        await log.info("작업 시작")
        
        // 에러 처리 접근
        do {
            let network = try await $networkService.resolve()
            let data = try await network.fetchData()
        } catch {
            await log.error("네트워크 오류: \(error)")
        }
    }
}
SwiftUI 통합
View Extensions
SwiftUI View에 Weaver DI 컨테이너를 통합하는 확장입니다.

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public extension View {
    func weaver(
        modules: [Module],
        setAsGlobal: Bool = true,
        @ViewBuilder loadingView: @escaping () -> some View = { /* 기본 로딩 뷰 */ }
    ) -> some View
}
사용 예시:

struct ContentView: View {
    var body: some View {
        Text("Hello, World!")
            .weaver(modules: [
                NetworkModule(),
                LoggingModule()
            ]) {
                ProgressView("의존성 로딩 중...")
            }
    }
}
PreviewWeaverContainer
SwiftUI Preview 환경에서 안전한 DI 컨테이너를 제공하는 헬퍼입니다.

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct PreviewWeaverContainer {
    public static func previewModule<Key: DependencyKey>(
        _ keyType: Key.Type,
        mockValue: Key.Value
    ) -> Module
    
    public static func previewModules(_ registrations: [(any DependencyKey.Type, any Sendable)]) -> [Module]
}
에러 처리
WeaverError
Weaver 라이브러리에서 발생하는 최상위 에러 타입입니다.

public enum WeaverError: Error, LocalizedError, Sendable, Equatable {
    case containerNotFound
    case containerNotReady(currentState: LifecycleState)
    case containerFailed(underlying: any Error & Sendable)
    case resolutionFailed(ResolutionError)
    case shutdownInProgress
    case initializationTimeout(timeoutDuration: TimeInterval)
    case dependencyResolutionFailed(keyName: String, currentState: LifecycleState, underlying: any Error & Sendable)
    case criticalDependencyFailed(keyName: String, underlying: any Error & Sendable)
    case memoryPressureDetected(availableMemory: UInt64)
    case appLifecycleEventFailed(event: String, keyName: String, underlying: any Error & Sendable)
    
    public var errorDescription: String? { get }
    public var debugDescription: String { get }
}
ResolutionError
의존성 해결 과정에서 발생하는 구체적인 에러 타입입니다.

public enum ResolutionError: Error, LocalizedError, Sendable, Equatable {
    case circularDependency(path: String)
    case factoryFailed(keyName: String, underlying: any Error & Sendable)
    case typeMismatch(expected: String, actual: String, keyName: String)
    case keyNotFound(keyName: String)
    case weakObjectDeallocated(keyName: String)
    
    public var errorDescription: String? { get }
}
성능 모니터링
WeaverPerformanceMonitor
Weaver DI 시스템의 성능을 모니터링하는 액터입니다.

public actor WeaverPerformanceMonitor {
    public init(enabled: Bool = WeaverEnvironment.isDevelopment, logger: WeaverLogger = DefaultLogger())
    
    // 의존성 해결 성능 측정
    public func measureResolution<T: Sendable>(
        keyName: String,
        operation: @Sendable () async throws -> T
    ) async rethrows -> T
    
    // 메모리 사용량 기록
    public func recordMemoryUsage() async
    
    // 성능 보고서 생성
    public func generatePerformanceReport() async -> PerformanceReport
    
    // 성능 데이터 초기화
    public func reset() async
}
PerformanceReport
성능 모니터링 결과를 담는 구조체입니다.

public struct PerformanceReport: Sendable, CustomStringConvertible {
    public let averageResolutionTime: TimeInterval
    public let slowResolutions: [(keyName: String, duration: TimeInterval)]
    public let totalResolutions: Int
    public let averageMemoryUsage: UInt64
    public let peakMemoryUsage: UInt64
    
    public var description: String { get }
}
유틸리티
Weaver (전역 접근 인터페이스)
편의를 위한 전역 접근 인터페이스입니다.

public enum Weaver {
    // 현재 컨테이너 접근
    public static var current: WeaverContainer? { get async }
    
    // 커널 상태 조회
    public static var currentKernelState: LifecycleState { get async }
    
    // 전역 커널 관리
    public static func setGlobalKernel(_ kernel: (any WeaverKernelProtocol)?) async
    public static func getGlobalKernel() async -> (any WeaverKernelProtocol)?
    
    // 안전한 의존성 해결
    public static func safeResolve<Key: DependencyKey>(_ keyType: Key.Type) async -> Key.Value
    
    // 준비 상태 대기
    public static func waitForReady() async throws -> any Resolver
    
    // 스코프 관리
    public static var scopeManager: DependencyScope { get async }
    public static func setScopeManager(_ manager: DependencyScope) async
    public static func withScope<R: Sendable>(_ container: WeaverContainer, operation: @Sendable () async throws -> R) async rethrows -> R
    
    // 앱 생명주기 이벤트 처리
    public static func handleAppLifecycleEvent(_ event: AppLifecycleEvent) async
    
    // 앱 초기화
    public static func initializeForApp(modules: [Module], strategy: WeaverKernel.InitializationStrategy = .realistic) async throws
    public static func setupRealistic(modules: [Module]) async -> WeaverKernel
    
    // 테스트 지원
    public static func resetForTesting() async
}
WeaverEnvironment
환경 관련 유틸리티를 제공하는 네임스페이스입니다.

public enum WeaverEnvironment {
    public static var isPreview: Bool { get }
    public static var isDevelopment: Bool { get }
    public static var isTesting: Bool { get }
}
DefaultValueGuidelines
DependencyKey의 defaultValue 설계를 위한 가이드라인과 유틸리티입니다.

public enum DefaultValueGuidelines {
    public static func safeDefault<T>(
        production: @autoclosure () -> T,
        preview: @autoclosure () -> T
    ) -> T
    
    public static func debugDefault<T>(
        debug: @autoclosure () -> T,
        release: @autoclosure () -> T
    ) -> T
}
WeakBox
Swift 6 동시성 환경에서 약한 참조를 안전하게 관리하는 패턴입니다.

public actor WeakBox<T: AnyObject & Sendable>: Sendable {
    public init(_ value: T)
    
    public var isAlive: Bool { get }
    public func getValue() -> T?
    public var age: TimeInterval { get }
    public var debugDescription: String { get }
}

public actor WeakBoxCollection<Key: Hashable, Value: AnyObject & Sendable>: Sendable {
    public func set(_ value: Value, for key: Key)
    public func get(for key: Key) async -> Value?
    public func cleanup() async -> Int
    public func getMetrics() async -> WeakReferenceMetrics
    public func removeAll()
}
PlatformAppropriateLock
iOS 15/16 호환 잠금 메커니즘입니다.

public struct PlatformAppropriateLock<State: Sendable>: Sendable {
    public init(initialState: State)
    
    @inlinable
    public func withLock<R>(_ body: (inout State) throws -> R) rethrows -> R
    
    public var lockMechanismInfo: String { get }
    
    #if DEBUG
    public func withLockForTesting<R>(_ body: (State) throws -> R) rethrows -> R
    #endif
}
📋 타입 정의
Scope
의존성의 생명주기를 정의하는 스코프 타입입니다.

public enum Scope: String, Sendable {
    case container      // 컨테이너 생명주기 동안 단일 인스턴스
    case weak          // 약한 참조로 관리
    case cached        // 캐시 정책에 따라 관리
    case appService    // 앱 전체 핵심 서비스
    case bootstrap     // 부트스트랩 레이어
    case core          // 코어 레이어
    case feature       // 피처 레이어
}
InitializationTiming
의존성의 초기화 시점을 정의하는 열거형입니다.

public enum InitializationTiming: String, Sendable, CaseIterable {
    case eager         // 앱 시작과 함께 백그라운드에서 초기화
    case background    // 메인 화면 표시를 위해 백그라운드에서 초기화
    case onDemand      // 실제 사용할 때만 초기화 (기본값)
    case lazy          // 지연 초기화 (레거시 호환성)
}
ResolutionMetrics
의존성 해결 통계 정보를 담는 구조체입니다.

public struct ResolutionMetrics: Sendable, CustomStringConvertible {
    public let totalResolutions: Int
    public let cacheHits: Int
    public let cacheMisses: Int
    public let averageResolutionTime: TimeInterval
    public let failedResolutions: Int
    public let weakReferences: WeakReferenceMetrics
    
    public var cacheHitRate: Double { get }
    public var successRate: Double { get }
    public var description: String { get }
}
🚀 사용 예시
기본 설정
// 1. 의존성 키 정의
struct LoggerKey: DependencyKey {
    typealias Value = Logger
    static var defaultValue: Logger { ConsoleLogger() }
}

// 2. 모듈 정의
struct AppModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(LoggerKey.self) { _ in
            ProductionLogger()
        }
    }
}

// 3. 앱 초기화
@main
struct MyApp: App {
    init() {
        Task {
            try await Weaver.initializeForApp(modules: [AppModule()])
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .weaver(modules: [AppModule()])
        }
    }
}

// 4. 의존성 사용
class MyService {
    @Inject(LoggerKey.self) private var logger
    
    func doWork() async {
        let log = await logger()
        await log.info("작업 완료")
    }
}

이 문서는 Weaver 라이브러리의 모든 public API를 포괄적으로 다루며, 실제 사용 시 참고할 수 있는 완전한 레퍼런스입니다.

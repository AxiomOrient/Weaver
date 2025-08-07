// Tests/WeaverTests/WeaverTestBase.swift

import Foundation
@testable import Weaver

// MARK: - ==================== Test Errors & Utilities ====================
// LANGUAGE.md Section 5: 구조화된 에러 처리 준수
// GEMINI.md Article 10: 명확한 에러 정보 전파

/// 테스트에서 사용되는 구조화된 에러 타입
/// LANGUAGE.md Section 5 Rule 5_1: 구조화된 에러 처리 패턴 준수
enum TestError: Error, Sendable, Equatable, LocalizedError {
    case factoryFailed
    case intentionalError
    case timeoutExceeded(Duration)
    case invalidTestState(String)
    case mockSetupFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .factoryFailed:
            return "팩토리 생성 실패"
        case .intentionalError:
            return "의도적인 테스트 에러"
        case .timeoutExceeded(let duration):
            return "타임아웃 초과: \(duration)"
        case .invalidTestState(let reason):
            return "잘못된 테스트 상태: \(reason)"
        case .mockSetupFailed(let reason):
            return "모의 객체 설정 실패: \(reason)"
        }
    }
}

/// 팩토리 호출 횟수를 동시성 환경에서 안전하게 추적하기 위한 액터
/// LANGUAGE.md Section 6 Rule 6_2: Actor를 통한 데이터 보호 패턴 준수
actor FactoryCallCounter {
    private(set) var count = 0
    private(set) var callTimestamps: [Date] = []
    
    func increment() {
        count += 1
        callTimestamps.append(Date())
    }
    
    func reset() {
        count = 0
        callTimestamps.removeAll()
    }
    
    /// 마지막 호출 이후 경과 시간을 반환합니다
    func timeSinceLastCall() -> TimeInterval? {
        guard let lastCall = callTimestamps.last else { return nil }
        return Date().timeIntervalSince(lastCall)
    }
    
    /// 지정된 시간 내의 호출 횟수를 반환합니다
    func callsWithin(_ timeInterval: TimeInterval) -> Int {
        let cutoffTime = Date().addingTimeInterval(-timeInterval)
        return callTimestamps.filter { $0 > cutoffTime }.count
    }
}

/// 비동기 테스트에서 특정 작업의 완료를 기다리기 위한 동기화 유틸리티
/// LANGUAGE.md Section 6 Rule 6_1: async/await 우선 사용 패턴 준수
actor TestSignal {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isSignaled = false
    private var signalCount = 0
    private let createdAt = Date()

    func signal() {
        signalCount += 1
        if let continuation {
            continuation.resume()
            self.continuation = nil
        } else {
            isSignaled = true
        }
    }

    func wait(timeout: Duration = .seconds(1)) async throws {
        if isSignaled {
            isSignaled = false
            return
        }
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    Task { await self.setContinuation(continuation) }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw TestError.timeoutExceeded(timeout)
            }
            
            // 첫 번째 완료된 작업만 기다림
            try await group.next()
            group.cancelAll()
        }
    }
    
    /// 여러 번의 시그널을 기다립니다
    func waitForSignals(count: Int, timeout: Duration = .seconds(5)) async throws {
        let startTime = Date()
        
        while signalCount < count {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > timeout.timeInterval {
                throw TestError.timeoutExceeded(timeout)
            }
            
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    
    /// 현재 시그널 상태를 반환합니다
    func getStatus() -> (signaled: Bool, count: Int, age: TimeInterval) {
        return (isSignaled, signalCount, Date().timeIntervalSince(createdAt))
    }

    private func setContinuation(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = self.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}


// MARK: - ==================== Test Services & Protocols ====================
// LANGUAGE.md Section 2 Rule 2_1: 단일 책임 원칙 준수
// LANGUAGE.md Section 4 Rule 4_2: 값 타입 우선 원칙 적용

/// 테스트용 서비스의 기본 프로토콜
/// 모든 테스트 서비스는 추적 가능한 ID와 기본값 여부를 제공해야 함
protocol Service: Sendable {
    var id: UUID { get }
    var isDefaultValue: Bool { get }
    var createdAt: Date { get }
}

/// 기본 테스트 서비스 구현
/// LANGUAGE.md Section 4 Rule 4_2: 값 타입 우선이지만 참조 추적을 위해 클래스 사용
final class TestService: Service {
    let id = UUID()
    let isDefaultValue: Bool
    let createdAt = Date()
    private let metadata: ServiceMetadata
    
    init(isDefaultValue: Bool = false, metadata: ServiceMetadata = ServiceMetadata()) {
        self.isDefaultValue = isDefaultValue
        self.metadata = metadata
    }
    
    /// 서비스의 생성 시점부터 경과된 시간을 반환합니다
    func ageInSeconds() -> TimeInterval {
        Date().timeIntervalSince(createdAt)
    }
    
    /// 서비스 메타데이터를 반환합니다
    func getMetadata() -> ServiceMetadata {
        metadata
    }
}

/// 서비스 생성 시 추가 정보를 담는 구조체
struct ServiceMetadata: Sendable {
    let version: String
    let environment: String
    let features: Set<String>
    
    init(version: String = "1.0.0", environment: String = "test", features: Set<String> = []) {
        self.version = version
        self.environment = environment
        self.features = features
    }
}

/// 다른 타입의 테스트 서비스 (타입 안전성 테스트용)
final class AnotherService: Service {
    let id = UUID()
    let isDefaultValue: Bool = false
    let createdAt = Date()
    let serviceType = "AnotherService"
    
    init() {}
}

/// 약한 참조 테스트용 서비스
/// LANGUAGE.md Section 4 Rule 4_1: ARC 최적화를 고려한 설계
final class WeakService: Service {
    let id = UUID()
    let isDefaultValue: Bool
    let createdAt = Date()
    private let onDeallocate: (@Sendable () -> Void)?
    
    init(isDefaultValue: Bool = false, onDeallocate: (@Sendable () -> Void)? = nil) {
        self.isDefaultValue = isDefaultValue
        self.onDeallocate = onDeallocate
    }
    
    deinit {
        onDeallocate?()
    }
}

/// 리소스 정리가 필요한 테스트 서비스
/// LANGUAGE.md Section 5 Rule 5_1: 구조화된 에러 처리 적용
final class DisposableService: Service, Disposable {
    let id = UUID()
    let isDefaultValue: Bool = false
    let createdAt = Date()
    private let onDispose: @Sendable () async -> Void

    init(onDispose: @escaping @Sendable () async -> Void = {}) {
        self.onDispose = onDispose
    }

    func dispose() async throws {
        await onDispose()
    }
}

final class CircularServiceA: Service {
    let id = UUID()
    let isDefaultValue: Bool = false
    let createdAt = Date()
    let serviceB: any Service
    
    init(serviceB: any Service) {
        self.serviceB = serviceB
    }
}

final class CircularServiceB: Service {
    let id = UUID()
    let isDefaultValue: Bool = false
    let createdAt = Date()
    let serviceA: any Service
    
    init(serviceA: any Service) {
        self.serviceA = serviceA
    }
}


// MARK: - ==================== Test Dependency Keys ====================
// LANGUAGE.md Section 3 Rule 3_1: 명확한 네이밍 컨벤션 준수

struct ServiceKey: DependencyKey {
    static var defaultValue: TestService { TestService(isDefaultValue: true) }
}

// 실제 앱 서비스들을 시뮬레이션하는 키들
struct LoggerServiceKey: DependencyKey {
    static var defaultValue: LoggerService { LoggerService(level: .info) }
}

struct NetworkServiceKey: DependencyKey {
    static var defaultValue: NetworkService { 
        NetworkService(logger: LoggerService(level: .info), baseURL: "https://default.com") 
    }
}

struct DatabaseServiceKey: DependencyKey {
    static var defaultValue: DatabaseService { 
        DatabaseService(logger: LoggerService(level: .info), connectionString: "default://localhost") 
    }
}

struct CameraServiceKey: DependencyKey {
    static var defaultValue: CameraService { 
        CameraService(logger: LoggerService(level: .info)) 
    }
}

struct LocationServiceKey: DependencyKey {
    static var defaultValue: LocationService { 
        LocationService(logger: LoggerService(level: .info)) 
    }
}

struct AnotherServiceKey: DependencyKey {
    static var defaultValue: AnotherService { AnotherService() }
}

struct WeakServiceKey: DependencyKey {
    static var defaultValue: WeakService { WeakService(isDefaultValue: true) }
}

struct DisposableServiceKey: DependencyKey {
    static var defaultValue: DisposableService { DisposableService(onDispose: {}) }
}

struct CircularAKey: DependencyKey {
    static var defaultValue: CircularServiceA { CircularServiceA(serviceB: TestService(isDefaultValue: true)) }
}

struct CircularBKey: DependencyKey {
    static var defaultValue: CircularServiceB { CircularServiceB(serviceA: TestService(isDefaultValue: true)) }
}


// MARK: - ==================== Test Modules ====================
// LANGUAGE.md Section 2 Rule 2_2: 개방-폐쇄 원칙 적용

/// 특정 스코프에 서비스를 등록하는 간단한 모듈
/// LANGUAGE.md Section 2 Rule 2_1: 단일 책임 원칙 - 하나의 서비스만 등록
struct TestModule: Module {
    let scope: Scope
    let factory: @Sendable (Resolver) async throws -> any Service
    let metadata: ModuleMetadata
    
    init(
        scope: Scope, 
        factory: @escaping @Sendable (Resolver) async throws -> any Service,
        metadata: ModuleMetadata = ModuleMetadata()
    ) {
        self.scope = scope
        self.factory = factory
        self.metadata = metadata
    }
    
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(ServiceKey.self, scope: scope) { resolver in
            try await factory(resolver) as! TestService
        }
    }
}

/// 모듈의 메타데이터를 담는 구조체
struct ModuleMetadata: Sendable {
    let name: String
    let version: String
    let dependencies: [String]
    
    init(name: String = "TestModule", version: String = "1.0.0", dependencies: [String] = []) {
        self.name = name
        self.version = version
        self.dependencies = dependencies
    }
}

/// 제네릭 테스트 모듈 (다양한 키 타입 지원)
struct GenericTestModule<Key: DependencyKey>: Module {
    let key: Key.Type
    let scope: Scope
    let factory: @Sendable (Resolver) async throws -> Key.Value
    
    init(key: Key.Type, scope: Scope, factory: @escaping @Sendable (Resolver) async throws -> Key.Value) {
        self.key = key
        self.scope = scope
        self.factory = factory
    }
    
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(key, scope: scope, factory: factory)
    }
}

/// 새로운 스코프 시스템을 테스트하기 위한 모듈들
struct StartupModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(ServiceKey.self, scope: .startup) { _ in
            TestService(isDefaultValue: false)
        }
    }
}

struct SharedModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(ServiceKey.self, scope: .shared) { _ in
            TestService(isDefaultValue: false)
        }
    }
}

struct WhenNeededModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(ServiceKey.self, scope: .whenNeeded) { _ in
            TestService(isDefaultValue: false)
        }
    }
}

struct WeakModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.registerWeak(WeakServiceKey.self) { _ in
            WeakService(isDefaultValue: false)
        }
    }
}

/// 순환 참조를 유발하는 모듈 (에러 테스트용)
struct CircularDependencyModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(CircularAKey.self) { resolver in
            let serviceB = try await resolver.resolve(CircularBKey.self)
            return CircularServiceA(serviceB: serviceB)
        }
        await builder.register(CircularBKey.self) { resolver in
            let serviceA = try await resolver.resolve(CircularAKey.self)
            return CircularServiceB(serviceA: serviceA)
        }
    }
}

/// 실제 앱의 로깅 모듈을 시뮬레이션하는 테스트 모듈
struct LoggingModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(LoggerServiceKey.self, scope: .startup) { _ in
            LoggerService(level: .debug)
        }
    }
}

/// 실제 앱의 네트워크 모듈을 시뮬레이션하는 테스트 모듈
struct NetworkModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(NetworkServiceKey.self, scope: .shared) { resolver in
            let logger = try await resolver.resolve(LoggerServiceKey.self)
            return NetworkService(logger: logger, baseURL: "https://api.test.com")
        }
    }
}

/// 실제 앱의 데이터베이스 모듈을 시뮬레이션하는 테스트 모듈
struct DatabaseModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(DatabaseServiceKey.self, scope: .shared) { resolver in
            let logger = try await resolver.resolve(LoggerServiceKey.self)
            return DatabaseService(logger: logger, connectionString: "test://localhost")
        }
    }
}

/// 기능별 서비스 모듈 (whenNeeded 스코프 테스트용)
struct FeatureModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(CameraServiceKey.self, scope: .whenNeeded) { resolver in
            let logger = try await resolver.resolve(LoggerServiceKey.self)
            return CameraService(logger: logger)
        }
        
        await builder.register(LocationServiceKey.self, scope: .whenNeeded) { resolver in
            let logger = try await resolver.resolve(LoggerServiceKey.self)
            return LocationService(logger: logger)
        }
    }
}


// MARK: - ==================== Test Helpers & Factories ====================

extension WeaverTestBase {
    /// 테스트용 커널을 생성하는 헬퍼
    static func makeTestKernel(modules: [Module]) -> WeaverKernel {
        return WeaverKernel.scoped(modules: modules)
    }
    
    /// 테스트용 컨테이너 빌더를 생성하는 헬퍼
    static func makeTestBuilder() -> WeaverBuilder {
        return WeaverContainer.builder()
    }
}

// MARK: - ==================== 실제 앱 서비스 시뮬레이션 ====================

/// 로깅 서비스 시뮬레이션
final class LoggerService: Service, AppLifecycleAware {
    let id = UUID()
    let isDefaultValue: Bool = false
    let createdAt = Date()
    let level: LogLevel
    
    enum LogLevel: String, Sendable {
        case debug, info, warning, error
    }
    
    init(level: LogLevel) {
        self.level = level
    }
    
    func log(_ message: String, level: LogLevel = .info) {
        print("[\(level.rawValue.uppercased())] \(message)")
    }
    
    func appDidEnterBackground() async throws {
        log("Logger entering background mode", level: .info)
    }
    
    func appWillEnterForeground() async throws {
        log("Logger entering foreground mode", level: .info)
    }
    
    func appWillTerminate() async throws {
        log("Logger shutting down", level: .info)
    }
}

/// 네트워크 서비스 시뮬레이션
final class NetworkService: Service, AppLifecycleAware, Disposable {
    let id = UUID()
    let isDefaultValue: Bool = false
    let createdAt = Date()
    let baseURL: String
    private let logger: LoggerService
    
    init(logger: LoggerService, baseURL: String) {
        self.logger = logger
        self.baseURL = baseURL
        logger.log("NetworkService initialized with baseURL: \(baseURL)")
    }
    
    func fetchData(endpoint: String) async -> String {
        logger.log("Fetching data from \(endpoint)")
        return "network_data_from_\(endpoint)"
    }
    
    func appDidEnterBackground() async throws {
        logger.log("Network connections suspended")
    }
    
    func appWillEnterForeground() async throws {
        logger.log("Network connections resumed")
    }
    
    func appWillTerminate() async throws {
        logger.log("Network service shutting down")
    }
    
    func dispose() async throws {
        logger.log("Network service disposed")
    }
}

/// 데이터베이스 서비스 시뮬레이션
final class DatabaseService: Service, AppLifecycleAware, Disposable {
    let id = UUID()
    let isDefaultValue: Bool = false
    let createdAt = Date()
    let connectionString: String
    private let logger: LoggerService
    
    init(logger: LoggerService, connectionString: String) {
        self.logger = logger
        self.connectionString = connectionString
        logger.log("DatabaseService initialized with connection: \(connectionString)")
    }
    
    func query(_ sql: String) async -> [String] {
        logger.log("Executing query: \(sql)")
        return ["result1", "result2"]
    }
    
    func appDidEnterBackground() async throws {
        logger.log("Database connections minimized")
    }
    
    func appWillEnterForeground() async throws {
        logger.log("Database connections restored")
    }
    
    func appWillTerminate() async throws {
        logger.log("Database service shutting down")
    }
    
    func dispose() async throws {
        logger.log("Database service disposed")
    }
}

/// 카메라 서비스 시뮬레이션 (whenNeeded 스코프)
final class CameraService: Service {
    let id = UUID()
    let isDefaultValue: Bool = false
    let createdAt = Date()
    private let logger: LoggerService
    
    init(logger: LoggerService) {
        self.logger = logger
        logger.log("CameraService initialized (whenNeeded)")
    }
    
    func capturePhoto() async -> String {
        logger.log("Photo captured")
        return "photo_\(id.uuidString)"
    }
}

/// 위치 서비스 시뮬레이션 (whenNeeded 스코프)
final class LocationService: Service {
    let id = UUID()
    let isDefaultValue: Bool = false
    let createdAt = Date()
    private let logger: LoggerService
    
    init(logger: LoggerService) {
        self.logger = logger
        logger.log("LocationService initialized (whenNeeded)")
    }
    
    func getCurrentLocation() async -> String {
        logger.log("Location requested")
        return "37.7749,-122.4194" // San Francisco coordinates
    }
}

/// 테스트 스위트의 기반이 되는 타입 (필요 시 공통 로직 추가)
struct WeaverTestBase {}
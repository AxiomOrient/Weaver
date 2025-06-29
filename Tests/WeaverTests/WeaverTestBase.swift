import Testing
import Foundation
@testable import Weaver

// MARK: - Test Utilities

/// 팩토리(Factory) 실패 테스트에 사용될 커스텀 에러 타입입니다.
enum TestError: Error, Sendable {
    case factoryFailed
}

/// 비동기 테스트에서 특정 작업의 완료를 기다리기 위한 동기화 유틸리티입니다.
actor TestSignal {
    private var continuation: CheckedContinuation<Void, Never>?
    
    /// 대기 중인 `wait()`를 깨우고 다음 작업을 진행하도록 신호를 보냅니다.
    func signal() {
        continuation?.resume()
        continuation = nil
    }
    
    /// `signal()`이 호출될 때까지 비동기적으로 대기합니다.
    func wait() async {
        await withCheckedContinuation { self.continuation = $0 }
    }
}

// MARK: - Test Services & Protocols

/// 모든 테스트 서비스의 기반이 되는 프로토콜입니다.
protocol Service: Sendable {
    /// 모든 서비스 인스턴스를 고유하게 식별하기 위한 ID입니다.
    var id: UUID { get }
}

/// 기본 의존성 주입 테스트를 위한 구현체입니다.
final class TestService: Service, Sendable {
    let id = UUID()
    
    /// 인스턴스 생성 시 호출될 콜백. 팩토리 호출 횟수 추적에 사용됩니다.
    init(onInit: (@Sendable () -> Void)? = nil) {
        onInit?()
    }
}

/// 타입 불일치 및 오버라이드 테스트를 위한 또 다른 서비스 구현체입니다.
final class AnotherService: Service, Sendable {
    let id = UUID()
}

/// 의존성 해결 실패 시 반환될 기본값을 명확히 하기 위한 'Null Object' 패턴 구현체입니다.
final class NullService: Service, Sendable {
    let id = UUID()
}

/// `Disposable` 프로토콜을 준수하는 테스트 서비스입니다.
final class DisposableService: Service, Disposable, Sendable {
    let id = UUID()
    private let onDispose: @Sendable () -> Void
    
    init(onDispose: @escaping @Sendable () -> Void) {
        self.onDispose = onDispose
    }
    
    /// 컨테이너 `shutdown` 시 `onDispose` 클로저를 호출합니다.
    func dispose() async {
        onDispose()
    }
}

/// 순환 참조 테스트를 위한 서비스 A입니다.
final class CircularServiceA: Service, Sendable {
    let id = UUID()
    let serviceB: any Service
    init(serviceB: any Service) {
        self.serviceB = serviceB
    }
}

/// 순환 참조 테스트를 위한 서비스 B입니다.
final class CircularServiceB: Service, Sendable {
    let id = UUID()
    let serviceA: any Service
    init(serviceA: any Service) {
        self.serviceA = serviceA
    }
}

// MARK: - Test Dependency Keys

/// `TestService` 타입에 대한 `DependencyKey`입니다.
struct ServiceKey: DependencyKey {
    typealias Value = TestService
    static var defaultValue: TestService { TestService() }
}

/// `any Service` 프로토콜 타입에 대한 `DependencyKey`입니다.
/// 기본값으로 `NullService`를 사용하여 타입 안정성을 보장합니다.
struct ServiceProtocolKey: DependencyKey {
    typealias Value = any Service
    static var defaultValue: any Service { NullService() }
}

/// `DisposableService` 타입에 대한 `DependencyKey`입니다.
/// 기본값 반환 테스트 목적이 아니므로 `fatalError`로 의도치 않은 사용을 방지합니다.
struct DisposableServiceKey: DependencyKey {
    typealias Value = DisposableService
    static var defaultValue: Value { fatalError("Not intended for default value tests.") }
}

/// `CircularServiceA` 타입에 대한 `DependencyKey`입니다.
struct CircularAKey: DependencyKey {
    typealias Value = CircularServiceA
    static var defaultValue: Value { fatalError("Not intended for default value tests.") }
}

/// `CircularServiceB` 타입에 대한 `DependencyKey`입니다.
struct CircularBKey: DependencyKey {
    typealias Value = CircularServiceB
    static var defaultValue: Value { fatalError("Not intended for default value tests.") }
}


// MARK: - Test Consumers & Modules

/// `@Inject` 프로퍼티 래퍼의 동작을 테스트하기 위한 소비자(Consumer) 액터입니다.
actor ServiceConsumer {
    /// `callAsFunction()`을 사용하여 기본 동작을 테스트하기 위한 프로퍼티입니다.
    @Inject(ServiceProtocolKey.self)
    var aService
    
    /// `@Inject`의 내부 캐싱 동작을 테스트하기 위한 프로퍼티입니다.
    @Inject(ServiceProtocolKey.self)
    var cachedService
    
    /// 실패 시 기본값 반환을 테스트하기 위한 프로퍼티입니다.
    @Inject(ServiceProtocolKey.self)
    var safeServiceWithDefault
    
    /// 실패 시 에러 발생 테스트는 `$strictService.resolved`를 호출하여 검증합니다.
    @Inject(ServiceProtocolKey.self)
    var strictService
    
    init() {}
}

/// 테스트에서 간단하게 익명 모듈을 생성하기 위한 유틸리티 구조체입니다.
struct AnonymousModule: Module {
    let configuration: @Sendable (WeaverBuilder) async -> Void
    
    init(configure: @escaping @Sendable (WeaverBuilder) async -> Void) {
        self.configuration = configure
    }
    
    func configure(_ builder: WeaverBuilder) async {
        await configuration(builder)
    }
}
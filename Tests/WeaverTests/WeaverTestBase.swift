import Testing
import Foundation
@testable import Weaver

// MARK: - Test Utilities

/// 팩토리(Factory) 실패 테스트에 사용될 커스텀 에러 타입입니다.
enum TestError: Error, Sendable {
    case factoryFailed
}

/// 팩토리 호출 횟수를 동시성 환경에서 안전하게 추적하기 위한 액터
actor FactoryCallCounter {
    var count = 0
    func increment() {
        count += 1
    }
}

/// 비동기 테스트에서 특정 작업의 완료를 기다리기 위한 동기화 유틸리티입니다.
actor TestSignal {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isSignaled = false

    /// `wait()`가 호출될 때까지 대기 중인 작업을 깨웁니다.
    /// 만약 `wait()`가 아직 호출되지 않았다면, 신호가 왔음을 기록하여 `wait()`가 즉시 반환되도록 합니다.
    func signal() {
        if let continuation {
            continuation.resume()
            self.continuation = nil
        } else {
            isSignaled = true
        }
    }

    /// `signal()`이 호출될 때까지 비동기적으로 대기합니다.
    func wait() async {
        if isSignaled {
            isSignaled = false
            return
        }
        await withCheckedContinuation { self.continuation = $0 }
    }
}

// MARK: - Test Services & Protocols

/// 모든 테스트 서비스의 기반이 되는 프로토콜입니다.
protocol Service: Sendable {
    /// 모든 서비스 인스턴스를 고유하게 식별하기 위한 ID입니다.
    var id: UUID { get }
    
    /// 이 인스턴스가 기본값인지 여부를 나타냅니다.
    /// 테스트에서 실제 해결된 값과 기본값을 구분하기 위해 사용됩니다.
    var isDefaultValue: Bool { get }
}

/// 기본 의존성 주입 테스트를 위한 구현체입니다.
final class TestService: Service, Sendable {
    let id = UUID()
    
    /// 이 인스턴스가 기본값인지 여부를 나타냅니다.
    /// 테스트에서 실제 해결된 값과 기본값을 구분하기 위해 사용됩니다.
    let isDefaultValue: Bool
    
    /// 인스턴스 생성 시 호출될 콜백. 팩토리 호출 횟수 추적에 사용됩니다.
    init(isDefaultValue: Bool = false, onInit: (@Sendable () async -> Void)? = nil) {
        self.isDefaultValue = isDefaultValue
        Task {
            await onInit?()
        }
    }
}

/// 타입 불일치 및 오버라이드 테스트를 위한 또 다른 서비스 구현체입니다.
final class AnotherService: Service, Sendable {
    let id = UUID()
    let isDefaultValue: Bool
    
    init(isDefaultValue: Bool = false) {
        self.isDefaultValue = isDefaultValue
    }
}

/// 의존성 해결 실패 시 반환될 기본값을 명확히 하기 위한 'Null Object' 패턴 구현체입니다.
final class NullService: Service, Sendable {
    let id = UUID()
    let isDefaultValue: Bool
    
    init(isDefaultValue: Bool = true) { // NullService는 기본적으로 기본값
        self.isDefaultValue = isDefaultValue
    }
}

/// 약한 참조 테스트를 위한 서비스입니다.
final class WeakService: Service, Sendable {
    let id = UUID()
    let isDefaultValue: Bool
    
    init(isDefaultValue: Bool = false) {
        self.isDefaultValue = isDefaultValue
    }
}

/// `Disposable` 프로토콜을 준수하는 테스트 서비스입니다.
final class DisposableService: Service, Disposable, Sendable {
    let id = UUID()
    let isDefaultValue: Bool
    private let onDispose: @Sendable () async -> Void

    init(isDefaultValue: Bool = false, onDispose: @escaping @Sendable () async -> Void) {
        self.isDefaultValue = isDefaultValue
        self.onDispose = onDispose
    }

    /// 컨테이너 `shutdown` 시 `onDispose` 클로저를 호출합니다.
    func dispose() async throws {
        await onDispose()
    }
}

/// 순환 참조 테스트를 위한 서비스 A입니다.
final class CircularServiceA: Service, Sendable {
    let id = UUID()
    let isDefaultValue: Bool
    let serviceB: any Service
    
    init(isDefaultValue: Bool = false, serviceB: any Service) {
        self.isDefaultValue = isDefaultValue
        self.serviceB = serviceB
    }
}

/// 순환 참조 테스트를 위한 서비스 B입니다.
final class CircularServiceB: Service, Sendable {
    let id = UUID()
    let isDefaultValue: Bool
    let serviceA: any Service
    
    init(isDefaultValue: Bool = false, serviceA: any Service) {
        self.isDefaultValue = isDefaultValue
        self.serviceA = serviceA
    }
}

// MARK: - Test Dependency Keys

/// `TestService` 타입에 대한 `DependencyKey`입니다.
/// 테스트에서 실제 해결된 값과 기본값을 구분하기 위해 기본값으로 특별한 마커를 사용합니다.
struct ServiceKey: DependencyKey {
    typealias Value = TestService
    static var defaultValue: TestService { 
        TestService(isDefaultValue: true)
    }
}

/// `any Service` 프로토콜 타입에 대한 `DependencyKey`입니다.
/// 기본값으로 `NullService`를 사용하여 타입 안정성을 보장합니다.
struct ServiceProtocolKey: DependencyKey {
    typealias Value = any Service
    static var defaultValue: any Service { NullService() }
}

/// `WeakService` 타입에 대한 `DependencyKey`입니다.
/// 약한 참조 테스트를 위한 키입니다.
struct WeakServiceKey: DependencyKey {
    typealias Value = WeakService
    static var defaultValue: Value { 
        WeakService(isDefaultValue: true)
    }
}

/// `DisposableService` 타입에 대한 `DependencyKey`입니다.
/// Mock 객체를 기본값으로 제공하여 안전성을 보장합니다.
struct DisposableServiceKey: DependencyKey {
    typealias Value = DisposableService
    static var defaultValue: Value { 
        DisposableService(isDefaultValue: true, onDispose: { /* Mock dispose - 아무것도 하지 않음 */ })
    }
}

/// `CircularServiceA` 타입에 대한 `DependencyKey`입니다.
/// Mock 객체를 기본값으로 제공하여 순환 참조 없이 안전한 기본값을 제공합니다.
struct CircularAKey: DependencyKey {
    typealias Value = CircularServiceA
    static var defaultValue: Value { 
        CircularServiceA(isDefaultValue: true, serviceB: NullService()) // 순환 참조 방지를 위한 Mock
    }
}

/// `CircularServiceB` 타입에 대한 `DependencyKey`입니다.
/// Mock 객체를 기본값으로 제공하여 순환 참조 없이 안전한 기본값을 제공합니다.
struct CircularBKey: DependencyKey {
    typealias Value = CircularServiceB
    static var defaultValue: Value { 
        CircularServiceB(isDefaultValue: true, serviceA: NullService()) // 순환 참조 방지를 위한 Mock
    }
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

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
    
    /// ✅ FIX: `strategy` 파라미터 제거.
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

/*
 실패 원인 종합 분석
 테스트 실패 로그를 종합해 보면 크게 세 가지의 근본적인 원인이 있습니다.

 1. (가장 핵심적인 원인) Actor 재진입(Re-entrancy)으로 인한 동시성 안티패턴
 현상: 여러 테스트(T2.2, T2.5, T3.1, T5.1)에서 공통적으로 typeMismatch(..., actual: "Optional<Any>") 에러가 발생합니다. 이는 의존성 해결 로직이 기대한 타입 대신 nil 값을 반환하고, 이 nil이 any Sendable로 타입 소거(type-erased) 되면서 Optional<Any>라는 이상한 타입으로 표현되는 문제입니다. T1.9에서 팩토리 호출 카운트가 0인 것 또한, 의존성 해결이 내부적으로 실패하여 @Inject가 조용히 기본값을 반환했기 때문에 나타나는 증상입니다.

 근본 원인: ScopeManager의 getOrCreateInstance 메서드에 전형적인 동시성 안티패턴이 존재합니다.

 Swift

 // ScopeManager.swift 내부
 func getOrCreateInstance<T: Sendable>(...) async throws -> T {
     // ...
     let creationTask = Task<any Sendable, Error> { try await factory() }
     ongoingCreations[key] = creationTask // 1. 진행 중인 작업으로 등록
     defer { ongoingCreations[key] = nil }

     let instance = try await creationTask.value // 2. 여기서 await! 액터가 잠시 멈춤

     // 3. await 이후 상태 변경! (안티패턴)
     // 이 코드가 실행되기 전에 다른 작업이 끼어들어 상태를 변경할 수 있음
     containerCache[key] = instance
     return instance
 }
 await으로 인해 액터가 일시 중단된 동안, 다른 작업이 이 액터에 접근할 수 있습니다 (Actor Re-entrancy). 만약 거의 동시에 동일한 의존성을 요청하는 두 개의 태스크(A, B)가 있다면 다음과 같은 경쟁 상태가 발생할 수 있습니다.

 태스크 A가 들어와 creationTask를 만들고 await 상태에 들어갑니다.

 태스크 B가 거의 동시에 들어와 ongoingCreations에 등록된 A의 creationTask를 발견하고 똑같이 await 합니다.

 A의 creationTask가 완료되고 A가 깨어납니다. 하지만 캐시에 값을 저장하기 전에 B가 먼저 깨어나는 등 순서가 꼬이면, B는 아직 캐시에 저장되지 않은 값을 받으려 하거나, ongoingCreations이 defer에 의해 먼저 nil이 되는 등의 미묘한 타이밍 문제가 발생하여 결국 nil을 반환하게 됩니다.

 결론: await 이후에 액터의 상태(containerCache, ongoingCreations)를 변경하는 로직이 이 문제의 핵심 원인입니다.

 2. 부정확한 오류 전파 (Error Propagation)
 현상: T4.1(순환 참조) 테스트에서 기대한 .circularDependency 에러 대신, 여러 개의 .factoryFailed 에러가 감싸고 있는 복잡한 중첩 에러가 발생했습니다.

 근본 원인: WeaverContainer의 resolve(key:from:) 메서드에 있는 do-catch 블록이 너무 포괄적입니다. 의존성 팩토리 내부에서 resolver.resolve(...) 호출로 인해 .circularDependency 에러가 발생했을 때, 이 catch 블록이 해당 에러의 종류를 확인하지 않고 무조건 .factoryFailed로 다시 감싸서 던지기 때문입니다. 이 과정이 순환 경로를 따라 반복되면서 에러가 여러 번 중첩된 것입니다.

 3. 테스트 로직의 결함
 현상: T1.6(@Inject 안전 모드) 테스트가 id가 다르다며 실패했습니다.

 근본 원인: 테스트의 검증 로직이 잘못되었습니다. ServiceProtocolKey.defaultValue는 static var 컴퓨티드 프로퍼티이므로, 접근할 때마다 NullService()를 통해 새로운 인스턴스를 생성합니다. 테스트는 @Inject가 반환한 기본값(첫 번째 새 인스턴스)과, 검증을 위해 또 한 번 호출해서 만든 두 번째 새 인스턴스의 id를 비교하고 있으므로 당연히 실패합니다.

 결론: 이 실패는 라이브러리의 버그가 아닌, 테스트 코드의 논리적 오류입니다. 인스턴스 ID 비교 대신, 반환된 객체의 타입이 NullService인지를 확인해야 합니다.
 */

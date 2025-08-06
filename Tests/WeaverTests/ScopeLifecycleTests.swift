import Foundation
import Testing

@testable import Weaver

@Suite("2. 스코프별 생명주기 (Scope Lifecycle)")
struct ScopeLifecycleTests {

  @Test("T2.1: .container 스코프 - 동일 인스턴스 반환")
  func test_containerScope_whenResolvedMultipleTimes_shouldReturnSameInstance() async throws {
    // Arrange
    let container = await WeaverContainer.builder()
      .register(ServiceKey.self, scope: .container) { _ in TestService() }
      .build()

    // Act
    let instance1 = try await container.resolve(ServiceKey.self)
    let instance2 = try await container.resolve(ServiceKey.self)

    // Assert
    #expect(instance1.id == instance2.id, ".container 스코프는 항상 동일한 인스턴스를 반환해야 합니다.")
  }

  @Test("T2.2: .appService 스코프 - 동일 인스턴스 반환")
  func test_appServiceScope_whenResolvedMultipleTimes_shouldReturnSameInstance() async throws {
    // Arrange
    let container = await WeaverContainer.builder()
      .register(ServiceKey.self, scope: .appService) { _ in TestService() }
      .build()

    // Act
    let instance1 = try await container.resolve(ServiceKey.self)
    let instance2 = try await container.resolve(ServiceKey.self)

    // Assert
    #expect(instance1.id == instance2.id, ".appService 스코프는 항상 동일한 인스턴스를 반환해야 합니다.")
  }

  @Test("T2.3: .weak 스코프 - 약한 참조 관리")
  func test_weakScope_whenObjectDeallocated_shouldCreateNewInstance() async throws {
    // Arrange
    let container = await WeaverContainer.builder()
      .registerWeak(WeakServiceKey.self) { _ in WeakService() }
      .build()

    // Act
    var instance1: WeakService? = try await container.resolve(WeakServiceKey.self)
    let id1 = instance1?.id
    
    // 강한 참조 해제
    instance1 = nil
    
    // 가비지 컬렉션을 위한 짧은 대기
    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    
    let instance2 = try await container.resolve(WeakServiceKey.self)

    // Assert
    #expect(id1 != instance2.id, "약한 참조 객체가 해제된 후에는 새로운 인스턴스를 생성해야 합니다.")
  }

  @Test("T2.4: .container 스코프 - Disposable 객체 자동 해제")
  func test_disposableObject_whenContainerShutsDown_shouldBeDisposed() async throws {
    // Arrange
    let disposeSignal = TestSignal()
    let container = await WeaverContainer.builder()
      .register(DisposableServiceKey.self, scope: .container) { _ in
        DisposableService(onDispose: { await disposeSignal.signal() })
      }
      .build()

    _ = try await container.resolve(DisposableServiceKey.self)

    // Act
    await container.shutdown()
    await disposeSignal.wait()

    // Assert
    #expect(Bool(true), "dispose() 메서드가 호출되어 wait()가 성공적으로 완료되어야 합니다.")
  }
}

struct LifecycleTests {

  /// - Intent: `.container` 스코프로 등록된 `Disposable` 객체가 컨테이너 `shutdown` 시 `dispose()` 메서드를 호출하는지 검증합니다.
  /// - Given: `dispose` 호출 시 신호를 보낼 `TestSignal`과, 이를 사용하는 `DisposableService`가 등록된 컨테이너.
  /// - When: 컨테이너를 `shutdown()`하고, `TestSignal`을 `wait()`합니다.
  /// - Then: `wait()`이 시간 초과 없이 성공적으로 완료되어야 합니다. 이는 `dispose()`가 호출되었음을 의미합니다.
  @Test("Disposable dependency is disposed on container shutdown")
  func testDisposableDependencyIsDisposed() async throws {
    // Arrange
    let signal = TestSignal()
    let container = await WeaverContainer.builder()
      .register(DisposableServiceKey.self, scope: .container) { _ in
        DisposableService(onDispose: { await signal.signal() })
      }
      .build()

    // 컨테이너가 Disposable 인스턴스를 생성하도록 미리 한 번 해결합니다.
    _ = try await container.resolve(DisposableServiceKey.self)

    // Act
    await container.shutdown()

    // Assert
    // `wait()` 호출이 성공하면 `dispose`가 호출된 것입니다.
    await signal.wait()
  }
}

struct ErrorHandlingTests {

  /// - Intent: 의존성 팩토리 내부에서 에러가 발생했을 때, `resolutionFailed(.factoryFailed)` 에러가 올바르게 전파되는지 검증합니다.
  /// - Given: 팩토리 클로저가 항상 `TestError.factoryFailed`를 던지는 의존성이 등록된 컨테이너.
  /// - When: 해당 의존성을 해결(resolve)하려고 시도합니다.
  /// - Then: `WeaverError.resolutionFailed` 에러가 발생해야 하며, 그 내부(underlying) 에러는 `TestError.factoryFailed`여야 합니다.
  @Test("Factory failure propagates correct error")
  func testFactoryFailurePropagatesError() async {
    // Arrange
    let container = await WeaverContainer.builder()
      .register(ServiceKey.self) { _ in
        throw TestError.factoryFailed
      }
      .build()

    // Act & Assert
    await #expect(throws: WeaverError.self) {
      _ = try await container.resolve(ServiceKey.self)
    }
  }

  /// - Intent: 서비스 A가 B를, B가 다시 A를 필요로 하는 순환 참조 상황에서 `circularDependency` 에러가 발생하는지 검증합니다.
  /// - Given: `CircularAKey`와 `CircularBKey`가 서로를 참조하도록 등록된 컨테이너.
  /// - When: `CircularAKey`를 해결하려고 시도합니다.
  /// - Then: `WeaverError.resolutionFailed(.circularDependency)` 에러가 발생해야 합니다.
  @Test("Circular dependency is detected")
  func testCircularDependencyIsDetected() async {
    // Arrange
    let module = AnonymousModule { builder in
      await builder.register(CircularAKey.self) { resolver in
        let serviceB = try await resolver.resolve(CircularBKey.self)
        return CircularServiceA(serviceB: serviceB)
      }
      await builder.register(CircularBKey.self) { resolver in
        let serviceA = try await resolver.resolve(CircularAKey.self)
        return CircularServiceB(serviceA: serviceA)
      }
    }
    let container = await WeaverContainer.builder()
      .withModules([module])
      .build()

    // Act & Assert
    await #expect(throws: WeaverError.self) {
      _ = try await container.resolve(CircularAKey.self)
    }
  }
}
import Testing
@testable import Weaver

struct RegistrationAndResolutionTests {

    /// - Intent: `.container` 스코프로 등록된 의존성의 팩토리는 단 한 번만 호출되는지 검증합니다.
    /// - Given: 팩토리 호출 횟수를 추적하는 카운터와, `.container` 스코프로 등록된 `TestService`.
    /// - When: 동일한 의존성을 여러 번 해결(resolve)합니다.
    /// - Then: 팩토리 호출 카운터는 정확히 `1`이어야 합니다.
    @Test(".container scope factory is called only once")
    func testContainerScopeFactoryIsCalledOnlyOnce() async throws {
        // Arrange
        let factoryCallCounter = FactoryCallCounter()
        let container = await WeaverContainer.builder()
            .register(ServiceKey.self, scope: .container) { _ in
                TestService { await factoryCallCounter.increment() }
            }
            .build()
        
        // Act
        _ = try await container.resolve(ServiceKey.self)
        _ = try await container.resolve(ServiceKey.self)
        
        // Assert
        let callCount = await factoryCallCounter.count
        #expect(callCount == 1)
    }

    /// - Intent: `.cached` 스코프로 등록된 의존성은 처음 해결될 때만 팩토리가 호출되고, 이후에는 캐시된 인스턴스를 반환하는지 검증합니다.
    /// - Given: 팩토리 호출 횟수를 추적하는 카운터와, `.cached` 스코프로 등록된 `TestService`.
    /// - When: 동일한 의존성을 여러 번 해결합니다.
    /// - Then: 팩토리 호출 카운터는 `1`이어야 하고, 반환된 인스턴스들은 모두 동일해야 합니다.
    @Test(".cached scope factory is called only once")
    func testCachedScopeFactoryIsCalledOnlyOnce() async throws {
        // Arrange
        let factoryCallCounter = FactoryCallCounter()
        let container = await WeaverContainer.builder()
            .enableAdvancedCaching()
            .register(ServiceKey.self, scope: .cached) { _ in
                TestService { await factoryCallCounter.increment() }
            }
            .build()
        
        // Act
        let instance1 = try await container.resolve(ServiceKey.self)
        let instance2 = try await container.resolve(ServiceKey.self)

        // Assert
        let callCount = await factoryCallCounter.count
        #expect(callCount == 1)
        #expect(instance1.id == instance2.id)
    }

    /// - Intent: 이미 등록된 의존성을 다시 등록(Override)할 경우, 마지막에 등록된 팩토리가 사용되는지 검증합니다.
    /// - Given: 동일한 키(`ServiceProtocolKey`)에 대해 처음에는 `TestService`를, 두 번째에는 `AnotherService`를 등록한 컨테이너.
    /// - When: 해당 키로 의존성을 해결합니다.
    /// - Then: 해결된 인스턴스는 마지막에 등록한 `AnotherService` 타입이어야 합니다.
    @Test("Dependency registration can be overridden")
    func testDependencyRegistrationCanBeOverridden() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(ServiceProtocolKey.self) { _ in TestService() }
            .register(ServiceProtocolKey.self) { _ in AnotherService() } // Override
            .build()
        
        // Act
        let service = try await container.resolve(ServiceProtocolKey.self)
        
        // Assert
        #expect(service is AnotherService)
    }
}

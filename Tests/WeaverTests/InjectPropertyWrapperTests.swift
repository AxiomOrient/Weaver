import Testing
@testable import Weaver

struct InjectPropertyWrapperTests {

    /// - Intent: `@Inject`로 주입된 의존성이 컨테이너 스코프 내에서 정상적으로 해결되는지 검증합니다.
    /// - Given: `TestService`가 등록된 컨테이너와, 해당 서비스를 `@Inject`하는 `ServiceConsumer`.
    /// - When: `Weaver.withScope`로 컨테이너를 활성화하고, `@Inject` 프로퍼티에 접근합니다.
    /// - Then: `resolved` 프로퍼티는 `TestService`의 인스턴스를 반환해야 합니다.
    @Test("@Inject resolves dependency correctly")
    func testInjectResolvesDependencyCorrectly() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(ServiceProtocolKey.self) { _ in TestService() }
            .build()
        let consumer = ServiceConsumer()
        
        // Act
        let service = try await Weaver.withScope(container) {
            try await consumer.$aService.resolved
        }
        
        // Assert
        #expect(service is TestService)
    }
    
    /// - Intent: `@Inject`가 의존성을 한 번 해결한 후, 그 결과를 내부적으로 캐시하는지 검증합니다.
    /// - Given: 팩토리 호출 횟수를 추적하는 컨테이너와 `ServiceConsumer`.
    /// - When: 동일한 `@Inject` 프로퍼티에 여러 번 접근합니다.
    /// - Then: 팩토리는 단 한 번만 호출되어야 합니다.
    @Test("@Inject caches resolved instance")
    func testInjectCachesResolvedInstance() async throws {
        // Arrange
        let factoryCallCounter = FactoryCallCounter()
        let container = await WeaverContainer.builder()
            .enableAdvancedCaching() // Use the real cache manager
            .register(ServiceProtocolKey.self, scope: .cached) { _ in
                TestService { await factoryCallCounter.increment() }
            }
            .build()
        let consumer = ServiceConsumer()

        // Act
        try await Weaver.withScope(container) {
            _ = try await consumer.$cachedService.resolved
            _ = try await consumer.$cachedService.resolved
        }
        
        // Assert
        let callCount = await factoryCallCounter.count
        #expect(callCount == 1)
    }

    /// - Intent: 등록되지 않은 의존성을 `.value`로 접근 시, `DependencyKey`의 `defaultValue`가 반환되는지 검증합니다.
    /// - Given: 의존성이 등록되지 않은 빈 컨테이너와 `ServiceConsumer`.
    /// - When: `@Inject` 프로퍼티에 `.value`로 접근합니다.
    /// - Then: `ServiceProtocolKey.defaultValue`인 `NullService`의 인스턴스가 반환되어야 합니다.
    @Test("@Inject returns default value on resolution failure")
    func testInjectReturnsDefaultValueOnFailure() async throws {
        // Arrange
        let container = await WeaverContainer.builder().build()
        let consumer = ServiceConsumer()
        
        // Act
        let service = await Weaver.withScope(container) {
            await consumer.safeServiceWithDefault()
        }
        
        // Assert
        #expect(service is NullService)
    }
}

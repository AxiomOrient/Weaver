import Testing
@testable import Weaver

@Suite("1. 등록 및 해결 (Registration & Resolution)")
struct RegistrationAndResolutionTests {
    
    @Test("T1.1: 기본 등록 및 해결")
    func test_resolve_whenDependencyIsRegistered_shouldSucceed() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(ServiceProtocolKey.self) { _ in TestService() }
            .build()
        
        // Act
        let resolvedService = try await container.resolve(ServiceProtocolKey.self)
        
        // Assert
        #expect(resolvedService is TestService, "해결된 서비스는 등록된 타입이어야 합니다.")
    }
    
    @Test("T1.2: 미등록 의존성 해결")
    func test_resolve_whenDependencyIsUnregistered_shouldThrowKeyNotFoundError() async {
        // Arrange
        let container = await WeaverContainer.builder().build()
        
        // Act & Assert
        await #expect(throws: WeaverError.self, "미등록 키 해결 시 WeaverError를 던져야 합니다.") {
            _ = try await container.resolve(ServiceProtocolKey.self)
        }
    }
    
    @Test("T1.3: 의존성 오버라이드")
    func test_resolve_whenDependencyIsOverridden_shouldReturnLastRegisteredInstance() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(ServiceProtocolKey.self) { _ in TestService() } // 먼저 등록
            .register(ServiceProtocolKey.self) { _ in AnotherService() } // 나중에 오버라이드
            .build()
        
        // Act
        let resolvedService = try await container.resolve(ServiceProtocolKey.self)
        
        // Assert
        #expect(resolvedService is AnotherService, "오버라이드 된 경우, 마지막에 등록된 의존성이 해결되어야 합니다.")
    }
}

import Testing
@testable import Weaver

/// 의존성 등록 및 해결의 핵심 기능만 검증하는 간소화된 테스트 스위트입니다.
/// 스코프별 세부 동작은 ScopeLifecycleTests에서 다룹니다.
@Suite("Basic Registration & Resolution")
struct RegistrationAndResolutionTests {

    @Test("의존성 등록 오버라이드 - 마지막 등록이 우선")
    func dependencyRegistrationCanBeOverridden() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(ServiceProtocolKey.self) { _ in TestService() }
            .register(ServiceProtocolKey.self) { _ in AnotherService() } // Override
            .build()
        
        // Act
        let service = try await container.resolve(ServiceProtocolKey.self)
        
        // Assert
        #expect(service is AnotherService)
        
        await container.shutdown()
    }
}

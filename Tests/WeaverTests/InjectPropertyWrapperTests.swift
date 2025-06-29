
import Testing
@testable import Weaver

@Suite("1. 등록 및 해결 - @Inject 프로퍼티 래퍼")
struct InjectPropertyWrapperTests {

    private actor FactoryCallCounter {
        var count = 0
        func increment() { count += 1 }
    }

    @Test("T1.4 & T1.5: @Inject 기본 모드 - 컨테이너 스코프 내에서 정상 해결")
    func test_inject_whenInScope_shouldResolveValue() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(ServiceProtocolKey.self) { _ in TestService() }
            .build()
        
        // Act & Assert
        try await Weaver.withScope(container) {
            let consumer = ServiceConsumer()
            
            // T1.5: 안전 모드 (`callAsFunction`)
            let service = await consumer.aService()
            #expect(service is TestService, "기본 호출 시 의존성이 정상적으로 해결되어야 합니다.")
            
            // T1.4: 엄격 모드 (`.resolved`)
            let strictService = try await consumer.$strictService.resolved
            #expect(strictService is TestService, "엄격 모드(.resolved)에서도 의존성이 정상적으로 해결되어야 합니다.")
        }
    }

    @Test("T1.6: @Inject 안전 모드 - 실패 시 기본값 반환")
    func test_inject_whenResolutionFails_shouldReturnDefaultValue() async {
        // Arrange
        let emptyContainer = await WeaverContainer.builder().build()
        
        // Act & Assert
        await Weaver.withScope(emptyContainer) {
            let consumer = ServiceConsumer()
            let service = await consumer.safeServiceWithDefault()
            
            // Assert: 반환된 객체가 기본값 타입인 `NullService`인지 확인합니다.
            // ID 비교는 defaultValue가 매번 새 인스턴스를 생성하므로 부적절합니다.
            #expect(service is NullService, "안전 모드에서는 해결 실패 시 `defaultValue`가 반환되어야 합니다.")
        }
    }

    @Test("T1.7: @Inject 엄격 모드 - 실패 시 에러 발생")
    func test_injectStrict_whenResolutionFails_shouldThrowError() async {
        // Arrange
        let emptyContainer = await WeaverContainer.builder().build()
        
        // Act & Assert
        await Weaver.withScope(emptyContainer) {
            let consumer = ServiceConsumer()
            await #expect(throws: WeaverError.self, "엄격 모드는 해결 실패 시 WeaverError를 던져야 합니다.") {
                _ = try await consumer.$strictService.resolved
            }
        }
    }
    
    @Test("T1.8: @Inject 스코프 외부 접근")
    func test_inject_whenAccessedOutsideScope_shouldThrowOrReturnDefault() async {
        // Arrange
        let consumer = ServiceConsumer()
        
        // Act & Assert
        // 안전 모드: 기본값 반환
        let service = await consumer.safeServiceWithDefault()
        #expect(service is NullService, "스코프 외부에서 안전 모드 접근 시 기본값이 반환되어야 합니다.")
        
        // 엄격 모드: .containerNotFound 에러 발생
        await #expect(throws: WeaverError.self, "스코프 외부에서 엄격 모드 접근 시 WeaverError.containerNotFound 에러가 발생해야 합니다.") {
            _ = try await consumer.$strictService.resolved
        }
    }
    
    @Test("T1.9: @Inject 내부 캐시 동작")
    func test_inject_whenAccessedMultipleTimes_shouldUseInternalCache() async throws {
        // Arrange
        let factoryCallCounter = FactoryCallCounter()
        let container = await WeaverContainer.builder()
            .register(ServiceProtocolKey.self) { _ in
                await factoryCallCounter.increment()
                return TestService()
            }
            .build()
            
        // Act & Assert
        try await Weaver.withScope(container) {
            let consumer = ServiceConsumer()
            _ = await consumer.cachedService() // 1차 호출 (팩토리 실행)
            _ = await consumer.cachedService() // 2차 호출 (캐시 사용)
            
            let finalCount = await factoryCallCounter.count
            #expect(finalCount == 1, "팩토리는 최초 1회만 호출되고, 이후에는 @Inject 내부 캐시를 사용해야 합니다.")
        }
    }
}


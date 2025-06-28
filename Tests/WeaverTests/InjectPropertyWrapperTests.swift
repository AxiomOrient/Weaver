import Testing
@testable import Weaver

@Suite("1. 등록 및 해결 - @Inject 프로퍼티 래퍼")
struct InjectPropertyWrapperTests {

    /// 팩토리 호출 횟수를 동시성 환경에서 안전하게 추적하기 위한 액터
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
        // ✅ FIX: 'try' 키워드를 다시 추가합니다.
        // 클로저 내부의 'try await' 호출로 인해 withScope 자체가 rethrows 합니다.
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
            
            #expect(service is NullService, "안전 모드에서는 해결 실패 시 `defaultValue`가 반환되어야 합니다.")
            #expect(service.id == ServiceProtocolKey.defaultValue.id)
        }
    }

    @Test("T1.7: @Inject 엄격 모드 - 실패 시 에러 발생")
    func test_injectStrict_whenResolutionFails_shouldThrowError() async {
        // Arrange
        let emptyContainer = await WeaverContainer.builder().build()
        
        // Act & Assert
        await Weaver.withScope(emptyContainer) {
            let consumer = ServiceConsumer()
            do {
                _ = try await consumer.$strictService.resolved
                Issue.record("엄격 모드는 해결 실패 시 에러를 던져야 하지만, 에러가 발생하지 않았습니다.")
            } catch {
                #expect(error is WeaverError, "던져진 에러는 WeaverError 타입이어야 합니다.")
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
        #expect(service is NullService)
        
        // 엄격 모드: .containerNotFound 에러 발생
        do {
            _ = try await consumer.$strictService.resolved
            Issue.record("스코프 외부에서 엄격 모드 접근 시 에러를 던져야 하지만, 에러가 발생하지 않았습니다.")
        } catch let error {
            if case WeaverError.containerNotFound = error {
                // 성공
            } else {
                Issue.record("던져진 에러는 WeaverError.containerNotFound 이어야 합니다. 받은 에러: \(error)")
            }
        }
    }
    
    @Test("T1.9: @Inject 내부 캐시 동작")
    func test_inject_whenAccessedMultipleTimes_shouldUseInternalCache() async {
        // Arrange
        let factoryCallCounter = FactoryCallCounter()
        let module = AnonymousModule { builder in
            await builder.register(ServiceProtocolKey.self) { _ in
                TestService {
                    Task { await factoryCallCounter.increment() }
                }
            }
        }
        let container = await WeaverContainer.builder()
            .withModules([module])
            .build()
            
        // Act & Assert
        await Weaver.withScope(container) {
            let consumer = ServiceConsumer()
            _ = await consumer.cachedService() // 1차 호출
            _ = await consumer.cachedService() // 2차 호출 (캐시 사용)
            
            let finalCount = await factoryCallCounter.count
            #expect(finalCount == 1, "팩토리는 최초 1회만 호출되고, 이후에는 @Inject 내부 캐시를 사용해야 합니다.")
        }
    }
}

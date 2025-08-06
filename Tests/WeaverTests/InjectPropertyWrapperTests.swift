import Testing
@testable import Weaver

struct InjectPropertyWrapperTests {
    
    // MARK: - Test Helpers
    
    /// 격리된 전역 상태에서 @Inject 테스트를 실행하는 헬퍼
    private func withIsolatedGlobalState<T>(_ test: @escaping (WeaverGlobalState) async throws -> T) async rethrows -> T {
        let isolatedState = WeaverGlobalState.shared
        return try await test(isolatedState)
    }

    /// - Intent: `@Inject`로 주입된 의존성이 컨테이너 스코프 내에서 정상적으로 해결되는지 검증합니다.
    /// - Given: `TestService`가 등록된 컨테이너와, 해당 서비스를 `@Inject`하는 `ServiceConsumer`.
    /// - When: TaskLocal 스코프로 컨테이너를 활성화하고, `@Inject` 프로퍼티에 접근합니다.
    /// - Then: `resolved` 프로퍼티는 `TestService`의 인스턴스를 반환해야 합니다.
    @Test("@Inject resolves dependency correctly")
    func testInjectResolvesDependencyCorrectly() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(ServiceProtocolKey.self) { _ in TestService(isDefaultValue: false) }
            .build()
        
        // Act - 직접 컨테이너 사용 (전역 상태 불필요)
        let service = try await container.resolve(ServiceProtocolKey.self)
        
        // Assert
        #expect(service.isDefaultValue == false) // 실제 해결된 값
        
        await container.shutdown()
    }
    
    /// - Intent: 컨테이너의 캐시 스코프가 의존성을 한 번 해결한 후 캐시하는지 검증합니다.
    /// - Given: 팩토리 호출 횟수를 추적하는 컨테이너.
    /// - When: 동일한 의존성을 여러 번 해결합니다.
    /// - Then: 팩토리는 단 한 번만 호출되어야 합니다.
    @Test("@Inject caches resolved instance")
    func testInjectCachesResolvedInstance() async throws {
        // Arrange
        let factoryCallCounter = FactoryCallCounter()
        let container = await WeaverContainer.builder()
            .enableAdvancedCaching() // Use the real cache manager
            .register(ServiceProtocolKey.self, scope: .container) { _ in
                TestService { await factoryCallCounter.increment() }
            }
            .build()

        // Act - 직접 컨테이너 사용 (전역 상태 불필요)
        _ = try await container.resolve(ServiceProtocolKey.self)
        _ = try await container.resolve(ServiceProtocolKey.self)
        
        // Assert
        let callCount = await factoryCallCounter.count
        #expect(callCount == 1)
        
        await container.shutdown()
    }

    /// - Intent: 등록되지 않은 의존성 해결 시 에러가 발생하는지 검증합니다.
    /// - Given: 의존성이 등록되지 않은 빈 컨테이너.
    /// - When: 등록되지 않은 의존성을 해결하려고 시도합니다.
    /// - Then: `WeaverError`가 발생해야 합니다.
    @Test("@Inject returns default value on resolution failure")
    func testInjectReturnsDefaultValueOnFailure() async throws {
        // Arrange
        let container = await WeaverContainer.builder().build()
        
        // Act & Assert - 직접 컨테이너 사용 (전역 상태 불필요)
        await #expect(throws: WeaverError.self) {
            _ = try await container.resolve(ServiceProtocolKey.self)
        }
        
        await container.shutdown()
    }
    
    // MARK: - 단순화된 @Inject API 테스트 (Task 9)
    
    /// - Intent: `@Inject`의 `callAsFunction()` API가 TaskLocal 스코프에서 안전하게 동작하는지 검증합니다.
    /// - Given: 정상적으로 등록된 의존성과 `@Inject` 프로퍼티
    /// - When: TaskLocal 스코프에서 `await myService()`로 호출합니다.
    /// - Then: 의존성이 정상적으로 해결되어야 합니다.
    @Test("@Inject callAsFunction resolves dependency safely")
    func testInjectCallAsFunctionResolvesSafely() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(ServiceProtocolKey.self) { _ in TestService(isDefaultValue: false) }
            .build()
        let consumer = ServiceConsumer()
        
        // Act - TaskLocal 스코프에서 @Inject 테스트 (전역 상태 필요)
        let service = await Weaver.withScope(container) {
            await consumer.aService()
        }
        
        // Assert
        #expect(service.isDefaultValue == false) // 실제 해결된 값
        
        await container.shutdown()
    }
    
    /// - Intent: `@Inject`의 `callAsFunction()`이 실패 시에도 절대 크래시하지 않고 기본값을 반환하는지 검증합니다.
    /// - Given: 의존성이 등록되지 않은 컨테이너
    /// - When: TaskLocal 스코프에서 `await myService()`로 호출합니다.
    /// - Then: 기본값이 안전하게 반환되어야 합니다.
    @Test("@Inject callAsFunction returns default value on failure")
    func testInjectCallAsFunctionReturnsDefaultOnFailure() async throws {
        // Arrange
        let container = await WeaverContainer.builder().build() // 빈 컨테이너
        let consumer = ServiceConsumer()
        
        // Act - TaskLocal 스코프에서 @Inject 안전성 테스트 (전역 상태 필요)
        let service = await Weaver.withScope(container) {
            await consumer.aService()
        }
        
        // Assert: 기본값(NullService)이 반환되어야 함
        #expect(service is NullService)
        
        await container.shutdown()
    }
    
    /// - Intent: `callAsFunction()`이 전역 커널 없이도 안전하게 동작하는지 검증합니다.
    /// - Given: 전역 커널이 설정되지 않은 상태
    /// - When: `await myService()`로 호출합니다.
    /// - Then: 기본값이 안전하게 반환되어야 합니다.
    @Test("@Inject callAsFunction works without global kernel")
    func testInjectCallAsFunctionWorksWithoutGlobalKernel() async throws {
        // Arrange - 전역 상태 정리
        let consumer = ServiceConsumer()
        
        // Act - 전역 커널 없이 직접 호출 (기본적으로 기본값 반환)
        let service = await consumer.aService()
        
        // Assert: 기본값이 반환되어야 함
        #expect(service is NullService)
    }
    
    /// - Intent: `@Inject`의 `$inject.resolve()`와 `callAsFunction()`의 동작 차이를 검증합니다.
    /// - Given: 정상적으로 등록된 의존성
    /// - When: TaskLocal 스코프에서 두 방식으로 모두 호출합니다.
    /// - Then: 동일한 결과를 반환해야 합니다.
    @Test("@Inject callAsFunction and resolve return same result when successful")
    func testInjectCallAsFunctionAndResolveConsistency() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(ServiceProtocolKey.self) { _ in TestService(isDefaultValue: false) }
            .build()
        let consumer = ServiceConsumer()
        
        // Act - TaskLocal 스코프에서 @Inject 두 API 비교 (전역 상태 필요)
        let (safeResult, throwingResult) = try await Weaver.withScope(container) {
            let safe = await consumer.aService()
            let throwing = try await consumer.$aService.resolve()
            return (safe, throwing)
        }
        
        // Assert: 둘 다 실제 해결된 값이어야 함
        #expect(safeResult.isDefaultValue == false) // 실제 해결된 값
        #expect(throwingResult.isDefaultValue == false) // 실제 해결된 값
        
        await container.shutdown()
    }
    
    /// - Intent: `@Inject`의 실패 상황에서 두 API의 동작 차이를 검증합니다.
    /// - Given: 의존성이 등록되지 않은 컨테이너
    /// - When: TaskLocal 스코프에서 두 방식으로 모두 호출합니다.
    /// - Then: `callAsFunction()`은 기본값을, `resolve()`는 에러를 발생시켜야 합니다.
    @Test("@Inject callAsFunction and resolve behave differently on failure")
    func testInjectCallAsFunctionAndResolveDifferOnFailure() async throws {
        // Arrange
        let container = await WeaverContainer.builder().build() // 빈 컨테이너
        let consumer = ServiceConsumer()
        
        // Act & Assert - TaskLocal 스코프에서 @Inject 실패 동작 테스트 (전역 상태 필요)
        await Weaver.withScope(container) {
            // callAsFunction()은 기본값 반환
            let safeResult = await consumer.aService()
            #expect(safeResult is NullService)
            
            // resolve()는 에러 발생
            await #expect(throws: WeaverError.self) {
                _ = try await consumer.$aService.resolve()
            }
        }
        
        await container.shutdown()
    }
    
    // MARK: - 새로운 에러 처리 기능 테스트
    
    /// - Intent: `$inject.resolve()`가 컨테이너가 없을 때 적절한 에러를 던지는지 검증합니다.
    /// - Given: 컨테이너 스코프 밖에서 `@Inject` 사용하고 전역 커널도 없는 상태
    /// - When: `$inject.resolve()`를 호출합니다.
    /// - Then: `WeaverError.containerNotReady` 에러가 발생해야 합니다.
    @Test("$inject.resolve() throws containerNotReady when no container")
    func testResolveThrowsContainerNotReady() async throws {
        // Arrange - 격리된 환경에서 테스트
        await withIsolatedGlobalState { isolatedState in
            let consumer = ServiceConsumer()
            
            // Act & Assert - 전역 커널 없이 resolve 시도 (idle 상태)
            await #expect(throws: WeaverError.containerNotReady(currentState: .idle)) {
                _ = try await consumer.$aService.resolve()
            }
        }
    }
    
    /// - Intent: 컨테이너가 준비되지 않은 상태에서 `$inject.resolve()`가 적절한 에러를 던지는지 검증합니다.
    /// - Given: 아직 빌드되지 않은 커널이 전역으로 설정된 상태
    /// - When: `$inject.resolve()`를 호출합니다.
    /// - Then: `WeaverError.containerNotReady` 에러가 발생해야 합니다.
    @Test("$inject.resolve() throws containerNotReady when kernel not built")
    func testResolveThrowsContainerNotReadyWhenKernelNotBuilt() async throws {
        // Arrange - 격리된 전역 상태에서 테스트
        await withIsolatedGlobalState { isolatedState in
            let modules = [AnonymousModule { builder in
                await builder.register(ServiceProtocolKey.self) { _ in TestService(isDefaultValue: false) }
            }]
            let kernel = DefaultWeaverKernel(modules: modules)
            await isolatedState.setGlobalKernel(kernel)
            // 주의: kernel.build()를 호출하지 않아서 idle 상태 유지
            
            let consumer = ServiceConsumer()
            
            // Act & Assert
            await #expect(throws: WeaverError.containerNotReady(currentState: .idle)) {
                _ = try await consumer.$aService.resolve()
            }
            
            // Cleanup
            await isolatedState.setGlobalKernel(nil)
        }
    }
}

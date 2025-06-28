import Testing
@testable import Weaver

@Suite("3 & 4. 계층, 오류 및 엣지 케이스")
struct ContainerEdgeCaseTests {

    // MARK: - 3. Hierarchical Containers

    @Test("T3.1: 부모 의존성 참조")
    func test_hierarchicalContainers_whenResolvingFromChild_shouldFindParentDependency() async throws {
        // Arrange
        let parentContainer = await WeaverContainer.builder()
            .register(ServiceProtocolKey.self, scope: .container) { _ in TestService() }
            .build()
        
        let childContainer = await WeaverContainer.builder()
            .withParent(parentContainer)
            .build()

        // Act
        let instanceFromParent = try await parentContainer.resolve(ServiceProtocolKey.self)
        let instanceFromChild = try await childContainer.resolve(ServiceProtocolKey.self)

        // Assert
        #expect(instanceFromChild.id == instanceFromParent.id, "자식 컨테이너는 부모에 등록된 .container 스코프 인스턴스를 공유해야 합니다.")
    }

    @Test("T3.2: 자식 의존성 오버라이드")
    func test_hierarchicalContainers_whenChildOverrides_shouldResolveChildsDependency() async throws {
        // Arrange
        let parentContainer = await WeaverContainer.builder()
            .register(ServiceProtocolKey.self) { _ in TestService() }
            .build()
        
        let childContainer = await WeaverContainer.builder()
            .withParent(parentContainer)
            .register(ServiceProtocolKey.self) { _ in AnotherService() } // 자식에서 오버라이드
            .build()

        // Act
        let resolvedService = try await childContainer.resolve(ServiceProtocolKey.self)

        // Assert
        // ✅ FIX: 조건문을 변수로 추출하여 매크로 구문 오류 회피
        let isOverriddenInstance = resolvedService is AnotherService
        #expect(isOverriddenInstance, "자식 컨테이너에서 resolve 시, 자식에 등록된 의존성이 우선적으로 반환되어야 합니다.")
    }

    // MARK: - 4. Error Handling & Edge Cases

    @Test("T4.1: 순환 참조")
    func test_errorHandling_whenCircularDependencyDetected_shouldThrowError() async {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(CircularAKey.self) { resolver in
                let serviceB = try await resolver.resolve(CircularBKey.self)
                return CircularServiceA(serviceB: serviceB)
            }
            .register(CircularBKey.self) { resolver in
                let serviceA = try await resolver.resolve(CircularAKey.self)
                return CircularServiceB(serviceA: serviceA)
            }
            .build()
        
        // Act & Assert
        // ✅ FIX: 불필요한 await 제거 및 do-catch로 에러 케이스 검증
        do {
            _ = try await container.resolve(CircularAKey.self)
            Issue.record("순환 참조 시 에러가 발생해야 하지만, 에러가 발생하지 않았습니다.")
        } catch let error as WeaverError {
            if case .resolutionFailed(let resolutionError) = error,
               case .circularDependency = resolutionError {
                // 성공
            } else {
                Issue.record("던져진 에러는 .circularDependency 이어야 합니다. 받은 에러: \(error)")
            }
        } catch {
            Issue.record("던져진 에러는 WeaverError 타입이어야 합니다.")
        }
    }

    @Test("T4.2: 팩토리 실패")
    func test_errorHandling_whenFactoryThrows_shouldThrowError() async {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(ServiceKey.self) { _ in
                throw TestError.factoryFailed
            }
            .build()

        // Act & Assert
        // ✅ FIX: 불필요한 await 제거 및 do-catch로 에러 케이스 검증
        do {
            _ = try await container.resolve(ServiceKey.self)
            Issue.record("팩토리 실패 시 에러가 발생해야 하지만, 에러가 발생하지 않았습니다.")
        } catch let error as WeaverError {
            if case .resolutionFailed(let resolutionError) = error,
               case .factoryFailed = resolutionError {
                // 성공
            } else {
                Issue.record("던져진 에러는 .factoryFailed 이어야 합니다. 받은 에러: \(error)")
            }
        } catch {
            Issue.record("던져진 에러는 WeaverError 타입이어야 합니다.")
        }
    }

    // T4.3: 타입 불일치 테스트는 register API의 타입 안전성으로 인해 컴파일 시점에 방지되므로 제거합니다.

    @Test("T4.4: 종료된 컨테이너 접근")
    func test_errorHandling_whenResolvingFromShutdownContainer_shouldThrowError() async {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(ServiceKey.self) { _ in TestService() }
            .build()
        
        await container.shutdown()

        // Act & Assert
        // ✅ FIX: 불필요한 await 제거 및 do-catch로 에러 케이스 검증
        do {
            _ = try await container.resolve(ServiceKey.self)
            Issue.record("종료된 컨테이너 접근 시 에러가 발생해야 하지만, 에러가 발생하지 않았습니다.")
        } catch let error as WeaverError {
            if case .shutdownInProgress = error {
                // 성공
            } else {
                Issue.record("던져진 에러는 .shutdownInProgress 이어야 합니다. 받은 에러: \(error)")
            }
        } catch {
            Issue.record("던져진 에러는 WeaverError 타입이어야 합니다.")
        }
    }
}

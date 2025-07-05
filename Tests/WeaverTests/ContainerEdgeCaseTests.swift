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
        let isOverriddenInstance = resolvedService is AnotherService
        #expect(isOverriddenInstance, "자식 컨테이너에서 resolve 시, 자식에 등록된 의존성이 우선적으로 반환되어야 합니다.")
    }

    @Test("T3.3: 다단계 계층 - 손자 컨테이너가 조부모 의존성 참조")
    func test_multiLevelHierarchy_whenResolvingFromGrandchild_shouldFindGrandparentDependency() async throws {
        // Arrange
        let grandparent = await WeaverContainer.builder()
            .register(ServiceKey.self, scope: .container) { _ in TestService() }
            .build()
        
        let parent = await WeaverContainer.builder()
            .withParent(grandparent)
            .build()

        let child = await WeaverContainer.builder()
            .withParent(parent)
            .build()

        // Act
        let instanceFromGrandparent = try await grandparent.resolve(ServiceKey.self)
        let instanceFromChild = try await child.resolve(ServiceKey.self)

        // Assert
        #expect(instanceFromChild.id == instanceFromGrandparent.id, "손자 컨테이너는 조부모 컨테이너에 등록된 의존성을 해결할 수 있어야 합니다.")
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
        await #expect(throws: WeaverError.self, "순환 참조가 감지되면 .circularDependency 오류를 포함한 WeaverError를 던져야 합니다.") {
            _ = try await container.resolve(CircularAKey.self)
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
        await #expect(throws: WeaverError.self, "팩토리에서 오류가 발생하면 .factoryFailed 오류를 포함한 WeaverError를 던져야 합니다.") {
            _ = try await container.resolve(ServiceKey.self)
        }
    }

    @Test("T4.3: 종료된 컨테이너 접근")
    func test_errorHandling_whenResolvingFromShutdownContainer_shouldThrowError() async {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(ServiceKey.self) { _ in TestService() }
            .build()
        
        await container.shutdown()

        // Act & Assert
        await #expect(throws: WeaverError.self, "종료된 컨테이너에 접근하면 .shutdownInProgress 오류를 포함한 WeaverError를 던져야 합니다.") {
            _ = try await container.resolve(ServiceKey.self)
        }
    }

    @Test("T4.4: 계층 간 순환 참조로 인한 데드락")
    func test_errorHandling_whenCircularDependencyBetweenHierarchicalContainers_shouldThrowError() async {
        // Arrange
        // 1. 부모와 자식 컨테이너를 먼저 빌드합니다.
        let initialParentContainer = await WeaverContainer.builder().build()
        let initialChildContainer = await WeaverContainer.builder()
            .withParent(initialParentContainer)
            .build()

        // 2. 순환 참조를 포함하는 새로운 빌더를 생성합니다.
        // 이 빌더들은 이미 빌드된 initialParentContainer와 initialChildContainer를 참조합니다.
        let parentBuilderWithCircularDep = WeaverContainer.builder()
        let childBuilderWithCircularDep = WeaverContainer.builder()

        // Register CircularAKey in childBuilderWithCircularDep
        // CircularA will try to resolve CircularB from initialParentContainer
        await childBuilderWithCircularDep.register(CircularAKey.self, scope: .container) { resolver in
            let serviceB = try await initialParentContainer.resolve(CircularBKey.self)
            return CircularServiceA(serviceB: serviceB)
        }

        // Register CircularBKey in parentBuilderWithCircularDep
        // CircularB will try to resolve CircularA from initialChildContainer
        await parentBuilderWithCircularDep.register(CircularBKey.self, scope: .container) { resolver in
            let serviceA = try await initialChildContainer.resolve(CircularAKey.self)
            return CircularServiceB(serviceA: serviceA)
        }

        // 3. 순환 참조가 등록된 새로운 컨테이너를 빌드합니다.
        // 이 컨테이너들은 기존 컨테이너를 부모로 가집니다.
        let finalParentContainer = await parentBuilderWithCircularDep.build()
        let finalChildContainer = await childBuilderWithCircularDep.withParent(finalParentContainer).build()

        // Act & Assert
        await #expect(throws: WeaverError.self, "계층 간 순환 참조가 감지되면 데드락 대신 오류를 던져야 합니다.") {
            _ = try await finalChildContainer.resolve(CircularAKey.self)
        }
    }
}

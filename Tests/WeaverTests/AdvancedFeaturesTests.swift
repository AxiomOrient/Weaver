import Testing
@testable import Weaver

@Suite("6. 고급 기능 (Advanced Features)")
struct AdvancedFeaturesTests {

    // MARK: - 6. Weak Scope Lifecycle

    @Test("T6.1: .weak 스코프 - 정상 해결")
    func test_weakScope_whenResolved_shouldReturnInstance() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .registerWeak(ServiceKey.self) { _ in TestService() }
            .build()

        // Act
        let instance = try await container.resolve(ServiceKey.self)
        print("[6.1] Resolved instance:", instance)

        // Assert
        let casted = instance as? TestService
        try #require(casted != nil, ".weak 스코프로 등록된 의존성은 정상적으로 해결되어야 합니다.")
    }

    @Test("T6.2: .weak 스코프 - 인스턴스 해제 시 재생성")
    func test_weakScope_whenInstanceDeallocated_shouldReturnNewInstance() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .registerWeak(ServiceKey.self) { _ in TestService() }
            .build()

        // Act
        var instance1: TestService? = try await container.resolve(ServiceKey.self)
        let id1 = instance1?.id
        print("[6.2] First instance id:", id1 ?? "nil")

        // 인스턴스에 대한 모든 강한 참조를 해제합니다.
        instance1 = nil

        // 컨테이너가 약한 참조를 정리할 시간을 주기 위해 잠시 대기합니다.
        try await Task.sleep(for: .milliseconds(100))

        let instance2 = try await container.resolve(ServiceKey.self)
        let id2 = instance2.id
        print("[6.2] Second instance id:", id2)

        // Assert
        let nonNilId1 = try #require(id1, "첫 번째 인스턴스 id가 nil이면 안 됩니다.")
        let nonNilId2 = try #require(id2, "두 번째 인스턴스 id가 nil이면 안 됩니다.")
        #expect(nonNilId1 != nonNilId2, "약한 참조가 해제된 후에는 새로운 인스턴스가 생성되어야 합니다.")
    }

    @Test("T6.3: 일반 register에서 .weak 사용 시 Precondition 실패", .disabled("This test is designed to crash."))
    func test_register_whenUsingWeakScope_shouldTriggerPrecondition() async {
        // Arrange
        let builder = WeaverContainer.builder()

        // Act & Assert
        await builder.register(ServiceKey.self, scope: .weak) { _ in TestService() }
    }
    
    // MARK: - 7. Reconfigure

    @Test("T7.1: reconfigure - 새 의존성 추가")
    func test_reconfigure_whenAddingNewModule_shouldResolveNewDependency() async throws {
        // Arrange
        let initialContainer = await WeaverContainer.builder().build()
        let newModule = AnonymousModule { builder in
            await builder.register(ServiceKey.self) { _ in TestService() }
        }

        // Act
        let reconfiguredContainer = await initialContainer.reconfigure(with: [newModule])
        let instance = try await reconfiguredContainer.resolve(ServiceKey.self)

        // Assert
        #expect(instance is TestService, "reconfigure로 추가된 모듈의 의존성을 해결할 수 있어야 합니다.")
    }

    @Test("T7.2: reconfigure - 기존 의존성 오버라이드")
    func test_reconfigure_whenOverridingModule_shouldResolveOverriddenDependency() async throws {
        // Arrange
        let initialContainer = await WeaverContainer.builder()
            .register(ServiceProtocolKey.self) { _ in TestService() }
            .build()
        
        let overridingModule = AnonymousModule { builder in
            await builder.register(ServiceProtocolKey.self) { _ in AnotherService() }
        }

        // Act
        let reconfiguredContainer = await initialContainer.reconfigure(with: [overridingModule])
        let instance = try await reconfiguredContainer.resolve(ServiceProtocolKey.self)

        // Assert
        #expect(instance is AnotherService, "reconfigure로 추가된 모듈이 기존 의존성을 오버라이드해야 합니다.")
    }

    @Test("T7.3: reconfigure - 부모 의존성 유지")
    func test_reconfigure_shouldMaintainParentLink() async throws {
        // Arrange
        let initialContainer = await WeaverContainer.builder()
            .register(ServiceKey.self, scope: .container) { _ in TestService() }
            .build()
        
        let emptyModule = AnonymousModule { _ in }

        // Act
        let reconfiguredContainer = await initialContainer.reconfigure(with: [emptyModule])
        let instanceFromOriginal = try await initialContainer.resolve(ServiceKey.self)
        let instanceFromReconfigured = try await reconfiguredContainer.resolve(ServiceKey.self)

        // Assert
        #expect(instanceFromOriginal.id == instanceFromReconfigured.id, "reconfigure된 컨테이너는 부모(원본) 컨테이너의 의존성을 계속 해결할 수 있어야 합니다.")
    }
    
    // MARK: - 8. Dependency Graph

    @Test("T8.1: 의존성 그래프 - DOT 형식 생성")
    func test_dependencyGraph_shouldGenerateCorrectDotFile() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(CircularAKey.self, dependencies: ["CircularBKey"]) { _ in CircularServiceA(serviceB: TestService()) }
            .register(CircularBKey.self, dependencies: ["CircularAKey"]) { _ in CircularServiceB(serviceA: TestService()) }
            .build()

        // Act
        let graph = await container.getDependencyGraph()
        let dotString = graph.generateDotGraph()

        // Assert
        #expect(dotString.contains("digraph Dependencies"))
        #expect(dotString.contains("\"CircularAKey\" [label=\"CircularAKey\\n<container>\"; fillcolor=lightgreen];"))
        #expect(dotString.contains("\"CircularBKey\" [label=\"CircularBKey\\n<container>\"; fillcolor=lightgreen];"))
        #expect(dotString.contains("\"CircularAKey\" -> \"CircularBKey\";"))
        #expect(dotString.contains("\"CircularBKey\" -> \"CircularAKey\";"))
    }

    // MARK: - 9. Comprehensive Metrics

    @Test("T9.1: 종합 메트릭 - 모든 지표 정확성 검증")
    func test_getMetrics_shouldReturnComprehensiveAndAccurateMetrics() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .enableAdvancedCaching(policy: .init(maxSize: 1, ttl: 0.1))
            .enableMetricsCollection()
            .register(ServiceKey.self, scope: .container) { _ in TestService() }
            .register(ServiceProtocolKey.self, scope: .cached) { _ in AnotherService() }
            .registerWeak(CircularAKey.self) { _ in CircularServiceA(serviceB: TestService()) }
            .build()

        // Act
        // 1. Container scope: 2 resolutions
        _ = try await container.resolve(ServiceKey.self)
        _ = try await container.resolve(ServiceKey.self)

        // 2. Cached scope: 1 miss, 1 hit
        _ = try await container.resolve(ServiceProtocolKey.self)
        _ = try await container.resolve(ServiceProtocolKey.self)

        // 3. Weak scope: 1 resolution, 1 weak reference created
        var weakInstance: CircularServiceA? = try await container.resolve(CircularAKey.self)

        // 4. TTL 만료 후 Cached scope: 1 miss
        try await Task.sleep(for: .milliseconds(150))
        _ = try await container.resolve(ServiceProtocolKey.self)
        
        // 5. Weak scope 인스턴스 해제 후: 1 resolution, 1 weak reference created, 1 deallocated
        weakInstance = nil
        try await Task.sleep(for: .milliseconds(100))
        let finalWeakInstance = try await container.resolve(CircularAKey.self)

        // Assert
        let metrics = await container.getMetrics()
        
        #expect(metrics.totalResolutions == 7, "총 7번의 해결이 기록되어야 합니다.")
        #expect(metrics.cacheHits == 1, "캐시 히트는 1번이어야 합니다.")
        #expect(metrics.cacheMisses == 2, "캐시 미스는 2번이어야 합니다. (cached scope만 해당)")
        
        let weakMetrics = metrics.weakReferences
        #expect(weakMetrics.totalWeakReferences == 1, "스냅샷 시점에는 총 1개의 약한 참조가 추적되고 있어야 합니다.")
        #expect(weakMetrics.aliveWeakReferences == 1, "현재 1개의 약한 참조가 살아있어야 합니다.")
        #expect(weakMetrics.deallocatedWeakReferences == 0, "스냅샷 시점에는 해제된 참조가 없어야 합니다.")
        
        _ = finalWeakInstance // Keep the instance alive until the end of the test
    }
}


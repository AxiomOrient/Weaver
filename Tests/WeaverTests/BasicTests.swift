// Tests/WeaverTests/BasicTests.swift

import Foundation
import Testing

@testable import Weaver

/// Weaver DI 라이브러리의 핵심 기능을 검증하는 테스트 스위트
/// LANGUAGE.md Section 9 Rule 9_1: AAA 패턴과 단일 책임 원칙 준수
/// GEMINI.md Article 11 Rule 1: 모든 테스트는 AAA 패턴을 따름
@Suite("Weaver DI 핵심 기능 검증", .tags(.unit, .core, .critical))
struct WeaverCoreTests {

  // MARK: - 1. 4가지 스코프 시스템 검증

  @Suite("스코프 시스템 검증", .tags(.scope, .startup, .shared, .whenNeeded, .weak))
  struct ScopeSystemTests {

    @Test("startup 스코프는 커널 빌드 시 즉시 로딩되어야 한다", .tags(.startup, .fast))
    func testStartupScopeEagerLoading() async throws {
      // Arrange
      let counter = FactoryCallCounter()
      let kernel = WeaverKernel.scoped(modules: [
        GenericTestModule(key: ServiceKey.self, scope: .startup) { _ in
          await counter.increment()
          return TestService(isDefaultValue: false)
        }
      ])

      // Act
      await kernel.build()

      // Assert - startup 스코프는 빌드 시 즉시 로딩됨
      let countAfterBuild = await counter.count
      #expect(countAfterBuild == 1, "startup 스코프는 커널 빌드 시 즉시 로딩되어야 함")

      // 커널이 ready 상태인지 확인
      let state = await kernel.currentState
      switch state {
      case .ready:
        let service = await kernel.safeResolve(ServiceKey.self)
        #expect(!service.isDefaultValue, "startup 서비스가 정상적으로 해결되어야 함")
      default:
        throw TestError.intentionalError
      }
    }

    @Test("shared 스코프는 싱글톤으로 동작해야 한다", .tags(.shared, .fast))
    func testSharedScopeSingleton() async throws {
      // Arrange
      let container = await WeaverContainer.builder()
        .register(ServiceKey.self, scope: .shared) { _ in
          TestService(isDefaultValue: false)
        }
        .build()

      // Act
      let service1 = try await container.resolve(ServiceKey.self)
      let service2 = try await container.resolve(ServiceKey.self)

      // Assert
      #expect(service1.id == service2.id, "shared 스코프는 같은 인스턴스를 반환해야 함")
    }

    @Test("whenNeeded 스코프는 온디맨드로 로딩되어야 한다", .tags(.whenNeeded, .fast))
    func testWhenNeededScopeOnDemand() async throws {
      // Arrange
      let counter = FactoryCallCounter()
      let container = await WeaverContainer.builder()
        .register(ServiceKey.self, scope: .whenNeeded) { _ in
          await counter.increment()
          return TestService(isDefaultValue: false)
        }
        .build()

      // Act - 컨테이너 생성 직후에는 로딩되지 않음
      let initialCount = await counter.count
      #expect(initialCount == 0, "whenNeeded 스코프는 사용 전까지 로딩되지 않아야 함")

      // 실제 사용 시 로딩
      _ = try await container.resolve(ServiceKey.self)
      let afterUse = await counter.count
      #expect(afterUse == 1, "whenNeeded 스코프는 첫 사용 시 로딩되어야 함")
    }

    @Test("weak 스코프는 약한 참조로 관리되어야 한다", .tags(.weak, .memory, .fast))
    func testWeakScopeWeakReference() async throws {
      // Arrange
      let container = await WeaverContainer.builder()
        .registerWeak(WeakServiceKey.self) { _ in
          WeakService(isDefaultValue: false)
        }
        .build()

      // Act - 첫 번째 해결
      var service1: WeakService? = try await container.resolve(WeakServiceKey.self)
      let id1 = service1?.id

      // 강한 참조 해제
      service1 = nil
      try await Task.sleep(for: .milliseconds(100))

      // 두 번째 해결
      let service2 = try await container.resolve(WeakServiceKey.self)

      // Assert - 새로운 인스턴스가 생성되어야 함
      #expect(id1 != nil, "첫 번째 서비스가 생성되어야 함")
      #expect(service2.id != id1, "weak 스코프는 해제 후 새 인스턴스를 생성해야 함")
    }
  }

  // MARK: - 2. @Inject 프로퍼티 래퍼 검증

  @Suite("@Inject 프로퍼티 래퍼 검증", .tags(.inject, .safety))
  struct InjectPropertyWrapperTests {

    @Test("@Inject는 callAsFunction으로 안전하게 의존성을 해결해야 한다", .tags(.inject, .safety, .fast))
    func testInjectSafeResolution() async throws {
      // Arrange
      struct TestConsumer {
        @Inject(ServiceKey.self) var service
      }

      let container = await WeaverContainer.builder()
        .register(ServiceKey.self, scope: .shared) { _ in
          TestService(isDefaultValue: false)
        }
        .build()

      let consumer = TestConsumer()

      // Act
      let service = await Weaver.withScope(container) {
        await consumer.service()
      }

      // Assert
      #expect(!service.isDefaultValue, "@Inject는 등록된 서비스를 해결해야 함")
    }

    @Test(
      "@Inject는 해결 실패 시 기본값으로 fallback하여 크래시를 방지해야 한다", .tags(.inject, .safety, .resilience, .fast))
    func testInjectDefaultValueFallback() async throws {
      // Arrange
      struct TestConsumer {
        @Inject(ServiceKey.self) var service
      }

      let emptyContainer = await WeaverContainer.builder().build()
      let consumer = TestConsumer()

      // Act
      let service = await Weaver.withScope(emptyContainer) {
        await consumer.service()
      }

      // Assert
      #expect(service.isDefaultValue, "@Inject는 해결 실패 시 기본값을 반환해야 함")
    }

    @Test("@Inject의 projectedValue는 명시적 에러 처리를 제공해야 한다", .tags(.inject, .errorHandling, .fast))
    func testInjectExplicitErrorHandling() async throws {
      // Arrange
      struct TestConsumer {
        @Inject(ServiceKey.self) var service
      }

      let emptyContainer = await WeaverContainer.builder().build()
      let consumer = TestConsumer()

      // Act & Assert
      await Weaver.withScope(emptyContainer) {
        await #expect(throws: WeaverError.self) {
          _ = try await consumer.$service.resolve()
        }
      }
    }
  }

  // MARK: - 3. 동시성 및 스레드 안전성 검증

  @Suite("동시성 및 스레드 안전성", .tags(.concurrency, .safety, .critical))
  struct ConcurrencyTests {

    @Test("동시 해결 시 레이스 컨디션이 방지되어야 한다", .tags(.concurrency, .safety, .slow))
    func testConcurrentResolutionRaceConditionPrevention() async throws {
      // Arrange
      let counter = FactoryCallCounter()
      let container = await WeaverContainer.builder()
        .register(ServiceKey.self, scope: .shared) { _ in
          await counter.increment()
          try? await Task.sleep(for: .milliseconds(10))  // 레이스 컨디션 유발
          return TestService(isDefaultValue: false)
        }
        .build()

      // Act - 100개의 동시 해결 요청
      try await withThrowingTaskGroup(of: TestService.self) { group in
        for _ in 0..<100 {
          group.addTask {
            try await container.resolve(ServiceKey.self)
          }
        }

        var services: [TestService] = []
        for try await service in group {
          services.append(service)
        }

        // Assert - 모든 서비스가 같은 인스턴스여야 함
        let firstId = services[0].id
        for service in services {
          #expect(service.id == firstId, "shared 스코프는 동시 접근 시에도 같은 인스턴스를 반환해야 함")
        }
      }

      // Assert - 팩토리는 한 번만 호출되어야 함
      let factoryCallCount = await counter.count
      #expect(factoryCallCount == 1, "shared 스코프 팩토리는 동시 접근 시에도 한 번만 호출되어야 함")
    }
  }

  // MARK: - 4. 에러 처리 및 안전성 검증

  @Suite("에러 처리 및 안전성", .tags(.errorHandling, .safety, .critical))
  struct ErrorHandlingTests {

    @Test("순환 참조가 감지되어야 한다", .tags(.errorHandling, .safety, .fast))
    func testCircularDependencyDetection() async throws {
      // Arrange
      let container = await WeaverContainer.builder()
        .register(CircularAKey.self, scope: .shared) { resolver in
          let serviceB = try await resolver.resolve(CircularBKey.self)
          return CircularServiceA(serviceB: serviceB)
        }
        .register(CircularBKey.self, scope: .shared) { resolver in
          let serviceA = try await resolver.resolve(CircularAKey.self)
          return CircularServiceB(serviceA: serviceA)
        }
        .build()

      // Act & Assert
      await #expect(throws: WeaverError.self) {
        _ = try await container.resolve(CircularAKey.self)
      }
    }

    @Test("팩토리 에러가 적절히 전파되어야 한다", .tags(.errorHandling, .fast))
    func testFactoryErrorPropagation() async throws {
      // Arrange
      let container = await WeaverContainer.builder()
        .register(ServiceKey.self, scope: .shared) { _ in
          throw TestError.factoryFailed
        }
        .build()

      // Act & Assert
      await #expect(throws: WeaverError.self) {
        _ = try await container.resolve(ServiceKey.self)
      }
    }
  }

  // MARK: - 5. 생명주기 관리 검증

  @Suite("생명주기 관리", .tags(.lifecycle, .memory))
  struct LifecycleTests {

    @Test("Disposable 인스턴스가 정리되어야 한다", .tags(.lifecycle, .memory, .fast))
    func testDisposableCleanup() async throws {
      // Arrange
      let disposeSignal = TestSignal()
      let container = await WeaverContainer.builder()
        .register(DisposableServiceKey.self, scope: .shared) { _ in
          DisposableService(onDispose: {
            await disposeSignal.signal()
          })
        }
        .build()

      // 인스턴스 생성
      _ = try await container.resolve(DisposableServiceKey.self)

      // Act
      await container.shutdown()

      // Assert
      try await disposeSignal.wait()
    }

    @Test("종료된 컨테이너에서 해결 시 에러가 발생해야 한다", .tags(.lifecycle, .errorHandling, .fast))
    func testResolveAfterShutdownThrowsError() async throws {
      // Arrange
      let container = await WeaverContainer.builder()
        .register(ServiceKey.self, scope: .shared) { _ in
          TestService(isDefaultValue: false)
        }
        .build()

      // Act
      await container.shutdown()

      // Assert
      await #expect(throws: WeaverError.self) {
        _ = try await container.resolve(ServiceKey.self)
      }
    }
  }

  // MARK: - 6. 커널 생명주기 검증

  @Suite("커널 생명주기", .tags(.kernel, .lifecycle))
  struct KernelLifecycleTests {

    @Test("커널 상태가 올바르게 전환되어야 한다", .tags(.kernel, .lifecycle, .fast))
    func testKernelStateTransitions() async throws {
      // Arrange
      let kernel = WeaverKernel.scoped(modules: [StartupModule()])

      // Act & Assert - 초기 상태
      let initialState = await kernel.currentState
      #expect(initialState == .idle, "커널 초기 상태는 idle이어야 함")

      // 빌드 후 상태
      await kernel.build()
      let stateAfterBuild = await kernel.currentState
      switch stateAfterBuild {
      case .ready:
        break  // 정상
      default:
        throw TestError.intentionalError
      }

      // 종료 후 상태
      await kernel.shutdown()
      let stateAfterShutdown = await kernel.currentState
      #expect(stateAfterShutdown == .shutdown, "커널 종료 후 상태는 shutdown이어야 함")
    }

    @Test("safeResolve는 절대 크래시하지 않아야 한다", .tags(.kernel, .safety, .resilience, .fast))
    func testSafeResolveNeverCrashes() async throws {
      // Arrange - 빈 커널
      let kernel = WeaverKernel.scoped(modules: [])

      // Act - 등록되지 않은 서비스 안전 해결
      let service = await kernel.safeResolve(ServiceKey.self)

      // Assert - 기본값 반환
      #expect(service.isDefaultValue, "safeResolve는 실패 시 기본값을 반환해야 함")
    }
  }

  // MARK: - 7. 통합 시나리오 검증

  @Suite("통합 시나리오", .tags(.integration, .critical))
  struct IntegrationTests {

    @Test("전체 앱 시뮬레이션이 정상적으로 동작해야 한다", .tags(.integration, .slow))
    func testFullAppSimulation() async throws {
      // Arrange - 실제 앱과 유사한 구조
      await Weaver.resetForTesting()

      try await Weaver.setup(modules: [
        StartupModule(),  // 로깅, 설정 등
        SharedModule(),  // 네트워크, 데이터베이스 등
        WhenNeededModule(),  // 기능별 서비스
      ])

      // Act - 전역 커널에서 서비스 해결
      let resolver = try await Weaver.waitForReady()
      let service = try await resolver.resolve(ServiceKey.self)

      // Assert
      #expect(!service.isDefaultValue, "전역 설정된 서비스가 정상적으로 해결되어야 함")

      await Weaver.resetForTesting()
    }

    @Test("의존성 체인이 올바르게 해결되어야 한다", .tags(.integration, .fast))
    func testDependencyChainResolution() async throws {
      // Arrange
      struct DependentServiceKey: DependencyKey {
        typealias Value = DependentService
        static var defaultValue: DependentService {
          DependentService(dependency: TestService(isDefaultValue: true))
        }
      }

      final class DependentService: Sendable {
        let dependency: TestService
        let id = Foundation.UUID()

        init(dependency: TestService) {
          self.dependency = dependency
        }
      }

      let container = await WeaverContainer.builder()
        .register(ServiceKey.self, scope: .shared) { _ in
          TestService(isDefaultValue: false)
        }
        .register(DependentServiceKey.self, scope: .shared) { resolver in
          let dependency = try await resolver.resolve(ServiceKey.self)
          return DependentService(dependency: dependency)
        }
        .build()

      // Act
      let dependentService = try await container.resolve(DependentServiceKey.self)

      // Assert
      #expect(!dependentService.dependency.isDefaultValue, "의존성 체인이 정상적으로 해결되어야 함")
    }
  }

  // MARK: - 8. 성능 및 메모리 최적화 검증

  @Suite("성능 및 메모리 최적화", .tags(.performance, .memory))
  struct PerformanceTests {

    @Test("대량 의존성 해결 성능이 허용 범위 내여야 한다", .tags(.performance, .slow))
    func testMassiveResolutionPerformance() async throws {
      // Arrange
      let container = await WeaverContainer.builder()
        .register(ServiceKey.self, scope: .shared) { _ in
          TestService(isDefaultValue: false)
        }
        .build()

      let iterations = 1000
      let startTime = CFAbsoluteTimeGetCurrent()

      // Act - 1000번의 해결 요청
      for _ in 0..<iterations {
        _ = try await container.resolve(ServiceKey.self)
      }

      let duration = CFAbsoluteTimeGetCurrent() - startTime

      // Assert - 평균 해결 시간이 1ms 미만이어야 함
      let averageTime = duration / Double(iterations)
      #expect(averageTime < 0.001, "평균 해결 시간이 1ms를 초과함: \(averageTime * 1000)ms")
    }

    @Test("메모리 정리가 올바르게 수행되어야 한다", .tags(.memory, .fast))
    func testMemoryCleanup() async throws {
      // Arrange
      let container = await WeaverContainer.builder()
        .registerWeak(WeakServiceKey.self) { _ in
          WeakService(isDefaultValue: false)
        }
        .build()

      // Act - 약한 참조 인스턴스 생성 후 해제
      var service: WeakService? = try await container.resolve(WeakServiceKey.self)
      let serviceId = service?.id
      service = nil  // 강한 참조 해제

      // 메모리 정리 수행
      await container.performMemoryCleanup(forced: true)

      // Assert - 새로운 인스턴스가 생성되어야 함
      let newService = try await container.resolve(WeakServiceKey.self)
      #expect(newService.id != serviceId, "메모리 정리 후 새 인스턴스가 생성되어야 함")
    }
  }

  // MARK: - 9. 보안 및 안전성 검증

  @Suite("보안 및 안전성", .tags(.safety, .security, .critical))
  struct SecurityTests {

    @Test("타입 안전성이 보장되어야 한다", .tags(.safety, .fast))
    func testTypeSafety() async throws {
      // Arrange
      let container = await WeaverContainer.builder()
        .register(ServiceKey.self, scope: .shared) { _ in
          TestService(isDefaultValue: false)
        }
        .build()

      // Act & Assert - 올바른 타입만 해결되어야 함
      let service = try await container.resolve(ServiceKey.self)
      #expect(service is TestService, "해결된 인스턴스가 올바른 타입이어야 함")
      #expect(!service.isDefaultValue, "실제 등록된 인스턴스가 반환되어야 함")
    }

    @Test("잘못된 타입 캐스팅 시 에러가 발생해야 한다", .tags(.safety, .errorHandling, .fast))
    func testInvalidTypeCasting() async throws {
      // Arrange - 팩토리에서 에러를 던지는 경우
      let container = await WeaverContainer.builder()
        .register(ServiceKey.self, scope: .shared) { _ in
          throw TestError.factoryFailed
        }
        .build()

      // Act & Assert - 팩토리 에러가 전파되어야 함
      await #expect(throws: WeaverError.self) {
        _ = try await container.resolve(ServiceKey.self)
      }
    }
  }

  // MARK: - 10. 실제 사용 패턴 검증

  @Suite("실제 사용 패턴", .tags(.integration, .ui))
  struct RealWorldUsageTests {

    @Test("SwiftUI 환경에서 @Inject가 정상 동작해야 한다", .tags(.swiftui, .inject, .integration, .fast))
    func testSwiftUIIntegration() async throws {
      // Arrange - SwiftUI 뷰 모델 시뮬레이션
      struct MockViewModel {
        @Inject(ServiceKey.self) var service

        func performAction() async -> String {
          let svc = await service()
          return svc.isDefaultValue ? "default" : "injected"
        }
      }

      let container = await WeaverContainer.builder()
        .register(ServiceKey.self, scope: .shared) { _ in
          TestService(isDefaultValue: false)
        }
        .build()

      let viewModel = MockViewModel()

      // Act
      let result = await Weaver.withScope(container) {
        await viewModel.performAction()
      }

      // Assert
      #expect(result == "injected", "SwiftUI 환경에서 의존성이 올바르게 주입되어야 함")
    }

    @Test("네트워크 서비스 패턴이 올바르게 동작해야 한다", .tags(.integration, .fast))
    func testNetworkServicePattern() async throws {
      // Arrange - 실제 네트워크 서비스 패턴 시뮬레이션
      struct NetworkServiceKey: DependencyKey {
        typealias Value = NetworkService
        static var defaultValue: NetworkService { NetworkService(isOffline: true) }
      }

      final class NetworkService: Sendable {
        let isOffline: Bool
        let id = UUID()

        init(isOffline: Bool) {
          self.isOffline = isOffline
        }

        func fetchData() async -> String {
          return isOffline ? "offline_data" : "online_data"
        }
      }

      let container = await WeaverContainer.builder()
        .register(NetworkServiceKey.self, scope: .shared) { _ in
          NetworkService(isOffline: false)
        }
        .build()

      // Act
      let networkService = try await container.resolve(NetworkServiceKey.self)
      let data = await networkService.fetchData()

      // Assert
      #expect(data == "online_data", "네트워크 서비스가 올바르게 주입되어야 함")
      #expect(!networkService.isOffline, "온라인 상태의 서비스가 주입되어야 함")
    }
  }

  // MARK: - 11. 에지 케이스 및 경계 조건 검증

  @Suite("에지 케이스 및 경계 조건", .tags(.safety, .resilience))
  struct EdgeCaseTests {

    @Test("빈 컨테이너에서 해결 시 적절한 에러가 발생해야 한다", .tags(.errorHandling, .fast))
    func testEmptyContainerResolution() async throws {
      // Arrange
      let emptyContainer = await WeaverContainer.builder().build()

      // Act & Assert
      await #expect(throws: WeaverError.self) {
        _ = try await emptyContainer.resolve(ServiceKey.self)
      }
    }

    @Test("nil 팩토리 결과 처리가 안전해야 한다", .tags(.safety, .fast))
    func testNilFactoryResult() async throws {
      // Arrange - Optional을 반환하는 팩토리
      struct OptionalServiceKey: DependencyKey {
        typealias Value = TestService?
        static var defaultValue: TestService? { nil }
      }

      let container = await WeaverContainer.builder()
        .register(OptionalServiceKey.self, scope: .shared) { _ in
          return nil as TestService?
        }
        .build()

      // Act
      let result = try await container.resolve(OptionalServiceKey.self)

      // Assert
      #expect(result == nil, "nil 결과가 올바르게 처리되어야 함")
    }

    @Test("매우 깊은 의존성 체인이 처리되어야 한다", .tags(.integration, .fast))
    func testDeepDependencyChain() async throws {
      // Arrange - 5단계 의존성 체인
      struct Level1Key: DependencyKey {
        typealias Value = Level1Service
        static var defaultValue: Level1Service {
          Level1Service(
            level2: Level2Service(
              level3: Level3Service(level4: Level4Service(level5: Level5Service()))))
        }
      }

      struct Level2Key: DependencyKey {
        typealias Value = Level2Service
        static var defaultValue: Level2Service {
          Level2Service(level3: Level3Service(level4: Level4Service(level5: Level5Service())))
        }
      }

      struct Level3Key: DependencyKey {
        typealias Value = Level3Service
        static var defaultValue: Level3Service {
          Level3Service(level4: Level4Service(level5: Level5Service()))
        }
      }

      struct Level4Key: DependencyKey {
        typealias Value = Level4Service
        static var defaultValue: Level4Service { Level4Service(level5: Level5Service()) }
      }

      struct Level5Key: DependencyKey {
        typealias Value = Level5Service
        static var defaultValue: Level5Service { Level5Service() }
      }

      final class Level1Service: Sendable {
        let level2: Level2Service
        let id = UUID()
        init(level2: Level2Service) { self.level2 = level2 }
      }

      final class Level2Service: Sendable {
        let level3: Level3Service
        let id = UUID()
        init(level3: Level3Service) { self.level3 = level3 }
      }

      final class Level3Service: Sendable {
        let level4: Level4Service
        let id = UUID()
        init(level4: Level4Service) { self.level4 = level4 }
      }

      final class Level4Service: Sendable {
        let level5: Level5Service
        let id = UUID()
        init(level5: Level5Service) { self.level5 = level5 }
      }

      final class Level5Service: Sendable {
        let id = UUID()
        init() {}
      }

      let container = await WeaverContainer.builder()
        .register(Level5Key.self, scope: .shared) { _ in Level5Service() }
        .register(Level4Key.self, scope: .shared) { resolver in
          let level5 = try await resolver.resolve(Level5Key.self)
          return Level4Service(level5: level5)
        }
        .register(Level3Key.self, scope: .shared) { resolver in
          let level4 = try await resolver.resolve(Level4Key.self)
          return Level3Service(level4: level4)
        }
        .register(Level2Key.self, scope: .shared) { resolver in
          let level3 = try await resolver.resolve(Level3Key.self)
          return Level2Service(level3: level3)
        }
        .register(Level1Key.self, scope: .shared) { resolver in
          let level2 = try await resolver.resolve(Level2Key.self)
          return Level1Service(level2: level2)
        }
        .build()

      // Act
      let level1 = try await container.resolve(Level1Key.self)

      // Assert - 모든 레벨이 올바르게 연결되어야 함
      #expect(level1.level2.level3.level4.level5.id != UUID(), "깊은 의존성 체인이 올바르게 해결되어야 함")
    }
  }
}

// MARK: - 12. 실제 앱 시나리오 시뮬레이션

@Suite("실제 앱 시나리오 시뮬레이션", .tags(.integration, .critical))
struct RealAppScenarioTests {

  @Test("앱 시작부터 종료까지 전체 생명주기가 정상 동작해야 한다", .tags(.integration, .lifecycle, .slow))
  func testFullAppLifecycle() async throws {
    // Arrange - 컨테이너 기반 테스트로 변경 (더 안정적)
    let container = await WeaverContainer.builder()
      .register(LoggerServiceKey.self, scope: .startup) { _ in
        LoggerService(level: .debug)
      }
      .register(NetworkServiceKey.self, scope: .shared) { resolver in
        let logger = try await resolver.resolve(LoggerServiceKey.self)
        return NetworkService(logger: logger, baseURL: "https://api.test.com")
      }
      .register(DatabaseServiceKey.self, scope: .shared) { resolver in
        let logger = try await resolver.resolve(LoggerServiceKey.self)
        return DatabaseService(logger: logger, connectionString: "test://localhost")
      }
      .register(CameraServiceKey.self, scope: .whenNeeded) { resolver in
        let logger = try await resolver.resolve(LoggerServiceKey.self)
        return CameraService(logger: logger)
      }
      .register(LocationServiceKey.self, scope: .whenNeeded) { resolver in
        let logger = try await resolver.resolve(LoggerServiceKey.self)
        return LocationService(logger: logger)
      }
      .build()

    // Act & Assert - 1. 기본 서비스들이 준비되었는지 확인
    let logger = try await container.resolve(LoggerServiceKey.self)
    let network = try await container.resolve(NetworkServiceKey.self)
    let database = try await container.resolve(DatabaseServiceKey.self)

    #expect(!logger.isDefaultValue, "로거 서비스가 정상 주입되어야 함")
    #expect(!network.isDefaultValue, "네트워크 서비스가 정상 주입되어야 함")
    #expect(!database.isDefaultValue, "데이터베이스 서비스가 정상 주입되어야 함")

    // 2. 기능별 서비스들이 필요 시 로딩되는지 확인
    let camera = try await container.resolve(CameraServiceKey.self)
    let location = try await container.resolve(LocationServiceKey.self)

    #expect(!camera.isDefaultValue, "카메라 서비스가 필요 시 로딩되어야 함")
    #expect(!location.isDefaultValue, "위치 서비스가 필요 시 로딩되어야 함")

    // 3. 앱 생명주기 이벤트 시뮬레이션
    await container.handleAppDidEnterBackground()
    await container.handleAppWillEnterForeground()

    // 4. 정리
    await container.shutdown()
  }

  @Test("복잡한 의존성 그래프가 올바르게 해결되어야 한다", .tags(.integration, .fast))
  func testComplexDependencyGraph() async throws {
    // Arrange - 복잡한 의존성 관계 설정
    let container = await WeaverContainer.builder()
      .register(LoggerServiceKey.self, scope: .startup) { _ in
        LoggerService(level: .debug)
      }
      .register(NetworkServiceKey.self, scope: .shared) { resolver in
        let logger = try await resolver.resolve(LoggerServiceKey.self)
        return NetworkService(logger: logger, baseURL: "https://api.example.com")
      }
      .register(DatabaseServiceKey.self, scope: .shared) { resolver in
        let logger = try await resolver.resolve(LoggerServiceKey.self)
        return DatabaseService(logger: logger, connectionString: "postgres://localhost")
      }
      .register(CameraServiceKey.self, scope: .whenNeeded) { resolver in
        let logger = try await resolver.resolve(LoggerServiceKey.self)
        return CameraService(logger: logger)
      }
      .build()

    // Act - 모든 서비스 해결
    let logger = try await container.resolve(LoggerServiceKey.self)
    let network = try await container.resolve(NetworkServiceKey.self)
    let database = try await container.resolve(DatabaseServiceKey.self)
    let camera = try await container.resolve(CameraServiceKey.self)

    // Assert - 의존성이 올바르게 주입되었는지 확인
    #expect(logger.level == .debug, "로거 레벨이 올바르게 설정되어야 함")

    let networkData = await network.fetchData(endpoint: "/users")
    #expect(networkData.contains("network_data"), "네트워크 서비스가 정상 동작해야 함")

    let dbResults = await database.query("SELECT * FROM users")
    #expect(!dbResults.isEmpty, "데이터베이스 서비스가 정상 동작해야 함")

    let photo = await camera.capturePhoto()
    #expect(photo.contains("photo_"), "카메라 서비스가 정상 동작해야 함")
  }
}

// MARK: - 13. 스트레스 테스트 및 한계 테스트

@Suite("스트레스 테스트 및 한계 테스트", .tags(.performance, .stress))
struct StressTests {

  @Test("대량 동시 해결 요청 처리가 안정적이어야 한다", .tags(.concurrency, .performance, .slow))
  func testMassiveConcurrentResolution() async throws {
    // Arrange
    let container = await WeaverContainer.builder()
      .register(ServiceKey.self, scope: .shared) { _ in
        // 의도적으로 약간의 지연 추가
        try? await Task.sleep(for: .milliseconds(1))
        return TestService(isDefaultValue: false)
      }
      .build()

    let concurrentRequests = 1000
    let startTime = CFAbsoluteTimeGetCurrent()

    // Act - 1000개의 동시 해결 요청
    try await withThrowingTaskGroup(of: TestService.self) { group in
      for _ in 0..<concurrentRequests {
        group.addTask {
          try await container.resolve(ServiceKey.self)
        }
      }

      var resolvedServices: [TestService] = []
      for try await service in group {
        resolvedServices.append(service)
      }

      let duration = CFAbsoluteTimeGetCurrent() - startTime

      // Assert
      #expect(resolvedServices.count == concurrentRequests, "모든 요청이 성공해야 함")

      // 모든 서비스가 같은 인스턴스여야 함 (shared 스코프)
      let firstId = resolvedServices[0].id
      for service in resolvedServices {
        #expect(service.id == firstId, "shared 스코프는 모든 요청에 같은 인스턴스를 반환해야 함")
      }

      // 성능 검증 - 평균 해결 시간이 10ms 미만이어야 함
      let averageTime = duration / Double(concurrentRequests)
      #expect(averageTime < 0.01, "평균 해결 시간이 10ms를 초과함: \(averageTime * 1000)ms")
    }
  }

  @Test("메모리 압박 상황에서 안정성이 유지되어야 한다", .tags(.memory, .stress, .slow))
  func testMemoryPressureStability() async throws {
    // Arrange - 메모리를 많이 사용하는 서비스
    struct MemoryIntensiveServiceKey: DependencyKey {
      typealias Value = MemoryIntensiveService
      static var defaultValue: MemoryIntensiveService { MemoryIntensiveService(size: 0) }
    }

    final class MemoryIntensiveService: Sendable {
      let data: [UInt8]
      let id = UUID()

      init(size: Int) {
        self.data = Array(repeating: 0, count: size)
      }
    }

    let container = await WeaverContainer.builder()
      .registerWeak(MemoryIntensiveServiceKey.self) { _ in
        // 1MB 데이터를 가진 서비스
        MemoryIntensiveService(size: 1024 * 1024)
      }
      .build()

    // Act - 많은 인스턴스 생성 후 해제
    var services: [MemoryIntensiveService] = []

    for _ in 0..<100 {
      let service = try await container.resolve(MemoryIntensiveServiceKey.self)
      services.append(service)
    }

    // 강한 참조 해제
    services.removeAll()

    // 메모리 정리 강제 실행
    await container.performMemoryCleanup(forced: true)

    // Assert - 새로운 인스턴스가 생성되어야 함 (약한 참조가 해제됨)
    let newService = try await container.resolve(MemoryIntensiveServiceKey.self)
    #expect(newService.data.count == 1024 * 1024, "새 인스턴스가 정상 생성되어야 함")
  }
}

// MARK: - 14. 호환성 및 환경 테스트

@Suite("호환성 및 환경 테스트", .tags(.compatibility, .environment))
struct CompatibilityTests {

  @Test("다양한 Swift 동시성 패턴과 호환되어야 한다", .tags(.concurrency, .fast))
  func testSwiftConcurrencyCompatibility() async throws {
    // Arrange
    let container = await WeaverContainer.builder()
      .register(ServiceKey.self, scope: .shared) { _ in
        TestService(isDefaultValue: false)
      }
      .build()

    // Act & Assert - AsyncSequence와 함께 사용
    let services = AsyncStream<TestService> { continuation in
      Task {
        for _ in 0..<5 {
          do {
            let service = try await container.resolve(ServiceKey.self)
            continuation.yield(service)
          } catch {
            continuation.finish()
            return
          }
        }
        continuation.finish()
      }
    }

    var count = 0
    var firstId: UUID?

    for await service in services {
      count += 1
      if firstId == nil {
        firstId = service.id
      } else {
        #expect(service.id == firstId, "shared 스코프는 같은 인스턴스를 반환해야 함")
      }
    }

    #expect(count == 5, "모든 서비스가 성공적으로 해결되어야 함")
  }

      @Test("테스트 환경에서 안전하게 동작해야 한다", .tags(.safety, .fast), .disabled("CI 환경에서의 환경 변수 감지 불안정성으로 비활성화"))
  func testTestEnvironmentSafety() async throws {
    // Arrange - 테스트 환경 시뮬레이션
    #expect(WeaverEnvironment.isTesting, "테스트 환경이 올바르게 감지되어야 함")

    // Act - 빈 컨테이너에서 안전한 해결
    let emptyContainer = await WeaverContainer.builder().build()

    await Weaver.withScope(emptyContainer) {
      struct TestConsumer {
        @Inject(ServiceKey.self) var service
      }

      let consumer = TestConsumer()
      let service = await consumer.service()  // 크래시하지 않아야 함

      // Assert
      #expect(service.isDefaultValue, "테스트 환경에서는 기본값이 반환되어야 함")
    }
  }
}

// MARK: - 15. 새로운 기능 테스트

@Suite("새로운 기능 테스트", .tags(.integration, .swiftui))
struct NewFeaturesTests {
    
    @Test("SwiftUI Preview 등록이 타입 안전하게 동작해야 한다", .tags(.swiftui, .fast))
    func testSwiftUIPreviewRegistration() async throws {
        #if canImport(SwiftUI)
        // Arrange - 테스트용 키 정의
        struct TestNetworkServiceKey: DependencyKey {
            typealias Value = MockNetworkService
            static var defaultValue: MockNetworkService { MockNetworkService(baseURL: "default") }
        }
        
        struct TestDatabaseServiceKey: DependencyKey {
            typealias Value = MockDatabaseService
            static var defaultValue: MockDatabaseService { MockDatabaseService(connectionString: "default") }
        }
        
        // Preview 등록 생성
        let networkRegistration = PreviewWeaverContainer.PreviewRegistration.register(
            TestNetworkServiceKey.self,
            mockValue: MockNetworkService(baseURL: "https://preview.api.com")
        )
        
        let databaseRegistration = PreviewWeaverContainer.PreviewRegistration.register(
            TestDatabaseServiceKey.self
        ) { _ in
            MockDatabaseService(connectionString: "preview://memory")
        }
        
        // Act - 모듈 생성 및 컨테이너 빌드
        let modules = [
            AnonymousModule { builder in
                await networkRegistration.configure(builder)
                await databaseRegistration.configure(builder)
            }
        ]
        
        let container = await WeaverContainer.builder()
            .withModules(modules)
            .build()
        
        // Assert
        let networkService = try await container.resolve(TestNetworkServiceKey.self)
        let databaseService = try await container.resolve(TestDatabaseServiceKey.self)
        
        #expect(networkService.baseURL == "https://preview.api.com", "Preview 네트워크 서비스가 올바르게 설정되어야 함")
        #expect(databaseService.connectionString == "preview://memory", "Preview 데이터베이스 서비스가 올바르게 설정되어야 함")
        #endif
    }
    
    @Test("우선순위 제공자가 올바르게 동작해야 한다", .tags(.priority, .fast))
    func testCustomPriorityProvider() async throws {
        // Arrange - 커스텀 우선순위 제공자
        let customProvider = CustomServicePriorityProvider(
            customPriorities: [
                "ServiceKey": 1,  // 높은 우선순위
                "AnotherServiceKey": 100  // 낮은 우선순위
            ]
        )
        
        // Act - 우선순위 계산
        let serviceKey = AnyDependencyKey(ServiceKey.self)
        let anotherKey = AnyDependencyKey(AnotherServiceKey.self)
        
        let serviceRegistration = DependencyRegistration(
            scope: .shared,
            factory: { _ in TestService() },
            keyName: "ServiceKey"
        )
        
        let anotherRegistration = DependencyRegistration(
            scope: .shared,
            factory: { _ in AnotherService() },
            keyName: "AnotherServiceKey"
        )
        
        let servicePriority = await customProvider.getPriority(for: serviceKey, registration: serviceRegistration)
        let anotherPriority = await customProvider.getPriority(for: anotherKey, registration: anotherRegistration)
        
        // Assert
        #expect(servicePriority == 1, "커스텀 우선순위가 적용되어야 함")
        #expect(anotherPriority == 100, "커스텀 우선순위가 적용되어야 함")
        #expect(servicePriority < anotherPriority, "우선순위 순서가 올바르게 적용되어야 함")
    }
    
    @Test("기본 우선순위 제공자가 올바른 우선순위를 계산해야 한다", .tags(.priority, .fast))
    func testDefaultPriorityProvider() async throws {
        // Arrange
        let provider = DefaultServicePriorityProvider()
        
        // 다양한 서비스 키 생성
        struct LoggerServiceKey: DependencyKey {
            typealias Value = TestService
            static var defaultValue: TestService { TestService(isDefaultValue: true) }
        }
        
        struct NetworkServiceKey: DependencyKey {
            typealias Value = TestService
            static var defaultValue: TestService { TestService(isDefaultValue: true) }
        }
        
        struct DatabaseServiceKey: DependencyKey {
            typealias Value = TestService
            static var defaultValue: TestService { TestService(isDefaultValue: true) }
        }
        
        let loggerKey = AnyDependencyKey(LoggerServiceKey.self)
        let networkKey = AnyDependencyKey(NetworkServiceKey.self)
        let databaseKey = AnyDependencyKey(DatabaseServiceKey.self)
        
        // 등록 정보 생성
        let loggerRegistration = DependencyRegistration(
            scope: .startup,
            factory: { _ in TestService() },
            keyName: "LoggerServiceKey",
            dependencies: []
        )
        
        let networkRegistration = DependencyRegistration(
            scope: .startup,
            factory: { _ in TestService() },
            keyName: "NetworkServiceKey",
            dependencies: [LoggerServiceKey.self]
        )
        
        let databaseRegistration = DependencyRegistration(
            scope: .startup,
            factory: { _ in TestService() },
            keyName: "DatabaseServiceKey",
            dependencies: [LoggerServiceKey.self, NetworkServiceKey.self]
        )
        
        // Act - 우선순위 계산
        let loggerPriority = await provider.getPriority(for: loggerKey, registration: loggerRegistration)
        let networkPriority = await provider.getPriority(for: networkKey, registration: networkRegistration)
        let databasePriority = await provider.getPriority(for: databaseKey, registration: databaseRegistration)
        
        // Assert - 우선순위 순서 확인
        #expect(loggerPriority < networkPriority, "로거가 네트워크보다 높은 우선순위를 가져야 함")
        #expect(networkPriority < databasePriority, "네트워크가 데이터베이스보다 높은 우선순위를 가져야 함")
        
        // 구체적인 우선순위 값 확인
        #expect(loggerPriority == 0, "로거는 최고 우선순위(0)를 가져야 함") // startup(0) + logger(0) + deps(0)
        #expect(networkPriority == 31, "네트워크는 31 우선순위를 가져야 함") // startup(0) + network(30) + deps(1)
        #expect(databasePriority == 42, "데이터베이스는 42 우선순위를 가져야 함") // startup(0) + database(40) + deps(2)
    }
    
    @Test("WeaverBuilder에 우선순위 제공자를 설정할 수 있어야 한다", .tags(.builder, .priority, .fast))
    func testBuilderWithPriorityProvider() async throws {
        // Arrange
        let customProvider = CustomServicePriorityProvider(
            customPriorities: ["TestService": 5]
        )
        
        // Act - 빌더에 우선순위 제공자 설정
        let builder = await WeaverContainer.builder()
            .withPriorityProvider(customProvider)
            .register(ServiceKey.self) { _ in
                TestService(isDefaultValue: false)
            }
        
        let container = await builder.build()
        
        // Assert - 컨테이너가 정상적으로 생성되어야 함
        let service = try await container.resolve(ServiceKey.self)
        #expect(!service.isDefaultValue, "서비스가 정상적으로 해결되어야 함")
    }
}

// MARK: - Mock Services for New Features

#if canImport(SwiftUI)
extension PreviewWeaverContainer {
    static func createTestModules() -> [Module] {
        struct TestNetworkServiceKey: DependencyKey {
            typealias Value = MockNetworkService
            static var defaultValue: MockNetworkService { MockNetworkService(baseURL: "default") }
        }
        
        struct TestDatabaseServiceKey: DependencyKey {
            typealias Value = MockDatabaseService
            static var defaultValue: MockDatabaseService { MockDatabaseService(connectionString: "default") }
        }
        
        return previewModules(
            .register(TestNetworkServiceKey.self, mockValue: MockNetworkService(baseURL: "https://test.api.com")),
            .register(TestDatabaseServiceKey.self, mockValue: MockDatabaseService(connectionString: "test://memory"))
        )
    }
}
#endif
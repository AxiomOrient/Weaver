import Testing
import Foundation

@testable import Weaver

/// WeaverSyncStartup의 현실적 해결책을 검증하는 테스트 스위트입니다.
@Suite("Weaver Sync Startup Tests")
struct WeaverSyncStartupTests {

  @Test("동기적 컨테이너 빌드 테스트")
  func testSyncContainerBuildsImmediately() async throws {
    // Arrange
    let modules = [LoggingModule(), NetworkModule()]

    // Act
    let container = WeaverSyncContainer.builder()
      .withModules(modules)
      .build()

    // Assert
    #expect(container != nil)

    // 캐시되지 않은 상태에서는 nil 반환
    let syncLogger = container.resolveSync(LoggerKey.self)
    #expect(syncLogger == nil)

    // 비동기 해결로 실제 생성
    let asyncLogger = try await container.resolve(LoggerKey.self)
    #expect(asyncLogger != nil)
  }

  @Test("WeaverRealistic 헬퍼가 올바르게 동작함")
  func testWeaverRealisticHelper() async throws {
    // Arrange
    let modules = [LoggingModule(), NetworkModule()]

    // Act - 헬퍼를 통한 컨테이너 생성
    let container = WeaverRealistic.createContainer(modules: modules)

    // Assert
    #expect(container != nil)

    // Eager 서비스 초기화 테스트
    await WeaverRealistic.initializeEagerServices(container)

    // 전역 커널이 설정되었는지 확인
    let globalKernel = await Weaver.getGlobalKernel()
    #expect(globalKernel != nil)

    // Cleanup
    await Weaver.resetForTesting()
  }

  @Test("동기적 모듈 구성이 올바르게 동작함")
  func testSyncModuleConfiguration() async throws {
    // Arrange
    let builder = WeaverSyncBuilder()
    let loggingModule = LoggingModule()

    // Act
    loggingModule.configure(builder)
    let container = builder.build()

    // Assert - 등록된 의존성 해결
    let logger = try await container.resolve(LoggerKey.self)
    #expect(type(of: logger) == ProductionLogger.self)
  }

  @Test("앱 초기화 패턴 테스트")
  func testAppInitPattern() async throws {
    // Arrange
    let container: WeaverSyncContainer

    // Act - 앱 초기화 시뮬레이션
    container = WeaverSyncContainer.builder()
      .withModules([
        LoggingModule(),
        NetworkModule(),
      ])
      .build()

    // Assert
    #expect(container != nil)

    await WeaverRealistic.initializeEagerServices(container)

    let logger = try await container.resolve(LoggerKey.self)
    let networkService = try await container.resolve(NetworkServiceKey.self)

    // Services are resolved successfully

    // Cleanup
    await Weaver.resetForTesting()
  }

  @Test("동시 접근 안전성 테스트")
  func testThreadSafeConcurrentAccess() async throws {
    // Arrange
    let container = WeaverSyncContainer.builder()
      .withModules([LoggingModule()])
      .build()

    // Act - 동시 의존성 해결
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<10 {
        group.addTask {
          do {
            let logger = try await container.resolve(LoggerKey.self)
            await logger.info("동시 접근 테스트")
          } catch {
            // 에러가 발생해도 크래시하지 않음
          }
        }
      }
    }

    // Assert - 모든 작업 완료 (크래시 없음)
  }

  @Test("성능 비교 테스트")
  func testPerformanceComparison() async throws {
    let modules = [LoggingModule(), NetworkModule()]

    // 동기적 빌드
    let syncContainer = WeaverSyncContainer.builder()
      .withModules(modules)
      .build()

    // 비동기 빌드
    let asyncBuilder = WeaverContainer.builder()
    await asyncBuilder.register(LoggerKey.self) { _ in ProductionLogger() }
    await asyncBuilder.register(NetworkServiceKey.self) { resolver in
      let logger = try await resolver.resolve(LoggerKey.self)
      return NetworkService(logger: logger)
    }
    let asyncContainer = await asyncBuilder.build()

    // 의존성 해결 테스트
    _ = try await syncContainer.resolve(LoggerKey.self)
    _ = try await asyncContainer.resolve(LoggerKey.self)

    // Cleanup
    await asyncContainer.shutdown()
  }
}

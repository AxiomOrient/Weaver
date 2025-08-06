// Weaver/Sources/Weaver/WeaverSyncStartup.swift

import Foundation
import os
#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - ==================== 동기적 DI 컨테이너 ====================
//
// DevPrinciples Article 1, 2에 따라 일관성 있고 품질 높은 DI 시스템을 제공합니다.
// 핵심 설계 원칙:
// 1. 등록은 동기적으로, 생성은 지연적으로 처리
// 2. Thread-safe 동시성 보장
// 3. 명확한 에러 처리와 상태 관리
// 4. 단순하고 예측 가능한 동작

/// 동기적 등록과 지연 생성을 지원하는 DI 컨테이너입니다.
/// DevPrinciples Article 5에 따라 SOLID 원칙을 준수하며 단일 책임을 가집니다.
public final class WeaverSyncContainer: Sendable {

  // MARK: - Thread-Safe Storage

  private let registrations: [AnyDependencyKey: DependencyRegistration]
  private let instanceCache = PlatformAppropriateLock(initialState: [AnyDependencyKey: any Sendable]())
  private let creationTasks = PlatformAppropriateLock(initialState: [AnyDependencyKey: Task<any Sendable, Error>]())

  // MARK: - Initialization

  /// 컨테이너를 등록된 의존성으로 초기화합니다.
  public init(registrations: [AnyDependencyKey: DependencyRegistration]) {
    self.registrations = registrations
    
    #if DEBUG
    // 개발 환경에서 사용 중인 잠금 메커니즘 로깅
    print("🔒 WeaverSyncContainer initialized with: \(instanceCache.lockMechanismInfo)")
    #endif
  }

  /// 빌더 패턴을 통한 컨테이너 생성을 시작합니다.
  public static func builder() -> WeaverSyncBuilder {
    WeaverSyncBuilder()
  }

  // MARK: - Resolution

  /// 캐시된 인스턴스가 있는 경우 즉시 반환합니다.
  public func resolveSync<Key: DependencyKey>(_ keyType: Key.Type) -> Key.Value? {
    let key = AnyDependencyKey(keyType)
    return instanceCache.withLock { cache in
      return cache[key] as? Key.Value
    }
  }

  /// 의존성을 해결하고 필요시 새로 생성합니다.
  /// DevPrinciples Article 10에 따라 명시적 에러 처리를 제공합니다.
  public func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value {
    let key = AnyDependencyKey(keyType)

    // 캐시된 인스턴스 확인
    if let cached = instanceCache.withLock({ cache in
      return cache[key]
    }) as? Key.Value {
      return cached
    }

    // 진행 중인 생성 작업 확인
    let existingTask = creationTasks.withLock { tasks in
      return tasks[key]
    }

    if let task = existingTask {
      let instance = try await task.value
      guard let typedInstance = instance as? Key.Value else {
        throw WeaverError.resolutionFailed(
          .typeMismatch(
            expected: "\(Key.Value.self)",
            actual: "\(type(of: instance))",
            keyName: key.description
          ))
      }
      return typedInstance
    }

    // 새로운 인스턴스 생성
    return try await createInstance(key: key, keyType: keyType)
  }

  /// 안전한 의존성 해결 - 실패시 기본값을 반환합니다.
  public func safeResolve<Key: DependencyKey>(_ keyType: Key.Type) async -> Key.Value {
    do {
      return try await resolve(keyType)
    } catch {
      return Key.defaultValue
    }
  }

  // MARK: - Private Implementation

  private func createInstance<Key: DependencyKey>(
    key: AnyDependencyKey,
    keyType: Key.Type
  ) async throws -> Key.Value {

    guard let registration = registrations[key] else {
      throw WeaverError.resolutionFailed(.keyNotFound(keyName: key.description))
    }

    // 생성 작업 등록
    let creationTask = Task<any Sendable, Error> {
      let instance = try await registration.factory(self)

      // 캐시에 저장 (scope에 따라)
      switch registration.scope {
      case .container, .cached:
        instanceCache.withLock { cache in
          cache[key] = instance
        }
      case .weak:
        // 약한 참조는 별도 처리 필요
        break
      default:
        break
      }

      return instance
    }

    // 진행 중인 작업으로 등록
    creationTasks.withLock { tasks in
      tasks[key] = creationTask
    }

    do {
      let instance = try await creationTask.value

      // 완료된 작업 제거
      creationTasks.withLock { tasks in
        _ = tasks.removeValue(forKey: key)
      }

      guard let typedInstance = instance as? Key.Value else {
        throw WeaverError.resolutionFailed(
          .typeMismatch(
            expected: "\(Key.Value.self)",
            actual: "\(type(of: instance))",
            keyName: key.description
          ))
      }

      return typedInstance

    } catch {
      // 실패한 작업 제거
      creationTasks.withLock { tasks in
        _ = tasks.removeValue(forKey: key)
      }
      throw error
    }
  }
}

// MARK: - ==================== 동기적 빌더 ====================

/// 🚀 Swift 6 방식: 동기적 빌더 (최적화된 동시성 안전)
/// DevPrinciples Article 5에 따라 빌더 패턴을 통한 명확한 API를 제공합니다.
public final class WeaverSyncBuilder: Sendable {
  private let registrations: PlatformAppropriateLock<[AnyDependencyKey: DependencyRegistration]>

  public init() {
    self.registrations = PlatformAppropriateLock(initialState: [:])
  }

  /// 의존성을 등록합니다. 팩토리는 저장되며 실제 생성은 지연됩니다.
  @discardableResult
  public func register<Key: DependencyKey>(
    _ keyType: Key.Type,
    scope: Scope = .container,
    timing: InitializationTiming = .onDemand,
    factory: @escaping @Sendable (any Resolver) async throws -> Key.Value
  ) -> Self {

    let key = AnyDependencyKey(keyType)
    let registration = DependencyRegistration(
      scope: scope,
      timing: timing,
      factory: { resolver in try await factory(resolver) },
      keyName: String(describing: keyType)
    )

    registrations.withLock { regs in
      regs[key] = registration
    }

    return self
  }

  /// 약한 참조 등록
  @discardableResult
  public func registerWeak<Key: DependencyKey>(
    _ keyType: Key.Type,
    timing: InitializationTiming = .onDemand,
    factory: @escaping @Sendable (any Resolver) async throws -> Key.Value
  ) -> Self where Key.Value: AnyObject {

    return register(keyType, scope: .weak, timing: timing, factory: factory)
  }

  /// 모듈들을 등록합니다.
  @discardableResult
  public func withModules(_ modules: [SyncModule]) -> Self {
    for module in modules {
      module.configure(self)
    }
    return self
  }

  /// 등록된 의존성으로 컨테이너를 빌드합니다.
  public func build() -> WeaverSyncContainer {
    let finalRegistrations = registrations.withLock { $0 }
    return WeaverSyncContainer(registrations: finalRegistrations)
  }
}

// MARK: - ==================== 동기적 모듈 ====================

/// 의존성 등록을 위한 모듈 프로토콜입니다.
public protocol SyncModule: Sendable {
  /// 빌더에 의존성을 등록합니다.
  func configure(_ builder: WeaverSyncBuilder)
}

// MARK: - ==================== Resolver 구현 ====================

extension WeaverSyncContainer: Resolver {
  // Resolver 프로토콜 구현은 이미 위에서 제공됨
}

// MARK: - ==================== 편의 헬퍼 ====================

/// 동기적 DI 컨테이너 생성을 위한 편의 헬퍼입니다.
/// DevPrinciples Article 3에 따라 단순하고 명확한 API를 제공합니다.
public struct WeaverRealistic {

  /// 모듈들로부터 컨테이너를 생성합니다.
  /// - Parameter modules: 등록할 모듈 배열
  /// - Returns: 생성된 동기 컨테이너
  public static func createContainer(modules: [SyncModule]) -> WeaverSyncContainer {
    return WeaverSyncContainer.builder()
      .withModules(modules)
      .build()
  }

  /// Eager 타이밍 서비스들을 백그라운드에서 초기화합니다.
  /// - Parameter container: 초기화할 컨테이너
  public static func initializeEagerServices(_ container: WeaverSyncContainer) async {
    await Weaver.setGlobalKernel(SyncKernel(container: container))
    
    // Eager 서비스들 초기화 (예시)
    _ = await container.safeResolve(LoggerKey.self)
  }
}

// MARK: - ==================== 사용 예시 ====================

/// 동기적 모듈 예시
public struct LoggingModule: SyncModule {
  public init() {}

  public func configure(_ builder: WeaverSyncBuilder) {
    builder.register(LoggerKey.self, scope: .container, timing: .eager) { _ in
      ProductionLogger()
    }
  }
}

public struct NetworkModule: SyncModule {
  public init() {}

  public func configure(_ builder: WeaverSyncBuilder) {
    builder.register(NetworkServiceKey.self, scope: .container, timing: .background) { resolver in
      let logger = try await resolver.resolve(LoggerKey.self)
      return NetworkService(logger: logger)
    }
  }
}

// MARK: - ==================== 예시 서비스 구현 ====================

/// 예시 로거 서비스
public final class ProductionLogger: Sendable {
    public init() {}
    
    public func info(_ message: String) async {
        print("ℹ️ \(message)")
    }
    
    public func error(_ message: String) async {
        print("❌ \(message)")
    }
}

/// 예시 네트워크 서비스
public final class NetworkService: Sendable {
    private let logger: ProductionLogger
    
    public init(logger: ProductionLogger) {
        self.logger = logger
    }
    
    public func fetchData() async throws -> String {
        await logger.info("네트워크 요청 시작")
        // 실제 네트워크 로직
        return "데이터"
    }
}

/// 예시 의존성 키들
public struct LoggerKey: DependencyKey {
    public typealias Value = ProductionLogger
    public static var defaultValue: ProductionLogger { ProductionLogger() }
}

public struct NetworkServiceKey: DependencyKey {
    public typealias Value = NetworkService
    public static var defaultValue: NetworkService { 
        NetworkService(logger: ProductionLogger()) 
    }
}

/// 앱 시작을 위한 패턴을 제공합니다.
public struct RealisticAppStartup {

  /// 동기적 컨테이너 설정을 수행합니다.
  public static func setupSync() -> WeaverSyncContainer {
    return WeaverSyncContainer.builder()
      .withModules([
        LoggingModule(),
        NetworkModule(),
      ])
      .build()
  }

  /// Eager 서비스들을 백그라운드에서 초기화합니다.
  public static func initializeEagerServices(_ container: WeaverSyncContainer) async {
    Task.detached {
      _ = await container.safeResolve(LoggerKey.self)
    }
  }
}

// MARK: - ==================== 사용 예시 ====================

// MARK: - ==================== 사용 예시 ====================

/// 현실적 해결책을 사용하는 앱 예시입니다.
/// 이제 단일 커널을 통해 더 간단하게 구현할 수 있습니다.
/*
struct MyRealisticApp: App {
  init() {
    Task {
      _ = await Weaver.setupRealistic(modules: [
        LoggingModule(),
        NetworkModule(),
      ])
    }
  }

  var body: some Scene {
    WindowGroup {
      Text("Hello, World!")
    }
  }
}
*/

/// 동기 컨테이너를 위한 커널 래퍼입니다.
public actor SyncKernel: WeaverKernelProtocol {
  private let container: WeaverSyncContainer

  public let stateStream: AsyncStream<LifecycleState>
  private let stateContinuation: AsyncStream<LifecycleState>.Continuation

  public var currentState: LifecycleState {
    get async { .ready(container) }
  }

  public init(container: WeaverSyncContainer) {
    self.container = container

    var continuation: AsyncStream<LifecycleState>.Continuation!
    self.stateStream = AsyncStream { continuation = $0 }
    self.stateContinuation = continuation

    self.stateContinuation.yield(.ready(container))
  }

  public func build() async {}

  public func shutdown() async {
    stateContinuation.yield(.shutdown)
    stateContinuation.finish()
  }

  public func safeResolve<Key: DependencyKey>(_ keyType: Key.Type) async -> Key.Value {
    await container.safeResolve(keyType)
  }

  public func waitForReady(timeout: TimeInterval?) async throws -> any Resolver {
    return container
  }

  public func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value {
    return try await container.resolve(keyType)
  }
}

// MARK: - ==================== 성능 비교 ====================

/// 동기 vs 비동기 컨테이너 성능 비교를 위한 예시입니다.
public struct PerformanceComparison {

  /// 비동기 컨테이너 빌드 방식
  public static func asyncWay() async {
    let builder = WeaverContainer.builder()
    _ = await builder.build()
  }

  /// 동기 컨테이너 빌드 방식
  public static func syncWay() {
    let container = WeaverSyncContainer.builder()
      .withModules([LoggingModule()])
      .build()

    Task {
      _ = await container.safeResolve(LoggerKey.self)
    }
  }
}

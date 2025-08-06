// Weaver/Sources/Weaver/WeaverBuilder.swift

import Foundation

/// `WeaverContainer`의 내부 동작을 제어하는 설정 구조체입니다.
public struct ContainerConfiguration: Sendable {
  var cachePolicy: CachePolicy = .default
}

/// `WeaverContainer`를 생성하기 위한 빌더 액터(Actor)입니다.
/// 플루언트(fluent) 인터페이스를 통해 컨테이너의 설정을 체이닝 방식으로 구성할 수 있습니다.
public actor WeaverBuilder {

  // MARK: - Properties

  private var registrations: [AnyDependencyKey: DependencyRegistration] = [:]
  private var modules: [Module] = []
  internal var configuration = ContainerConfiguration()
  private var parent: WeaverContainer?
  private var logger: WeaverLogger = DefaultLogger()
  private var cacheManagerFactory: (@Sendable (CachePolicy, WeaverLogger) -> CacheManaging)?
  private var metricsCollectorFactory: (@Sendable () -> MetricsCollecting)?

  // MARK: - Initialization

  public init() {}

  // MARK: - Configuration

  /// 의존성을 컨테이너에 등록합니다.
  /// - Parameters:
  ///   - keyType: 등록할 의존성의 키 타입
  ///   - scope: 인스턴스 생명주기 관리 방식 (기본값: .container)
  ///   - timing: 초기화 시점 (기본값: .onDemand)
  ///   - dependencies: 의존성 그래프 분석용 (선택적)
  ///   - factory: 인스턴스 생성 클로저
  @discardableResult
  public func register<Key: DependencyKey>(
    _ keyType: Key.Type,
    scope: Scope = .container,
    timing: InitializationTiming = .onDemand,
    dependencies: [String] = [],
    factory: @escaping @Sendable (Resolver) async throws -> Key.Value
  ) -> Self {
    // `.weak` 스코프는 타입 안정성을 위해 전용 메서드 사용 강제
    precondition(
      scope != .weak, "For .weak scope, please use the type-safe 'registerWeak()' method.")

    let key = AnyDependencyKey(keyType)
    if registrations[key] != nil {
      Task {
        await logger.log(
          message: "경고: '\(key.description)' 키에 대한 의존성이 중복 등록되어 기존 내용을 덮어씁니다.", level: .debug)
      }
    }
    registrations[key] = DependencyRegistration(
      scope: scope,
      timing: timing,
      factory: { resolver in try await factory(resolver) },
      keyName: String(describing: keyType),
      dependencies: dependencies
    )
    return self
  }

  /// 약한 참조(weak reference) 스코프 의존성을 등록합니다.
  ///
  /// 이 메서드는 제네릭 제약(`Key.Value: AnyObject`)을 통해 오직 클래스 타입의 의존성만 등록할 수 있도록
  /// 컴파일 시점에 보장하여, 런타임 오류 가능성을 원천적으로 차단합니다.
  ///
  /// - Parameters:
  ///   - keyType: 등록할 의존성의 `DependencyKey` 타입. `Value`는 반드시 클래스여야 합니다.
  ///   - timing: 초기화 시점 (기본값: .onDemand)
  ///   - dependencies: 의존성 그래프 분석을 위한 의존성 이름 목록.
  ///   - factory: 의존성 인스턴스를 생성하는 클로저.
  /// - Returns: 체이닝을 위해 빌더 자신(`Self`)을 반환합니다.
  @discardableResult
  public func registerWeak<Key: DependencyKey>(
    _ keyType: Key.Type,
    timing: InitializationTiming = .onDemand,
    dependencies: [String] = [],
    factory: @escaping @Sendable (Resolver) async throws -> Key.Value
  ) -> Self where Key.Value: AnyObject {  // ✨ 컴파일 타임에 클래스 타입 제약 강제
    let key = AnyDependencyKey(keyType)
    if registrations[key] != nil {
      Task {
        await logger.log(
          message: "경고: '\(key.description)' 키에 대한 의존성이 중복 등록되어 기존 내용을 덮어씁니다.", level: .debug)
      }
    }
    registrations[key] = DependencyRegistration(
      scope: .weak,  // 스코프를 .weak로 고정
      timing: timing,
      factory: { resolver in try await factory(resolver) },
      keyName: String(describing: keyType),
      dependencies: dependencies
    )
    return self
  }

  /// 의존성 등록 로직을 담고 있는 모듈들을 추가합니다.
  @discardableResult
  public func withModules(_ modules: [Module]) -> Self {
    self.modules = modules
    return self
  }

  /// 부모 컨테이너를 설정합니다.
  @discardableResult
  public func withParent(_ container: WeaverContainer) -> Self {
    self.parent = container
    return self
  }

  /// 로거를 커스텀 구현체로 교체합니다.
  @discardableResult
  public func withLogger(_ logger: WeaverLogger) -> Self {
    self.logger = logger
    return self
  }

  @discardableResult
  internal func setCacheManagerFactory(
    _ factory: @escaping @Sendable (CachePolicy, WeaverLogger) -> CacheManaging
  ) -> Self {
    self.cacheManagerFactory = factory
    return self
  }

  @discardableResult
  internal func setMetricsCollectorFactory(_ factory: @escaping @Sendable () -> MetricsCollecting)
    -> Self
  {
    self.metricsCollectorFactory = factory
    return self
  }

  /// 기존에 등록된 의존성을 테스트 등을 위해 다른 구현으로 강제 교체(override)합니다.
  ///
  /// 만약 오버라이드하려는 키가 등록되어 있지 않은 경우, 경고 로그를 남기고 새롭게 등록합니다.
  /// 이를 통해 테스트 환경에서 예기치 않은 동작을 방지할 수 있습니다.
  /// - Parameters:
  ///   - keyType: 교체할 의존성의 `DependencyKey` 타입.
  ///   - scope: 교체될 의존성의 스코프. 기본값은 `.container`.
  ///   - factory: 교체할 의존성을 생성하는 클로저.
  /// - Returns: 체이닝을 위해 빌더 자신(`Self`)을 반환합니다.
  @discardableResult
  public func override<Key: DependencyKey>(
    _ keyType: Key.Type,
    scope: Scope = .container,
    factory: @escaping @Sendable (Resolver) async throws -> Key.Value
  ) -> Self {
    let key = AnyDependencyKey(keyType)
    if registrations[key] == nil {
      Task {
        await logger.log(
          message: "⚠️ 경고: '\(key.description)' 키는 등록되지 않았지만 오버라이드 되었습니다. 테스트 설정을 확인하세요.",
          level: .debug
        )
      }
    }

    // 기존 등록 정보를 덮어씁니다.
    registrations[key] = DependencyRegistration(
      scope: scope,
      factory: { resolver in try await factory(resolver) },
      keyName: String(describing: keyType),
      dependencies: []  // 오버라이드는 의존성 분석에서 제외될 수 있으므로 비워둡니다.
    )
    return self
  }

  // MARK: - Build

  /// 설정된 내용들을 바탕으로 `WeaverContainer` 인스턴스를 생성합니다.
  /// - Returns: 설정이 완료된 새로운 `WeaverContainer` 인스턴스.
  public func build() async -> WeaverContainer {
    await build(onAppServiceProgress: { _ in })
  }
  
  /// 🔧 [NEW] 등록된 의존성 정보를 반환합니다 (검증용)
  internal func getRegistrations() async -> [AnyDependencyKey: DependencyRegistration] {
    // 모듈 설정을 먼저 적용
    for module in modules {
      await module.configure(self)
    }
    return registrations
  }

  /// 앱 서비스 초기화 진행률 콜백을 지원하는 `build` 메서드입니다.
  /// `WeaverKernel`에서 이 메서드를 호출하여 컨테이너 초기화 진행 상태를 외부에 알립니다.
  /// - Parameter onAppServiceProgress: 앱 서비스 초기화 진행률(0.0 ~ 1.0)을 전달받는 비동기 클로저.
  /// - Returns: 설정이 완료된 새로운 `WeaverContainer` 인스턴스.
  public func build(onAppServiceProgress: @escaping @Sendable (Double) async -> Void) async
    -> WeaverContainer
  {
    // 1. 모듈 설정을 먼저 적용합니다.
    for module in modules {
      await module.configure(self)
    }

    let cacheManager: CacheManaging =
      cacheManagerFactory?(configuration.cachePolicy, logger) ?? DummyCacheManager()
    let metricsCollector: MetricsCollecting = metricsCollectorFactory?() ?? DummyMetricsCollector()

    // 2. 모든 설정으로 컨테이너 인스턴스를 생성합니다.
    let container = WeaverContainer(
      registrations: registrations,
      parent: parent,
      logger: logger,
      cacheManager: cacheManager,
      metricsCollector: metricsCollector
    )

    // 3. 앱 서비스들을 진행률 콜백과 함께 초기화합니다.
    await container.initializeAppServiceDependencies(onProgress: onAppServiceProgress)

    // 4. 모든 준비가 완료된 컨테이너를 반환합니다.
    return container
  }
}

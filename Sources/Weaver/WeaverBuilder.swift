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
  private var priorityProvider: ServicePriorityProvider = DefaultServicePriorityProvider()

  // MARK: - Initialization

  public init() {}

  // MARK: - Configuration

  /// 의존성을 컨테이너에 등록합니다.
  /// - Parameters:
  ///   - keyType: 등록할 의존성의 키 타입
  ///   - scope: 인스턴스 생명주기 관리 방식 (기본값: .shared)
  ///   - dependencies: 의존성 그래프 분석용 (선택적) - 타입 안전한 DependencyKey 타입들
  ///   - explicitDependencies: 빌드 타임 순환 참조 감지를 위한 명시적 의존성 키들
  ///   - factory: 인스턴스 생성 클로저
  @discardableResult
  public func register<Key: DependencyKey>(
    _ keyType: Key.Type,
    scope: Scope = .shared,
    dependencies: [any DependencyKey.Type] = [],
    explicitDependencies: [any DependencyKey.Type] = [],
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
    
    // 명시적 의존성을 AnyDependencyKey로 변환
    let explicitDeps = explicitDependencies.isEmpty ? nil : Set(explicitDependencies.map { AnyDependencyKey($0) })
    
    registrations[key] = DependencyRegistration(
      scope: scope,
      factory: { resolver in try await factory(resolver) },
      keyName: String(describing: keyType),
      dependencies: dependencies,
      explicitDependencies: explicitDeps
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
  ///   - dependencies: 의존성 그래프 분석을 위한 타입 안전한 DependencyKey 타입들.
  ///   - explicitDependencies: 빌드 타임 순환 참조 감지를 위한 명시적 의존성 키들
  ///   - factory: 의존성 인스턴스를 생성하는 클로저.
  /// - Returns: 체이닝을 위해 빌더 자신(`Self`)을 반환합니다.
  @discardableResult
  public func registerWeak<Key: DependencyKey>(
    _ keyType: Key.Type,
    dependencies: [any DependencyKey.Type] = [],
    explicitDependencies: [any DependencyKey.Type] = [],
    factory: @escaping @Sendable (Resolver) async throws -> Key.Value
  ) -> Self where Key.Value: AnyObject {  // ✨ 컴파일 타임에 클래스 타입 제약 강제
    let key = AnyDependencyKey(keyType)
    if registrations[key] != nil {
      Task {
        await logger.log(
          message: "경고: '\(key.description)' 키에 대한 의존성이 중복 등록되어 기존 내용을 덮어씁니다.", level: .debug)
      }
    }
    
    // 명시적 의존성을 AnyDependencyKey로 변환
    let explicitDeps = explicitDependencies.isEmpty ? nil : Set(explicitDependencies.map { AnyDependencyKey($0) })
    
    registrations[key] = DependencyRegistration(
      scope: .weak,  // 스코프를 .weak로 고정
      factory: { resolver in try await factory(resolver) },
      keyName: String(describing: keyType),
      dependencies: dependencies,
      explicitDependencies: explicitDeps
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
  
  /// 서비스 초기화 우선순위 제공자를 설정합니다.
  /// 복잡한 앱에서 특별한 초기화 순서가 필요한 경우 사용합니다.
  @discardableResult
  public func withPriorityProvider(_ provider: ServicePriorityProvider) -> Self {
    self.priorityProvider = provider
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
  ///   - scope: 교체될 의존성의 스코프. 기본값은 `.shared`.
  ///   - factory: 교체할 의존성을 생성하는 클로저.
  /// - Returns: 체이닝을 위해 빌더 자신(`Self`)을 반환합니다.
  @discardableResult
  public func override<Key: DependencyKey>(
    _ keyType: Key.Type,
    scope: Scope = .shared,
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

  // MARK: - 편의 API (Convenience API)
  
  /// 타입 기반 편의 등록 메서드 - DependencyKey 없이 타입만으로 등록
  /// 
  /// 기존 DependencyKey 방식의 안전성을 해치지 않으면서 간단한 의존성에 대해 편의성을 제공합니다.
  /// 내부적으로는 TypeBasedDependencyKey를 사용하여 관리합니다.
  ///
  /// - Parameters:
  ///   - type: 등록할 타입
  ///   - scope: 인스턴스 생명주기 관리 방식 (기본값: .shared)
  ///   - defaultValue: 의존성 해결 실패 시 사용할 안전한 기본값 (필수)
  ///   - factory: 인스턴스 생성 클로저
  /// - Returns: 체이닝을 위해 빌더 자신(`Self`)을 반환합니다.
  @discardableResult
  public func registerType<T: Sendable>(
    _ type: T.Type,
    scope: Scope = .shared,
    defaultValue: T,
    factory: @escaping @Sendable (Resolver) async throws -> T
  ) -> Self {
    // 타입 기반 키 생성
    let key = AnyDependencyKey(TypeBasedDependencyKey<T>.self)
    
    // directDefaultValue를 포함한 등록 정보 생성
    registrations[key] = DependencyRegistration(
      scope: scope,
      factory: { resolver in try await factory(resolver) },
      keyName: String(describing: type),
      dependencies: [],
      directDefaultValue: defaultValue  // 안전한 기본값 저장
    )
    
    return self
  }
  
  /// 약한 참조 타입 기반 편의 등록 메서드
  @discardableResult
  public func registerTypeWeak<T: Sendable & AnyObject>(
    _ type: T.Type,
    defaultValue: T,
    factory: @escaping @Sendable (Resolver) async throws -> T
  ) -> Self {
    let key = AnyDependencyKey(TypeBasedDependencyKey<T>.self)
    
    registrations[key] = DependencyRegistration(
      scope: .weak,
      factory: { resolver in try await factory(resolver) },
      keyName: String(describing: type),
      dependencies: [],
      directDefaultValue: defaultValue  // 안전한 기본값 저장
    )
    
    return self
  }

  // MARK: - Build

  /// 설정된 내용들을 바탕으로 `WeaverContainer` 인스턴스를 생성합니다.
  /// 빌드 타임에 의존성 그래프를 검증하여 순환 참조와 누락된 의존성을 감지합니다.
  /// - Returns: 설정이 완료된 새로운 `WeaverContainer` 인스턴스.
  /// - Throws: DependencySetupError - 의존성 그래프에 문제가 있는 경우
  public func build() async throws -> WeaverContainer {
    try await build(onAppServiceProgress: { _ in })
  }
  
  /// 🔧 [NEW] 등록된 의존성 정보를 반환합니다 (검증용)
  internal func getRegistrations() async -> [AnyDependencyKey: DependencyRegistration] {
    // 모듈 설정을 먼저 적용
    for module in modules {
      await module.configure(self)
    }
    return registrations
  }
  
  /// 등록 정보를 직접 설정합니다 (스코프 기반 커널 내부 사용).
  @discardableResult
  internal func withRegistrations(_ newRegistrations: [AnyDependencyKey: DependencyRegistration]) -> Self {
    for (key, registration) in newRegistrations {
      registrations[key] = registration
    }
    return self
  }

  /// 앱 서비스 초기화 진행률 콜백을 지원하는 `build` 메서드입니다.
  /// `WeaverKernel`에서 이 메서드를 호출하여 컨테이너 초기화 진행 상태를 외부에 알립니다.
  /// 빌드 타임에 의존성 그래프를 검증하여 순환 참조와 누락된 의존성을 감지합니다.
  /// - Parameter onAppServiceProgress: 앱 서비스 초기화 진행률(0.0 ~ 1.0)을 전달받는 비동기 클로저.
  /// - Returns: 설정이 완료된 새로운 `WeaverContainer` 인스턴스.
  /// - Throws: DependencySetupError - 의존성 그래프에 문제가 있는 경우
  public func build(onAppServiceProgress: @escaping @Sendable (Double) async -> Void) async throws
    -> WeaverContainer
  {
    // 1. 모듈 설정을 먼저 적용합니다.
    for module in modules {
      await module.configure(self)
    }

    // 2. 🔧 [NEW] 빌드 타임 의존성 그래프 검증
    try await validateDependencyGraph()

    let cacheManager: CacheManaging =
      cacheManagerFactory?(configuration.cachePolicy, logger) ?? DummyCacheManager()
    let metricsCollector: MetricsCollecting = metricsCollectorFactory?() ?? DummyMetricsCollector()

    // 3. 모든 설정으로 컨테이너 인스턴스를 생성합니다.
    let container = WeaverContainer(
      registrations: registrations,
      parent: parent,
      logger: logger,
      cacheManager: cacheManager,
      metricsCollector: metricsCollector
    )

    // 4. 앱 서비스들을 진행률 콜백과 함께 초기화합니다.
    await container.initializeAppServiceDependencies(onProgress: onAppServiceProgress)

    // 5. 모든 준비가 완료된 컨테이너를 반환합니다.
    return container
  }
  
  // MARK: - 🔧 [NEW] Build-Time Dependency Graph Validation
  
  /// 빌드 타임에 의존성 그래프를 검증합니다.
  /// 순환 참조, 누락된 의존성, 스코프 호환성을 검사하여 런타임 에러를 방지합니다.
  private func validateDependencyGraph() async throws {
    await logger.log(message: "🔍 빌드 타임 의존성 그래프 검증 시작", level: .debug)
    
    let dependencyGraph = DependencyGraph(registrations: registrations)
    let validation = dependencyGraph.validate()
    
    switch validation {
    case .valid:
      await logger.log(message: "✅ 의존성 그래프 검증 완료 - 문제 없음", level: .debug)
      
      // 개발 환경에서는 DOT 그래프 생성
      if WeaverEnvironment.isDevelopment {
        let dotGraph = dependencyGraph.generateDotGraph()
        await logger.log(
          message: "📊 의존성 그래프 (DOT 형식):\n\(dotGraph)",
          level: .debug
        )
      }
      
    case .circular(let cyclePath):
      let error = DependencySetupError.circularDependency(cyclePath)
      await logger.log(
        message: "🚨 순환 참조 감지: \(cyclePath.joined(separator: " → "))",
        level: .error
      )
      throw error
      
    case .missing(let missingDeps):
      let error = DependencySetupError.missingDependencies(missingDeps)
      await logger.log(
        message: "🚨 누락된 의존성 감지: \(missingDeps.joined(separator: ", "))",
        level: .error
      )
      throw error
      
    case .invalid(let key, let underlyingError):
      let error = DependencySetupError.invalidConfiguration(key, underlyingError)
      await logger.log(
        message: "🚨 잘못된 의존성 설정: \(key) - \(underlyingError.localizedDescription)",
        level: .error
      )
      throw error
    }
  }
  
  /// 의존성 추적을 위한 편의 메서드들
  /// 개발자가 명시적으로 의존성을 선언할 수 있도록 지원합니다.
  
  /// 의존성 관계를 명시적으로 선언하는 편의 메서드
  @discardableResult
  public func declareDependency<Consumer: DependencyKey, Provider: DependencyKey>(
    _ consumer: Consumer.Type,
    dependsOn provider: Provider.Type
  ) -> Self {
    let consumerKey = AnyDependencyKey(consumer)
    
    // 기존 등록 정보가 있으면 의존성 추가
    if let registration = registrations[consumerKey] {
      var explicitDeps = registration.explicitDependencies ?? Set<AnyDependencyKey>()
      explicitDeps.insert(AnyDependencyKey(provider))
      
      // 새로운 등록 정보로 교체 (explicitDependencies 업데이트)
      registrations[consumerKey] = DependencyRegistration(
        scope: registration.scope,
        factory: registration.factory,
        keyName: registration.keyName,
        dependencies: registration.dependencies,
        explicitDependencies: explicitDeps
      )
    }
    
    return self
  }
  
  /// 여러 의존성을 한 번에 선언하는 편의 메서드
  @discardableResult
  public func declareDependencies<Consumer: DependencyKey>(
    _ consumer: Consumer.Type,
    dependsOn providers: [any DependencyKey.Type]
  ) -> Self {
    for provider in providers {
      _ = declareDependency(consumer, dependsOn: provider)
    }
    return self
  }
}

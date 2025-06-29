// WeaverBuilder.swift

import Foundation
import os.log

/// `WeaverContainer`를 생성하기 위한 빌더 액터입니다.
///
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
    ///
    /// 동일한 키에 대해 중복 등록할 경우, 기존 등록 내용을 덮어쓰고 경고 로그를 출력합니다.
    /// - Parameters:
    ///   - keyType: 등록할 의존성의 키 타입 (`DependencyKey.Type`).
    ///   - scope: 의존성의 생명주기를 정의하는 스코프 (`.container`, `.cached`, `.transient`). 기본값은 `.transient`.
    ///   - factory: 의존성 인스턴스를 생성하는 클로저. `Resolver`를 통해 다른 의존성을 주입받을 수 있습니다.
    /// - Returns: 체이닝을 위해 빌더 자신(`Self`)을 반환합니다.
    @discardableResult
    public func register<Key: DependencyKey>(
        _ keyType: Key.Type,
        scope: Scope = .transient,
        factory: @escaping @Sendable (Resolver) async throws -> Key.Value
    ) -> Self {
        let key = AnyDependencyKey(keyType)
        let registration = DependencyRegistration(
            scope: scope,
            factory: { resolver in try await factory(resolver) },
            keyName: String(describing: keyType)
        )
        if registrations[key] != nil {
            Task { await logger.log(message: "⚠️ 경고: '\(key.description)'에 대한 등록을 덮어씁니다.", level: .default) }
        }
        registrations[key] = registration
        return self
    }
    
    /// 의존성 등록 로직을 담고 있는 모듈들을 추가합니다.
    /// - Parameter modules: `Module` 프로토콜을 준수하는 모듈의 배열.
    /// - Returns: 체이닝을 위해 빌더 자신(`Self`)을 반환합니다.
    @discardableResult
    public func withModules(_ modules: [Module]) -> Self {
        self.modules = modules
        return self
    }
    
    /// 부모 컨테이너를 설정합니다.
    ///
    /// 현재 컨테이너에서 의존성을 찾지 못할 경우, 부모 컨테이너에서 찾기를 시도합니다.
    /// - Parameter container: 부모로 설정할 `WeaverContainer` 인스턴스.
    /// - Returns: 체이닝을 위해 빌더 자신(`Self`)을 반환합니다.
    @discardableResult
    public func withParent(_ container: WeaverContainer) -> Self {
        self.parent = container
        return self
    }
    
    /// 로거를 커스텀 구현체로 교체합니다.
    /// - Parameter logger: `WeaverLogger` 프로토콜을 준수하는 로거 인스턴스.
    /// - Returns: 체이닝을 위해 빌더 자신(`Self`)을 반환합니다.
    @discardableResult
    public func withLogger(_ logger: WeaverLogger) -> Self {
        self.logger = logger
        return self
    }
    
    /// 캐시 매니저를 생성하는 팩토리 클로저를 설정합니다.
    ///
    /// 고급 캐싱 기능을 활성화할 때 내부적으로 사용됩니다.
    /// - Parameter factory: `CacheManaging` 인스턴스를 생성하는 클로저.
    /// - Returns: 체이닝을 위해 빌더 자신(`Self`)을 반환합니다.
    @discardableResult
    internal func setCacheManagerFactory(_ factory: @escaping @Sendable (CachePolicy, WeaverLogger) -> CacheManaging) -> Self {
        self.cacheManagerFactory = factory
        return self
    }
    
    /// 메트릭 수집기를 생성하는 팩토리 클로저를 설정합니다.
    ///
    /// 메트릭 수집 기능을 활성화할 때 내부적으로 사용됩니다.
    /// - Parameter factory: `MetricsCollecting` 인스턴스를 생성하는 클로저.
    /// - Returns: 체이닝을 위해 빌더 자신(`Self`)을 반환합니다.
    @discardableResult
    internal func setMetricsCollectorFactory(_ factory: @escaping @Sendable () -> MetricsCollecting) -> Self {
        self.metricsCollectorFactory = factory
        return self
    }
    
    // MARK: - Build
    
    /// 설정된 내용들을 바탕으로 `WeaverContainer` 인스턴스를 생성합니다.
    /// - Returns: 설정이 완료된 새로운 `WeaverContainer` 인스턴스.
    public func build() async -> WeaverContainer {
        for module in modules {
            await module.configure(self)
        }
        
        let cacheManager: CacheManaging = cacheManagerFactory?(configuration.cachePolicy, logger) ?? DummyCacheManager()
        let metricsCollector: MetricsCollecting = metricsCollectorFactory?() ?? DummyMetricsCollector()
        
        return WeaverContainer(
            registrations: registrations,
            parent: parent,
            logger: logger,
            cacheManager: cacheManager,
            metricsCollector: metricsCollector
        )
    }
}

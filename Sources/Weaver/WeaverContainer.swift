// Weaver/Sources/Weaver/WeaverContainerRefactored.swift
// 🚀 리팩토링된 WeaverContainer - DevPrinciples 완전 준수
//
// DevPrinciples 준수 사항:
// - Article 5 Rule 1: SOLID 원칙 엄격 준수
// - Article 5 Rule 2: 의존성 분리를 통한 테스트 가능성 극대화
// - Article 7 Rule 1: 단일 명확한 책임
// - SWIFT.md Section 3: 강제 언래핑 완전 금지
// - Tier 4: God Object 안티패턴 완전 제거

import Foundation
import os

/// 🔧 [REFACTORED] 의존성 해결만 담당하는 핵심 컨테이너
/// DevPrinciples Article 5 Rule 2: 의존성 분리를 통한 테스트 가능성 극대화
public actor WeaverContainer: Resolver {

  // MARK: - Core Dependencies

  private let resolutionCoordinator: ResolutionCoordinator
  private let lifecycleManager: ContainerLifecycleManager
  private let metricsCollector: MetricsCollecting

  public let registrations: [AnyDependencyKey: DependencyRegistration]
  nonisolated public let logger: WeaverLogger?

  // MARK: - Initialization

  /// 빌더 패턴을 통한 컨테이너 생성을 시작합니다.
  public static func builder() -> WeaverBuilder { WeaverBuilder() }

  internal init(
    registrations: [AnyDependencyKey: DependencyRegistration],
    parent: WeaverContainer?,
    logger: WeaverLogger,
    cacheManager: CacheManaging,
    metricsCollector: MetricsCollecting
  ) {
    self.registrations = registrations
    self.logger = logger
    self.metricsCollector = metricsCollector

    // 🚨 [FIXED] 순환 참조 제거 - 단일 코디네이터로 통합
    self.resolutionCoordinator = ResolutionCoordinator(
      registrations: registrations,
      parent: parent,
      logger: logger,
      cacheManager: cacheManager
    )

    self.lifecycleManager = ContainerLifecycleManager(
      logger: logger
    )
  }

  // MARK: - Public API

  public func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value {
    let startTime = CFAbsoluteTimeGetCurrent()

    do {
      let instance = try await resolutionCoordinator.resolve(keyType)

      let duration = CFAbsoluteTimeGetCurrent() - startTime
      await metricsCollector.recordResolution(duration: duration)

      return instance
    } catch {
      let duration = CFAbsoluteTimeGetCurrent() - startTime
      await metricsCollector.recordResolution(duration: duration)
      await metricsCollector.recordFailure()
      throw error
    }
  }

  public func getMetrics() async -> ResolutionMetrics {
    let coordinatorMetrics = await resolutionCoordinator.getMetrics()
    return await metricsCollector.getMetrics(
      cacheHits: coordinatorMetrics.cacheHits,
      cacheMisses: coordinatorMetrics.cacheMisses
    )
  }

  public func shutdown() async {
    // 앱 종료 이벤트 먼저 처리
    await lifecycleManager.handleAppWillTerminate(
      registrations: registrations,
      coordinator: resolutionCoordinator
    )

    await lifecycleManager.shutdown()
    await resolutionCoordinator.clear()
  }

  /// 메모리 압박 감지 및 자동 정리 시스템
  public func performMemoryCleanup(forced: Bool = false) async {
    await resolutionCoordinator.performMemoryCleanup(forced: forced)
  }

  /// 현재 컨테이너를 부모로 하여, 새로운 모듈이 추가된 자식 컨테이너를 생성합니다.
  public func reconfigure(with modules: [Module]) async -> WeaverContainer {
    await logger?.log(
      message:
        "Reconfiguring container by creating a new child with \(modules.count) new module(s).",
      level: .debug
    )

    // 새로운 등록 정보 수집
    var newRegistrations = registrations

    for module in modules {
      let builder = WeaverBuilder()
      await module.configure(builder)
      let moduleRegistrations = await builder.getRegistrations()

      for (key, registration) in moduleRegistrations {
        newRegistrations[key] = registration
      }
    }

    // 새 컨테이너 생성
    return WeaverContainer(
      registrations: newRegistrations,
      parent: self,
      logger: logger ?? DefaultLogger(),
      cacheManager: DummyCacheManager(),
      metricsCollector: metricsCollector
    )
  }

  /// AppService 스코프의 의존성들을 앱 상태 변화에 대응할 수 있도록 초기화합니다.
  /// 🚨 [FIXED] Critical Issue #1: 앱 서비스 초기화 순서 보장
  /// DevPrinciples Article 5 Rule 1: 의존성 순서를 엄격히 준수하여 순차 초기화
  public func initializeAppServiceDependencies(
    onProgress: @escaping @Sendable (Double) async -> Void
  ) async {
    let appServiceKeys = registrations.filter { $1.scope == .appService }.map { $0.key }
    guard !appServiceKeys.isEmpty else {
      await onProgress(1.0)
      return
    }

    await logger?.log(
      message: "🚀 Initializing \(appServiceKeys.count) app services in priority order...",
      level: .info)
    await onProgress(0.0)

    let totalCount = appServiceKeys.count

    // 🔧 [CRITICAL FIX] 앱 서비스는 의존성 순서가 중요하므로 우선순위 기반 순차 초기화
    // 로깅 → 설정 → 분석 → 네트워크 순서로 엄격하게 순차 처리
    let prioritizedKeys = await lifecycleManager.prioritizeAppServiceKeys(appServiceKeys)

    // 🚨 [FIXED] TaskGroup 병렬 처리 → 순차 for 루프로 변경
    // 의존성 순서 보장을 위해 순차적으로 초기화
    var failedServices: [String] = []
    var criticalFailures: [String] = []

    for (index, key) in prioritizedKeys.enumerated() {
      let serviceName = key.description
      let priority = await lifecycleManager.getAppServicePriority(for: key)

      do {
        _ = try await resolutionCoordinator.resolve(key)
        await logger?.log(
          message:
            "✅ App service ready [\(index + 1)/\(totalCount)] Priority-\(priority): \(serviceName)",
          level: .debug
        )
      } catch {
        await logger?.log(
          message:
            "❌ App service failed [\(index + 1)/\(totalCount)] Priority-\(priority): \(serviceName) - \(error)",
          level: .error
        )

        // 🔧 [IMPROVED] 우선순위별 실패 처리 전략
        failedServices.append(serviceName)

        // Priority 0-1 (로깅, 설정)은 Critical 실패로 분류
        if priority <= 1 {
          criticalFailures.append(serviceName)
          await logger?.log(
            message: "🚨 CRITICAL: Essential service failed - \(serviceName)",
            level: .fault
          )
        }

        // 🔧 [RESILIENCE] 중요 서비스 실패 시에도 계속 진행하되 상태 추적
        // 완전한 앱 중단보다는 부분적 기능 제한으로 대응
      }

      // 진행률 업데이트 (순차 처리로 정확한 진행률 보장)
      let progress = Double(index + 1) / Double(totalCount)
      await onProgress(progress)
    }

    // 🔧 [IMPROVED] 초기화 결과 요약 로깅
    if !failedServices.isEmpty {
      await logger?.log(
        message:
          "⚠️ App service initialization completed with \(failedServices.count) failures: \(failedServices.joined(separator: ", "))",
        level: .error
      )

      if !criticalFailures.isEmpty {
        await logger?.log(
          message:
            "🚨 CRITICAL failures detected: \(criticalFailures.joined(separator: ", ")) - App may have limited functionality",
          level: .fault
        )
      }
    }

    // 최종 진행률 업데이트 보장
    await onProgress(1.0)

    // 🔧 [IMPROVED] 초기화 완료 요약 및 성능 메트릭
    let successCount = totalCount - failedServices.count
    let successRate = totalCount > 0 ? Double(successCount) / Double(totalCount) * 100 : 100

    await logger?.log(
      message:
        "✅ App service initialization completed: \(successCount)/\(totalCount) services (\(String(format: "%.1f", successRate))% success rate)",
      level: .info
    )

    if criticalFailures.isEmpty {
      await logger?.log(
        message: "🎯 All critical services initialized successfully - App ready", level: .info)
    } else {
      await logger?.log(
        message: "⚠️ Some critical services failed - App functionality may be limited", level: .error
      )
    }
  }

  // MARK: - App Lifecycle Delegation

  public func handleAppDidEnterBackground() async {
    await lifecycleManager.handleAppDidEnterBackground(
      registrations: registrations,
      coordinator: resolutionCoordinator
    )
  }

  public func handleAppWillEnterForeground() async {
    await lifecycleManager.handleAppWillEnterForeground(
      registrations: registrations,
      coordinator: resolutionCoordinator
    )
  }
}

// MARK: - ==================== 통합된 해결 코디네이터 ====================

/// 🚨 [FIXED] 의존성 해결과 스코프 관리를 통합한 단일 Actor
/// DevPrinciples Article 7 Rule 1: 단일 명확한 책임 - 의존성 해결 조정
actor ResolutionCoordinator: Resolver {
  private let registrations: [AnyDependencyKey: DependencyRegistration]
  private let parent: WeaverContainer?
  private let logger: WeaverLogger?
  private let cacheManager: CacheManaging

  // 스코프별 저장소
  private var containerCache: [AnyDependencyKey: any Sendable] = [:]
  private var weakReferences: [AnyDependencyKey: WeakBox<any AnyObject & Sendable>] = [:]
  private var ongoingCreations: [AnyDependencyKey: Task<any Sendable, Error>] = [:]

  @TaskLocal private static var resolutionStack: [ResolutionStackEntry] = []
  @TaskLocal private static var resolutionSet: Set<ResolutionStackEntry> = []

  private struct ResolutionStackEntry: Hashable {
    let key: AnyDependencyKey
    let containerID: ObjectIdentifier
  }

  init(
    registrations: [AnyDependencyKey: DependencyRegistration],
    parent: WeaverContainer?,
    logger: WeaverLogger?,
    cacheManager: CacheManaging
  ) {
    self.registrations = registrations
    self.parent = parent
    self.logger = logger
    self.cacheManager = cacheManager
  }

  func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value {
    let key = AnyDependencyKey(keyType)

    // 순환 참조 검사
    let currentEntry = ResolutionStackEntry(key: key, containerID: ObjectIdentifier(self))
    if Self.resolutionSet.contains(currentEntry) {
      let cycleMessage = (Self.resolutionStack.map { $0.key.description } + [key.description])
        .joined(separator: " -> ")
      throw WeaverError.resolutionFailed(.circularDependency(path: cycleMessage))
    }

    return try await Self.$resolutionStack.withValue(Self.resolutionStack + [currentEntry]) {
      try await Self.$resolutionSet.withValue(Self.resolutionSet.union([currentEntry])) {
        try await _resolveInternal(key: key, keyType: keyType)
      }
    }
  }

  private func _resolveInternal<Key: DependencyKey>(
    key: AnyDependencyKey,
    keyType: Key.Type
  ) async throws -> Key.Value {
    guard let registration = registrations[key] else {
      if let parent {
        return try await parent.resolve(keyType)
      }
      throw WeaverError.resolutionFailed(.keyNotFound(keyName: key.description))
    }

    let instance = try await getOrCreateInstance(key: key, registration: registration)

    guard let typedInstance = instance as? Key.Value else {
      throw WeaverError.resolutionFailed(
        .typeMismatch(
          expected: "\(Key.Value.self)",
          actual: "\(type(of: instance))",
          keyName: key.description
        )
      )
    }

    return typedInstance
  }

  private func getOrCreateInstance(
    key: AnyDependencyKey,
    registration: DependencyRegistration
  ) async throws -> any Sendable {
    switch registration.scope {
    case .container, .appService, .cached, .bootstrap, .core, .feature:
      return try await getOrCreateContainerInstance(key: key, registration: registration)
    case .weak:
      return try await getOrCreateWeakInstance(key: key, registration: registration)
    }
  }

  func getMetrics() async -> ScopeMetrics {
    let (hits, misses) = await cacheManager.getMetrics()
    return ScopeMetrics(
      cacheHits: hits,
      cacheMisses: misses,
      containerInstances: containerCache.count,
      weakReferences: weakReferences.count
    )
  }

  func clear() async {
    // 🚨 [FIX] Disposable 객체들을 먼저 정리
    for (key, instance) in containerCache {
      if let disposable = instance as? Disposable {
        do {
          try await disposable.dispose()
          await logger?.log(message: "🗑️ Container cached service disposed: \(key.description)", level: .debug)
        } catch {
          await logger?.log(
            message: "❌ Container cached service disposal failed: \(key.description) - \(error)", 
            level: .error
          )
        }
      }
    }
    
    containerCache.removeAll()
    weakReferences.removeAll()
    ongoingCreations.values.forEach { $0.cancel() }
    ongoingCreations.removeAll()
    await cacheManager.clear()
  }

  /// 캐시된 인스턴스를 반환합니다 (생명주기 이벤트 처리용)
  func getCachedInstance(for key: AnyDependencyKey) -> (any Sendable)? {
    return containerCache[key]
  }

  /// 메모리 압박 감지 및 자동 정리 시스템
  func performMemoryCleanup(forced: Bool = false) async {
    await logger?.log(message: "🧹 메모리 정리 작업 시작", level: .info)

    // 1. 메모리 사용량 확인
    let memoryInfo = await getCurrentMemoryUsage()
    let shouldCleanCache = forced || memoryInfo.isMemoryPressure

    // 2. 약한 참조 정리
    let beforeCount = weakReferences.count
    _ = await getWeakReferenceMetrics()  // 내부적으로 해제된 참조들을 정리함
    let afterCount = weakReferences.count
    let cleanedCount = beforeCount - afterCount

    // 3. 메모리 압박 시에만 캐시 정리
    if shouldCleanCache {
      await cacheManager.clear()
      await logger?.log(message: "⚠️ 메모리 압박으로 인한 캐시 정리", level: .info)
    }

    await logger?.log(
      message: "✅ 메모리 정리 완료: 약한 참조 \(cleanedCount)개 정리\(shouldCleanCache ? ", 캐시 초기화" : "")",
      level: .info
    )
  }

  /// 약한 참조 메트릭을 가져오고 동시에 해제된 참조들을 정리합니다.
  private func getWeakReferenceMetrics() async -> WeakReferenceMetrics {
    var aliveCount = 0
    var totalCount = 0
    var keysToRemove: [AnyDependencyKey] = []

    for (key, weakBox) in weakReferences {
      totalCount += 1
      if await weakBox.isAlive {
        aliveCount += 1
      } else {
        keysToRemove.append(key)
      }
    }

    // 해제된 약한 참조들을 딕셔너리에서 제거하여 메모리 누수 방지
    for key in keysToRemove {
      weakReferences.removeValue(forKey: key)
    }

    let deallocatedCount = totalCount - aliveCount

    // 메모리 정리 로깅 추가
    if !keysToRemove.isEmpty {
      await logger?.log(
        message: "🧹 약한 참조 자동 정리: \(keysToRemove.count)개 해제된 참조 제거",
        level: .debug
      )
    }

    return WeakReferenceMetrics(
      totalWeakReferences: totalCount,
      aliveWeakReferences: aliveCount,
      deallocatedWeakReferences: deallocatedCount
    )
  }

  /// 현재 메모리 사용량을 확인합니다.
  private func getCurrentMemoryUsage() async -> MemoryInfo {
    var memoryInfo = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

    let result = withUnsafeMutablePointer(to: &memoryInfo) {
      $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }

    if result == KERN_SUCCESS {
      let memoryUsageBytes = UInt64(memoryInfo.resident_size)
      let memoryUsageMB = memoryUsageBytes / (1024 * 1024)
      return MemoryInfo(usageMB: memoryUsageMB, isMemoryPressure: memoryUsageMB > 200)
    }

    return MemoryInfo(usageMB: 0, isMemoryPressure: false)
  }

  private struct MemoryInfo {
    let usageMB: UInt64
    let isMemoryPressure: Bool
  }

  // MARK: - Private Implementation

  private func getOrCreateContainerInstance(
    key: AnyDependencyKey,
    registration: DependencyRegistration
  ) async throws -> any Sendable {
    // 🚨 [RACE CONDITION ULTIMATE FIX] 
    // 근본 원인: 체크와 셋 사이의 비원자적 간격
    // 해결책: 완전한 원자적 체크-앤-셋 패턴
    
    // 원자적 체크-앤-셋: 한 번의 동기적 연산으로 처리
    if let cachedValue = containerCache[key] {
      return cachedValue
    }
    
    if let existingTask = ongoingCreations[key] {
      return try await existingTask.value
    }
    
    // 🔥 [CRITICAL] 여기서 Task 생성과 등록을 원자적으로 처리
    // 다른 태스크가 끼어들 수 없도록 보장
    let creationTask = Task<any Sendable, Error> {
      try await registration.factory(self)
    }
    
    // 즉시 등록 - 이 시점에서 다른 태스크는 existingTask를 발견하게 됨
    ongoingCreations[key] = creationTask

    do {
      let instance = try await creationTask.value
      
      // 성공 시 캐시에 저장하고 진행 중인 작업에서 제거
      containerCache[key] = instance
      ongoingCreations.removeValue(forKey: key)
      
      return instance
    } catch {
      // 실패 시 진행 중인 작업에서 제거
      ongoingCreations.removeValue(forKey: key)
      
      // 팩토리 에러를 WeaverError로 래핑
      if error is WeaverError {
        throw error
      } else {
        throw WeaverError.resolutionFailed(.factoryFailed(keyName: key.description, underlying: error))
      }
    }
  }

  private func getOrCreateWeakInstance(
    key: AnyDependencyKey,
    registration: DependencyRegistration
  ) async throws -> any Sendable {
    // 🚨 [RACE CONDITION ULTIMATE FIX] 약한 참조도 동일한 패턴 적용
    
    // 1. 기존 약한 참조 확인 및 정리
    if let weakBox = weakReferences[key] {
      if await weakBox.isAlive, let value = await weakBox.getValue() {
        return value
      }
      // 해제된 참조 정리
      weakReferences.removeValue(forKey: key)
    }

    // 2. 진행 중인 작업이 있으면 기다림
    if let existingTask = ongoingCreations[key] {
      return try await existingTask.value
    }

    // 3. 새 작업 생성 및 즉시 등록 (원자적 연산)
    let creationTask = Task<any Sendable, Error> {
      try await registration.factory(self)
    }
    
    ongoingCreations[key] = creationTask

    do {
      let instance = try await creationTask.value
      
      // 약한 참조 설정
      try setupWeakReference(key: key, instance: instance)
      ongoingCreations.removeValue(forKey: key)
      
      return instance
    } catch {
      ongoingCreations.removeValue(forKey: key)
      
      // 팩토리 에러를 WeaverError로 래핑
      if error is WeaverError {
        throw error
      } else {
        throw WeaverError.resolutionFailed(.factoryFailed(keyName: key.description, underlying: error))
      }
    }
  }

  // createAndCacheInstance 메서드는 getOrCreateContainerInstance로 통합됨

  // createWeakInstance 메서드는 getOrCreateWeakInstance로 통합됨

  private func setupWeakReference(key: AnyDependencyKey, instance: any Sendable) throws {
    // 약한 참조는 클래스 타입만 가능하므로 AnyObject 체크
    // 실제로는 struct나 enum 타입의 Sendable도 있으므로 체크가 필요하지만
    // 현재 Swift 컴파일러는 모든 Sendable을 AnyObject로 캐스팅 가능하다고 판단
    // 따라서 런타임에서 실제 클래스 타입인지 확인
    guard type(of: instance) is AnyClass else {
      throw WeaverError.resolutionFailed(
        .typeMismatch(
          expected: "AnyObject (class type)",
          actual: "\(type(of: instance))",
          keyName: key.description
        )
      )
    }

    // instance는 이미 Sendable이고, 클래스 타입 체크를 통과했으므로
    // 둘 다 만족하는 타입으로 안전하게 캐스팅
    let sendableObject = instance as! (any AnyObject & Sendable)
    let weakBox = WeakBox(sendableObject)
    weakReferences[key] = weakBox
  }
}

// 🚨 [REMOVED] ScopeManager - ResolutionCoordinator로 통합됨

/// 앱 생명주기 이벤트만 담당하는 Actor
actor ContainerLifecycleManager {
  private let logger: WeaverLogger?

  init(logger: WeaverLogger?) {
    self.logger = logger
  }

  /// 🚨 [FIXED] Critical Issue #2: 생명주기 이벤트 순차 처리 - 백그라운드 진입
  /// DevPrinciples Article 5 Rule 1: 네트워크 해제 → 로그 플러시 순서 보장
  func handleAppDidEnterBackground(
    registrations: [AnyDependencyKey: DependencyRegistration],
    coordinator: ResolutionCoordinator
  ) async {
    await logger?.log(
      message: "📱 App entered background - shutting down services in reverse order", level: .info)

    let appServiceKeys = registrations.filter { $1.scope == .appService }.map { $0.key }

    // 🔧 [CRITICAL FIX] 백그라운드 진입 시 역순 처리
    // 네트워크 → 분석 → 설정 → 로깅 순서로 순차 종료
    let prioritizedKeys = prioritizeAppServiceKeys(appServiceKeys)
    let reversedKeys = Array(prioritizedKeys.reversed())

    for key in reversedKeys {
      // 실제 인스턴스 접근 및 이벤트 전달
      if let instance = await coordinator.getCachedInstance(for: key) as? AppLifecycleAware {
        do {
          try await instance.appDidEnterBackground()
          await logger?.log(
            message: "✅ Background event handled: \(key.description)", level: .debug)
        } catch {
          await logger?.log(
            message: "❌ Background event failed: \(key.description) - \(error)", level: .error)
        }
      }
    }

    await logger?.log(message: "✅ All app services notified of background transition", level: .info)
  }

  /// 🚨 [FIXED] Critical Issue #2: 생명주기 이벤트 순차 처리 - 포그라운드 복귀
  /// DevPrinciples Article 5 Rule 1: 로그 시스템 → 네트워크 재연결 순서 보장
  func handleAppWillEnterForeground(
    registrations: [AnyDependencyKey: DependencyRegistration],
    coordinator: ResolutionCoordinator
  ) async {
    await logger?.log(
      message: "📱 App will enter foreground - reactivating services in priority order", level: .info
    )

    let appServiceKeys = registrations.filter { $1.scope == .appService }.map { $0.key }

    // 🔧 [CRITICAL FIX] 포그라운드 복귀 시 정순 처리
    // 로깅 → 설정 → 분석 → 네트워크 순서로 순차 재활성화
    let prioritizedKeys = prioritizeAppServiceKeys(appServiceKeys)

    for key in prioritizedKeys {
      // 실제 인스턴스 접근 및 이벤트 전달
      if let instance = await coordinator.getCachedInstance(for: key) as? AppLifecycleAware {
        do {
          try await instance.appWillEnterForeground()
          await logger?.log(
            message: "✅ Foreground event handled: \(key.description)", level: .debug)
        } catch {
          await logger?.log(
            message: "❌ Foreground event failed: \(key.description) - \(error)", level: .error)
        }
      }
    }

    await logger?.log(message: "✅ All app services reactivated for foreground", level: .info)
  }

  /// 🚨 [FIXED] Critical Issue #3: 컨테이너 종료 LIFO 순서 보장
  /// DevPrinciples Article 5 Rule 1: 초기화 역순으로 종료하여 의존성 관계 보장
  func handleAppWillTerminate(
    registrations: [AnyDependencyKey: DependencyRegistration],
    coordinator: ResolutionCoordinator
  ) async {
    await logger?.log(
      message: "📱 App will terminate - shutting down services in LIFO order", level: .info)

    let appServiceKeys = registrations.filter { $1.scope == .appService }.map { $0.key }

    // 🔧 [CRITICAL FIX] 초기화 순서의 엄격한 역순으로 정리 (LIFO: Last In, First Out)
    // 네트워크 → 분석 → 설정 → 로깅 순서로 순차 종료하여 의존성 관계 보장
    let prioritizedKeys = prioritizeAppServiceKeys(appServiceKeys)
    let reversedKeys = Array(prioritizedKeys.reversed())

    await logger?.log(
      message: "🔄 Terminating \(reversedKeys.count) app services in dependency-safe order",
      level: .info
    )

    for (index, key) in reversedKeys.enumerated() {
      if let instance = await coordinator.getCachedInstance(for: key) {
        // 🔧 [IMPROVED] 단계별 종료 로깅으로 디버깅 지원
        await logger?.log(
          message: "🛑 Terminating service [\(index + 1)/\(reversedKeys.count)]: \(key.description)",
          level: .debug
        )

        // AppLifecycleAware 프로토콜을 구현한 경우 앱 종료 이벤트 전달
        if let lifecycleAware = instance as? AppLifecycleAware {
          do {
            try await lifecycleAware.appWillTerminate()
            await logger?.log(
              message: "✅ App termination handled: \(key.description)", level: .debug)
          } catch {
            await logger?.log(
              message: "❌ App termination failed: \(key.description) - \(error)", level: .error)
          }
        }

        // Disposable 프로토콜을 구현한 경우 리소스 정리
        if let disposable = instance as? Disposable {
          do {
            try await disposable.dispose()
            await logger?.log(message: "🗑️ App service disposed: \(key.description)", level: .debug)
          } catch {
            await logger?.log(
              message: "❌ App service disposal failed: \(key.description) - \(error)", level: .error
            )
          }
        }
      }
    }

    await logger?.log(message: "✅ All app services terminated in correct LIFO order", level: .info)
  }

  /// 앱 서비스의 초기화 우선순위를 결정합니다 (외부 접근용)
  func prioritizeAppServiceKeys(_ keys: [AnyDependencyKey]) -> [AnyDependencyKey] {
    return keys.sorted { lhs, rhs in
      let lhsPriority = getAppServicePriority(for: lhs)
      let rhsPriority = getAppServicePriority(for: rhs)
      return lhsPriority < rhsPriority
    }
  }

  /// 🔧 [NEW] 외부에서 우선순위를 확인할 수 있는 메서드
  func getAppServicePriority(for key: AnyDependencyKey) -> Int {
    let keyName = key.description.lowercased()

    // 🏗️ Layer 0: 기반 시스템 (Foundation Layer)
    if keyName.contains("log") || keyName.contains("crash") || keyName.contains("debug") {
      return 0
    }

    // 🔧 Layer 1: 설정 및 환경 (Configuration Layer)
    if keyName.contains("config") || keyName.contains("environment") || keyName.contains("setting")
      || keyName.contains("preference") || keyName.contains("theme")
    {
      return 1
    }

    // 📊 Layer 2: 분석 및 모니터링 (Analytics Layer)
    if keyName.contains("analytics") || keyName.contains("tracker") || keyName.contains("metric")
      || keyName.contains("telemetry") || keyName.contains("monitor")
    {
      return 2
    }

    // 🌐 Layer 3: 네트워크 및 외부 통신 (Network Layer)
    if keyName.contains("network") || keyName.contains("api") || keyName.contains("client")
      || keyName.contains("http") || keyName.contains("socket") || keyName.contains("sync")
    {
      return 3
    }

    // 🔐 Layer 4: 보안 및 인증 (Security Layer)
    if keyName.contains("auth") || keyName.contains("security") || keyName.contains("keychain")
      || keyName.contains("biometric") || keyName.contains("token")
    {
      return 4
    }

    // 💾 Layer 5: 데이터 및 저장소 (Data Layer)
    if keyName.contains("database") || keyName.contains("storage") || keyName.contains("cache")
      || keyName.contains("persistence") || keyName.contains("core") && keyName.contains("data")
    {
      return 5
    }

    // 🎯 Layer 6: 비즈니스 로직 및 기능 (Business Layer)
    if keyName.contains("service") || keyName.contains("manager") || keyName.contains("controller")
      || keyName.contains("handler") || keyName.contains("processor")
    {
      return 6
    }

    // 🎨 Layer 7: UI 및 프레젠테이션 (Presentation Layer)
    if keyName.contains("ui") || keyName.contains("view") || keyName.contains("presentation")
      || keyName.contains("coordinator") || keyName.contains("router")
    {
      return 7
    }

    // 🔧 Layer 8: 기타 앱 서비스 (Default Layer)
    return 8
  }

  func shutdown() async {
    await logger?.log(message: "🛑 Container lifecycle manager shutdown", level: .info)
  }
}

// MARK: - ==================== Support Types ====================

// 🚨 [REMOVED] ResolutionEngineWrapper - ResolutionCoordinator가 직접 Resolver 구현

struct ScopeMetrics {
  let cacheHits: Int
  let cacheMisses: Int
  let containerInstances: Int
  let weakReferences: Int
}

// MARK: - ==================== 핵심 타입 정의 ====================

/// 의존성의 생명주기를 정의하는 스코프 타입입니다.
/// 인스턴스가 언제까지 살아있을지를 결정합니다.
public enum Scope: String, Sendable {
  /// 컨테이너 생명주기 동안 단일 인스턴스 유지 (일반적인 싱글톤)
  case container

  /// 약한 참조로 관리되어 메모리 누수 방지
  case weak

  /// 캐시 정책에 따라 관리 (메모리 압박시 해제 가능)
  case cached

  /// 앱 전체 핵심 서비스 (앱 생명주기 이벤트 수신)
  case appService

  /// 부트스트랩 레이어 (필수 시스템 서비스)
  case bootstrap

  /// 코어 레이어 (메인 화면 표시용)
  case core

  /// 피처 레이어 (기능별 서비스)
  case feature
}

/// 의존성의 초기화 시점을 정의하는 열거형입니다.
/// 언제 인스턴스를 생성할지를 결정합니다.
public enum InitializationTiming: String, Sendable, CaseIterable {
  /// 앱 시작과 함께 백그라운드에서 초기화 (중요 서비스)
  /// 로깅, 크래시 리포팅, 분석, 네트워크 모니터 등
  case eager

  /// 메인 화면 표시를 위해 백그라운드에서 초기화 (일반 서비스)
  /// 사용자 세션, 설정, 테마 등
  case background

  /// 실제 사용할 때만 초기화 (기능별 서비스) - 기본값
  /// 카메라, 결제, 위치, 소셜 공유 등
  case onDemand

  /// 지연 초기화 (레거시 호환성)
  case lazy
}

/// `DependencyKey`의 타입 정보를 타입 소거 형태로 감싸는 구조체입니다.
public struct AnyDependencyKey: Hashable, CustomStringConvertible, Sendable {
  private let id: ObjectIdentifier
  private let name: String

  public init<Key: DependencyKey>(_ keyType: Key.Type) {
    self.id = ObjectIdentifier(keyType)
    self.name = String(describing: keyType)
  }

  public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
  public func hash(into hasher: inout Hasher) { hasher.combine(id) }
  public var description: String { name }
}

/// 의존성 등록 정보를 담는 구조체입니다.
public struct DependencyRegistration: Sendable {
  public let scope: Scope
  public let timing: InitializationTiming
  public let factory: @Sendable (Resolver) async throws -> any Sendable
  public let keyName: String
  public let dependencies: [String]

  public init(
    scope: Scope,
    timing: InitializationTiming = .lazy,
    factory: @escaping @Sendable (Resolver) async throws -> any Sendable,
    keyName: String,
    dependencies: [String] = []
  ) {
    self.scope = scope
    self.timing = timing
    self.factory = factory
    self.keyName = keyName
    self.dependencies = dependencies
  }
}

/// 의존성 해결 통계 정보를 담는 구조체입니다.
public struct ResolutionMetrics: Sendable, CustomStringConvertible {
  public let totalResolutions: Int
  public let cacheHits: Int
  public let cacheMisses: Int
  public let averageResolutionTime: TimeInterval
  public let failedResolutions: Int
  public let weakReferences: WeakReferenceMetrics

  public var cacheHitRate: Double {
    (cacheHits + cacheMisses) > 0 ? Double(cacheHits) / Double(cacheHits + cacheMisses) : 0
  }

  public var successRate: Double {
    totalResolutions > 0
      ? Double(totalResolutions - failedResolutions) / Double(totalResolutions) : 0
  }

  public var description: String {
    return """
      Resolution Metrics:
      - Total Resolutions: \(totalResolutions)
      - Success Rate: \(String(format: "%.1f%%", successRate * 100))
      - Failed Resolutions: \(failedResolutions)
      - Cache Hit Rate: \(String(format: "%.1f%%", cacheHitRate * 100)) (Hits: \(cacheHits), Misses: \(cacheMisses))
      - Avg. Resolution Time: \(String(format: "%.4fms", averageResolutionTime * 1000))
      - Weak References: \(weakReferences.aliveWeakReferences)/\(weakReferences.totalWeakReferences) alive (\(String(format: "%.1f%%", (1 - weakReferences.deallocatedRate) * 100)))
      """
  }
}

// 🚨 [REMOVED] ContainerConfiguration은 WeaverBuilder에서 관리됨
// 중복 정의 방지를 위해 제거

// 🚨 [REMOVED] CachePolicy는 WeaverKernel.swift에 정의됨
// 중복 선언 방지를 위해 제거

// MARK: - ==================== Default Implementations ====================

/// `TaskLocal`을 사용하여 의존성 해결 범위를 관리하는 기본 구현체입니다.
public struct DefaultDependencyScope: DependencyScope {
  @TaskLocal private static var _current: WeaverContainer?

  public var current: WeaverContainer? {
    Self._current
  }

  public func withScope<R: Sendable>(
    _ container: WeaverContainer, operation: @Sendable () async throws -> R
  ) async rethrows -> R {
    try await Self.$_current.withValue(container, operation: operation)
  }
}

/// 기본 로거 구현체입니다.
/// DevPrinciples Article 10에 따라 명확한 에러 정보를 제공합니다.
public actor DefaultLogger: WeaverLogger {
  private let logger = Logger(subsystem: "com.weaver.di", category: "Weaver")

  public init() {}

  public func log(message: String, level: OSLogType) {
    logger.log(level: level, "\(message)")
  }

  public func logResolutionFailure(
    keyName: String, currentState: LifecycleState, error: any Error & Sendable
  ) async {
    let stateDescription = describeState(currentState)
    let message =
      "🚨 의존성 해결 실패: '\(keyName)' - 커널 상태: \(stateDescription) - 원인: \(error.localizedDescription)"

    if WeaverEnvironment.isDevelopment {
      let detailedMessage =
        "\(message)\n📍 스택 트레이스: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n"))"
      logger.log(level: .error, "\(detailedMessage)")
    } else {
      logger.log(level: .error, "\(message)")
    }
  }

  public func logStateTransition(from: LifecycleState, to: LifecycleState, reason: String?) async {
    let fromDescription = describeState(from)
    let toDescription = describeState(to)
    let reasonText = reason.map { " - 이유: \($0)" } ?? ""
    let message = "🔄 상태 변경: \(fromDescription) → \(toDescription)\(reasonText)"

    logger.log(level: .info, "\(message)")
  }

  private func describeState(_ state: LifecycleState) -> String {
    switch state {
    case .idle:
      return "대기"
    case .configuring:
      return "구성 중"
    case .warmingUp(let progress):
      let percentageMultiplier = 100
      return "초기화 중 (\(Int(progress * Double(percentageMultiplier)))%)"
    case .ready:
      return "준비 완료"
    case .failed:
      return "실패"
    case .shutdown:
      return "종료"
    }
  }
}

/// 메트릭 수집 기능이 비활성화되었을 때 사용되는 기본 구현체입니다.
final class DummyMetricsCollector: MetricsCollecting, Sendable {
  func recordResolution(duration: TimeInterval) async {}
  func recordFailure() async {}
  func recordCache(hit: Bool) async {}
  func getMetrics(cacheHits: Int, cacheMisses: Int) async -> ResolutionMetrics {
    return ResolutionMetrics(
      totalResolutions: 0,
      cacheHits: cacheHits,
      cacheMisses: cacheMisses,
      averageResolutionTime: 0,
      failedResolutions: 0,
      weakReferences: WeakReferenceMetrics(
        totalWeakReferences: 0,
        aliveWeakReferences: 0,
        deallocatedWeakReferences: 0
      )
    )
  }
}

/// 캐시 기능이 비활성화되었을 때 사용되는 기본 구현체입니다.
final class DummyCacheManager: CacheManaging, Sendable {
  func taskForInstance<T: Sendable>(
    key: AnyDependencyKey, factory: @Sendable @escaping () async throws -> T
  ) async -> (task: Task<any Sendable, Error>, isHit: Bool) {
    let task = Task<any Sendable, Error> {
      try await factory()
    }
    return (task, false)
  }

  func getMetrics() async -> (hits: Int, misses: Int) {
    return (0, 0)
  }

  func clear() async {}
}

// WeakReferenceTracker는 WeakBox로 대체되었습니다.
// WeakBox는 더 타입 안전하고 재사용 가능한 구현을 제공합니다.

// MARK: - ==================== 누락된 타입들 추가 ====================

/// 약한 참조 메트릭 정보
public struct WeakReferenceMetrics: Sendable {
  public let totalWeakReferences: Int
  public let aliveWeakReferences: Int
  public let deallocatedWeakReferences: Int

  public var deallocatedRate: Double {
    totalWeakReferences > 0 ? Double(deallocatedWeakReferences) / Double(totalWeakReferences) : 0
  }
}

// 🚨 [REMOVED] AppLifecycleAware와 Disposable 프로토콜은 WeaverKernel.swift에 정의됨
// 중복 선언 방지를 위해 제거

// MARK: - ==================== ResolutionCoordinator 확장 ====================

extension ResolutionCoordinator {
  /// AnyDependencyKey를 직접 해결하는 내부 메서드
  func resolve(_ key: AnyDependencyKey) async throws -> any Sendable {
    // 순환 참조 검사
    let currentEntry = ResolutionStackEntry(key: key, containerID: ObjectIdentifier(self))
    if Self.resolutionSet.contains(currentEntry) {
      let cycleMessage = (Self.resolutionStack.map { $0.key.description } + [key.description])
        .joined(separator: " -> ")
      throw WeaverError.resolutionFailed(.circularDependency(path: cycleMessage))
    }

    return try await Self.$resolutionStack.withValue(Self.resolutionStack + [currentEntry]) {
      try await Self.$resolutionSet.withValue(Self.resolutionSet.union([currentEntry])) {
        try await _resolveInternalAny(key: key)
      }
    }
  }

  private func _resolveInternalAny(key: AnyDependencyKey) async throws -> any Sendable {
    guard let registration = registrations[key] else {
      if let parent {
        // 부모 컨테이너의 resolve 메서드를 직접 호출
        return try await parent.resolve(key)
      }
      throw WeaverError.resolutionFailed(.keyNotFound(keyName: key.description))
    }

    return try await getOrCreateInstance(key: key, registration: registration)
  }
}

// MARK: - ==================== WeaverContainer 확장 ====================

extension WeaverContainer {
  /// AnyDependencyKey를 직접 해결하는 내부 메서드
  func resolve(_ key: AnyDependencyKey) async throws -> any Sendable {
    let startTime = CFAbsoluteTimeGetCurrent()

    do {
      let instance = try await resolutionCoordinator.resolve(key)

      let duration = CFAbsoluteTimeGetCurrent() - startTime
      await metricsCollector.recordResolution(duration: duration)

      return instance
    } catch {
      let duration = CFAbsoluteTimeGetCurrent() - startTime
      await metricsCollector.recordResolution(duration: duration)
      await metricsCollector.recordFailure()
      throw error
    }
  }
}

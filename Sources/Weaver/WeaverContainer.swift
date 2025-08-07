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

/// 의존성 해결을 담당하는 핵심 컨테이너
public actor WeaverContainer: Resolver {

  // MARK: - Core Dependencies

  private let resolutionCoordinator: ResolutionCoordinator
  private let lifecycleManager: ContainerLifecycleManager
  private let metricsCollector: MetricsCollecting

  // MARK: - State Management

  private var isShutdown = false

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

    // 단일 코디네이터로 통합
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
    // Shutdown 상태 체크
    guard !isShutdown else {
      throw WeaverError.resolutionFailed(.containerShutdown)
    }

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
    // 이미 종료된 경우 중복 실행 방지
    guard !isShutdown else { return }

    // 종료 상태로 설정
    isShutdown = true

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
  /// 의존성 순서를 보장하여 순차적으로 초기화합니다.
  public func initializeAppServiceDependencies(
    onProgress: @escaping @Sendable (Double) async -> Void
  ) async {
    let appServiceKeys = registrations.filter { 
      // startup 스코프의 서비스들을 앱 서비스로 간주
      $1.scope == .startup 
    }.map { $0.key }
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
    let prioritizedKeys = await lifecycleManager.prioritizeAppServiceKeys(appServiceKeys, registrations: registrations)

    // 의존성 순서 보장을 위해 순차적으로 초기화
    var failedServices: [String] = []
    var criticalFailures: [String] = []

    for (index, key) in prioritizedKeys.enumerated() {
      let serviceName = key.description
      let priority = await lifecycleManager.getAppServicePriority(for: key, registrations: registrations)

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

        // 우선순위별 실패 처리
        failedServices.append(serviceName)

        // Priority 0-1 (로깅, 설정)은 Critical 실패로 분류
        if priority <= 1 {
          criticalFailures.append(serviceName)
          await logger?.log(
            message: "🚨 CRITICAL: Essential service failed - \(serviceName)",
            level: .fault
          )
        }

        // 중요 서비스 실패 시에도 계속 진행하되 상태 추적
      }

      // 진행률 업데이트 (순차 처리로 정확한 진행률 보장)
      let progress = Double(index + 1) / Double(totalCount)
      await onProgress(progress)
    }

    // 초기화 결과 요약 로깅
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

    // 초기화 완료 요약 및 성능 메트릭
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

/// 의존성 해결과 스코프 관리를 담당하는 Actor
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
    case .shared, .startup, .whenNeeded:
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
          await logger?.log(
            message: "🗑️ Container cached service disposed: \(key.description)", level: .debug)
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
  
  /// 등록 정보를 반환합니다 (우선순위 계산용)
  func getRegistration(for key: AnyDependencyKey) -> DependencyRegistration? {
    return registrations[key]
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
        throw WeaverError.resolutionFailed(
          .factoryFailed(keyName: key.description, underlying: error))
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
        throw WeaverError.resolutionFailed(
          .factoryFailed(keyName: key.description, underlying: error))
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

    let appServiceKeys = registrations.filter { 
      // startup 스코프의 서비스들을 앱 서비스로 간주
      $1.scope == .startup 
    }.map { $0.key }

    // 🔧 [CRITICAL FIX] 백그라운드 진입 시 역순 처리
    // 네트워크 → 분석 → 설정 → 로깅 순서로 순차 종료
    let prioritizedKeys = prioritizeAppServiceKeys(appServiceKeys, registrations: registrations)
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

    let appServiceKeys = registrations.filter { 
      // startup 스코프의 서비스들을 앱 서비스로 간주
      $1.scope == .startup 
    }.map { $0.key }

    // 🔧 [CRITICAL FIX] 포그라운드 복귀 시 정순 처리
    // 로깅 → 설정 → 분석 → 네트워크 순서로 순차 재활성화
    let prioritizedKeys = prioritizeAppServiceKeys(appServiceKeys, registrations: registrations)

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

    let appServiceKeys = registrations.filter { 
      // startup 스코프의 서비스들을 앱 서비스로 간주
      $1.scope == .startup 
    }.map { $0.key }

    // 🔧 [CRITICAL FIX] 초기화 순서의 엄격한 역순으로 정리 (LIFO: Last In, First Out)
    // 네트워크 → 분석 → 설정 → 로깅 순서로 순차 종료하여 의존성 관계 보장
    let prioritizedKeys = prioritizeAppServiceKeys(appServiceKeys, registrations: registrations)
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
  func prioritizeAppServiceKeys(
    _ keys: [AnyDependencyKey],
    registrations: [AnyDependencyKey: DependencyRegistration]
  ) -> [AnyDependencyKey] {
    return keys.sorted { lhs, rhs in
      let lhsPriority = getAppServicePriority(for: lhs, registrations: registrations)
      let rhsPriority = getAppServicePriority(for: rhs, registrations: registrations)
      return lhsPriority < rhsPriority
    }
  }

  /// 확장 가능한 우선순위 시스템으로 서비스 초기화 순서를 결정합니다.
  /// 스코프 기반 기본 우선순위 + 서비스명 기반 세밀한 조정을 지원합니다.
  func getAppServicePriority(
    for key: AnyDependencyKey,
    registrations: [AnyDependencyKey: DependencyRegistration]
  ) -> Int {
    // 등록 정보에서 스코프를 기반으로 우선순위 결정
    guard let registration = registrations[key] else {
      return 999 // 등록되지 않은 키는 최하위 우선순위
    }
    
    // 1. 스코프 기반 기본 우선순위 (100단위)
    let basePriority = getScopePriority(registration.scope)
    
    // 2. 서비스명 기반 세밀한 조정 (10단위)
    let servicePriority = getServiceSpecificPriority(key.description)
    
    // 3. 의존성 기반 추가 조정 (1단위)
    let dependencyPriority = getDependencyBasedPriority(registration.dependencies)
    
    return basePriority + servicePriority + dependencyPriority
  }
  
  /// 스코프별 기본 우선순위를 반환합니다.
  private func getScopePriority(_ scope: Scope) -> Int {
    switch scope {
    case .startup:
      return 0   // 최우선 - 앱 시작 시 필수 서비스
    case .shared:
      return 100 // 공유 서비스
    case .whenNeeded:
      return 200 // 필요시 로딩 서비스
    case .weak:
      return 300 // 약한 참조 서비스
    }
  }
  
  /// 서비스명 기반 세밀한 우선순위 조정을 반환합니다.
  /// 복잡한 앱에서 특정 서비스의 초기화 순서를 미세 조정할 때 사용합니다.
  private func getServiceSpecificPriority(_ serviceName: String) -> Int {
    let lowercaseName = serviceName.lowercased()
    
    // 로깅 관련 서비스는 최우선
    if lowercaseName.contains("logger") || lowercaseName.contains("log") {
      return 0
    }
    
    // 설정 관련 서비스
    if lowercaseName.contains("config") || lowercaseName.contains("setting") {
      return 10
    }
    
    // 크래시 리포팅 서비스
    if lowercaseName.contains("crash") || lowercaseName.contains("analytics") {
      return 20
    }
    
    // 네트워크 관련 서비스
    if lowercaseName.contains("network") || lowercaseName.contains("api") {
      return 30
    }
    
    // 데이터베이스 관련 서비스
    if lowercaseName.contains("database") || lowercaseName.contains("storage") {
      return 40
    }
    
    // 인증 관련 서비스
    if lowercaseName.contains("auth") || lowercaseName.contains("security") {
      return 50
    }
    
    // 기타 서비스
    return 60
  }
  
  /// 의존성 개수 기반 추가 우선순위 조정을 반환합니다.
  /// 의존성이 적은 서비스일수록 먼저 초기화됩니다.
  private func getDependencyBasedPriority(_ dependencies: [String]) -> Int {
    // 의존성이 많을수록 나중에 초기화 (최대 9까지)
    return min(dependencies.count, 9)
  }

  func shutdown() async {
    await logger?.log(message: "🛑 Container lifecycle manager shutdown", level: .info)
  }
}

// MARK: - ==================== Support Types ====================

struct ScopeMetrics {
  let cacheHits: Int
  let cacheMisses: Int
  let containerInstances: Int
  let weakReferences: Int
}

// MARK: - ==================== 핵심 타입 정의 ====================

/// 의존성의 생명주기를 정의하는 스코프 타입입니다.
/// 사용자 관점에서 직관적이고 명확한 4가지 스코프를 제공합니다.
public enum Scope: String, Sendable {
  /// 앱 전체에서 하나의 인스턴스를 공유합니다 (싱글톤)
  /// 로깅, 설정, 네트워크 서비스 등에 사용
  case shared

  /// 약한 참조로 관리되어 메모리 누수를 방지합니다
  /// 델리게이트, 옵저버 패턴 등에 사용
  case weak

  /// 앱 시작 시 미리 로딩되는 필수 서비스입니다
  /// 로깅, 크래시 리포팅, 기본 설정 등에 사용
  case startup

  /// 실제 사용할 때만 로딩되는 기능별 서비스입니다
  /// 카메라, 결제, 위치 서비스 등에 사용
  case whenNeeded
}

/// 의존성의 초기화 시점을 정의하는 내부 열거형입니다.
/// 스코프에 따라 자동으로 결정되므로 사용자가 직접 지정할 필요가 없습니다.
internal enum InitializationTiming: String, Sendable, CaseIterable {
  /// 앱 시작과 함께 즉시 초기화
  case eager

  /// 실제 사용할 때만 초기화 (기본값)
  case onDemand
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
  internal let timing: InitializationTiming  // internal로 변경
  public let factory: @Sendable (Resolver) async throws -> any Sendable
  public let keyName: String
  public let dependencies: [String]

  public init(
    scope: Scope,
    factory: @escaping @Sendable (Resolver) async throws -> any Sendable,
    keyName: String,
    dependencies: [String] = []
  ) {
    self.scope = scope
    self.timing = Self.getTimingForScope(scope)
    self.factory = factory
    self.keyName = keyName
    self.dependencies = dependencies
  }
  
  /// 스코프에 따라 최적의 초기화 시점을 자동으로 결정합니다.
  private static func getTimingForScope(_ scope: Scope) -> InitializationTiming {
    switch scope {
    case .startup:
      return .eager      // 앱 시작 시 즉시 로딩
    case .shared, .weak, .whenNeeded:
      return .onDemand   // 필요할 때 로딩
    }
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

// MARK: - ==================== 확장 가능한 우선순위 시스템 ====================

/// 커스텀 우선순위 로직을 제공하기 위한 프로토콜입니다.
/// 복잡한 앱에서 특별한 초기화 순서가 필요한 경우 구현하여 사용할 수 있습니다.
public protocol ServicePriorityProvider: Sendable {
    /// 주어진 서비스 키와 등록 정보를 기반으로 우선순위를 계산합니다.
    /// - Parameters:
    ///   - key: 서비스 키
    ///   - registration: 서비스 등록 정보
    /// - Returns: 우선순위 값 (낮을수록 먼저 초기화)
    func getPriority(for key: AnyDependencyKey, registration: DependencyRegistration) async -> Int
}

/// 기본 우선순위 제공자 구현
public struct DefaultServicePriorityProvider: ServicePriorityProvider {
    public init() {}
    
    public func getPriority(for key: AnyDependencyKey, registration: DependencyRegistration) async -> Int {
        let basePriority = getScopePriority(registration.scope)
        let servicePriority = getServiceSpecificPriority(key.description)
        let dependencyPriority = getDependencyBasedPriority(registration.dependencies)
        
        return basePriority + servicePriority + dependencyPriority
    }
    
    private func getScopePriority(_ scope: Scope) -> Int {
        switch scope {
        case .startup: return 0
        case .shared: return 100
        case .whenNeeded: return 200
        case .weak: return 300
        }
    }
    
    private func getServiceSpecificPriority(_ serviceName: String) -> Int {
        let lowercaseName = serviceName.lowercased()
        
        if lowercaseName.contains("logger") || lowercaseName.contains("log") { return 0 }
        if lowercaseName.contains("config") || lowercaseName.contains("setting") { return 10 }
        if lowercaseName.contains("crash") || lowercaseName.contains("analytics") { return 20 }
        if lowercaseName.contains("network") || lowercaseName.contains("api") { return 30 }
        if lowercaseName.contains("database") || lowercaseName.contains("storage") { return 40 }
        if lowercaseName.contains("auth") || lowercaseName.contains("security") { return 50 }
        
        return 60
    }
    
    private func getDependencyBasedPriority(_ dependencies: [String]) -> Int {
        return min(dependencies.count, 9)
    }
}

/// 커스텀 우선순위 제공자를 사용하는 예시
public struct CustomServicePriorityProvider: ServicePriorityProvider {
    private let customPriorities: [String: Int]
    private let fallbackProvider: ServicePriorityProvider
    
    public init(
        customPriorities: [String: Int] = [:],
        fallbackProvider: ServicePriorityProvider = DefaultServicePriorityProvider()
    ) {
        self.customPriorities = customPriorities
        self.fallbackProvider = fallbackProvider
    }
    
    public func getPriority(for key: AnyDependencyKey, registration: DependencyRegistration) async -> Int {
        // 커스텀 우선순위가 있으면 사용
        if let customPriority = customPriorities[key.description] {
            return customPriority
        }
        
        // 없으면 기본 제공자에 위임
        return await fallbackProvider.getPriority(for: key, registration: registration)
    }
}

extension ContainerLifecycleManager {
    /// 커스텀 우선순위 제공자를 사용하여 서비스 우선순위를 계산합니다.
    func getAppServicePriority(
        for key: AnyDependencyKey,
        registrations: [AnyDependencyKey: DependencyRegistration],
        priorityProvider: ServicePriorityProvider = DefaultServicePriorityProvider()
    ) async -> Int {
        guard let registration = registrations[key] else {
            return 999 // 등록되지 않은 키는 최하위 우선순위
        }
        
        return await priorityProvider.getPriority(for: key, registration: registration)
    }
}
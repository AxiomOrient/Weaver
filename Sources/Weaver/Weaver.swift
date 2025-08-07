// Weaver/Sources/Weaver/Weaver.swift

import Foundation
import os

// MARK: - ==================== Weaver Namespace ====================

/// Weaver의 전역적인 설정 및 범위 관리를 위한 동시성 안전한 Actor입니다.
public actor WeaverGlobalState {
    // MARK: - Private Properties
    
    /// 전역적으로 사용될 의존성 범위 관리자입니다.
    private var scopeManager: DependencyScope = DefaultDependencyScope()
    
    /// 앱 레벨에서 사용할 전역 커널입니다.
    private var globalKernel: (any WeaverKernelProtocol)? = nil
    
    /// 커널 상태 변화를 관찰하는 Task입니다.
    private var stateObservationTask: Task<Void, Never>? = nil
    
    /// 향상된 로깅을 위한 로거입니다.
    internal let logger: WeaverLogger = DefaultLogger()
    
    /// 현재 커널의 상태를 캐시합니다.
    private var cachedKernelState: LifecycleState = .idle
    
    // MARK: - Singleton
    
    /// 싱글톤 인스턴스
    public static let shared = WeaverGlobalState()
    
    private init() {}
    
    // MARK: - Public API
    
    /// 현재 작업 범위에 활성화된 `WeaverContainer`입니다.
    public var current: WeaverContainer? {
        get async { await scopeManager.current }
    }
    
    /// 현재 설정된 전역 커널을 반환합니다.
    public func getGlobalKernel() -> (any WeaverKernelProtocol)? {
        return globalKernel
    }
    
    /// 현재 커널의 상태를 반환합니다.
    /// 레이스 컨디션을 방지하기 위해 커널에서 직접 최신 상태를 가져옵니다.
    public var currentKernelState: LifecycleState {
        get async { 
            if let kernel = globalKernel {
                let kernelState = await kernel.currentState
                // 캐시된 상태도 동기화
                cachedKernelState = kernelState
                return kernelState
            }
            return cachedKernelState
        }
    }
    
    /// 전역 커널을 설정하고 상태 모니터링을 시작합니다.
    public func setGlobalKernel(_ kernel: (any WeaverKernelProtocol)?) async {
        // 기존 관찰 작업 정리
        stateObservationTask?.cancel()
        stateObservationTask = nil
        
        // 이전 커널 정보 로깅
        if let previousKernel = globalKernel {
            let newKernelType = kernel.map { String(describing: type(of: $0)) } ?? "nil"
            await logger.log(message: "전역 커널 교체: \(type(of: previousKernel)) → \(newKernelType)", level: .info)
        }
        
        self.globalKernel = kernel
        
        // 새 커널의 상태 스트림 구독 시작
        if let kernel = kernel {
            await startKernelStateObservation(kernel)
            await logger.log(message: "전역 커널 설정 완료: \(type(of: kernel))", level: .info)
        } else {
            cachedKernelState = .idle
            await logger.log(message: "전역 커널 제거됨", level: .info)
        }
    }
    
    /// 완전한 크래시 방지 시스템 - 모든 상황에서 안전한 의존성 해결
    public func safeResolve<Key: DependencyKey>(_ keyType: Key.Type) async -> Key.Value {
        // 1단계: Preview 환경 감지 (최우선)
        if WeaverEnvironment.isPreview {
            await logger.log(
                message: "🎨 Preview 환경에서 \(keyType) 기본값 반환", 
                level: .debug
            )
            return Key.defaultValue
        }
        
        // 2단계: 전역 커널 존재 확인
        guard let kernel = globalKernel else {
            await logger.log(
                message: "⚠️ 전역 커널이 설정되지 않음. \(keyType) 기본값 반환", 
                level: .debug
            )
            return Key.defaultValue
        }
        
        // 3단계: 커널의 safeResolve에 완전히 위임 (상태 동기화 문제 해결)
        let result = await kernel.safeResolve(keyType)
        
        // 캐시된 상태도 동기화
        let currentState = await kernel.currentState
        cachedKernelState = currentState
        
        return result
    }
    
    /// 커널이 준비 완료 상태가 될 때까지 대기합니다.
    public func waitForReady() async throws -> any Resolver {
        guard let kernel = globalKernel else {
            await logger.log(message: "전역 커널이 설정되지 않음. waitForReady 실패", level: .error)
            throw WeaverError.containerNotFound
        }
        
        return try await kernel.waitForReady()
    }
    
    /// 현재 설정된 스코프 매니저를 반환합니다.
    public func getScopeManager() async -> DependencyScope {
        return scopeManager
    }
    
    /// 스코프 매니저를 설정합니다.
    public func setScopeManager(_ manager: DependencyScope) async {
        await logger.log(message: "스코프 매니저 변경: \(type(of: scopeManager)) → \(type(of: manager))", level: .info)
        self.scopeManager = manager
    }
    

    
    /// 스코프 기반 점진적 로딩으로 DI 시스템을 설정합니다.
    /// 앱 시작 시 Bootstrap 스코프만 즉시 활성화하고, 나머지는 사용 시점에 로딩합니다.
    /// - Parameter modules: 등록할 모듈 배열
    /// - Returns: 설정된 커널
    @discardableResult
    public func setupScoped(modules: [Module]) async -> WeaverKernel {
        await logger.log(message: "🚀 스코프 기반 DI 시스템 설정 시작", level: .info)
        
        let kernel = WeaverKernel.scoped(modules: modules, logger: logger)
        await setGlobalKernel(kernel)
        await kernel.build()
        
        await logger.log(message: "✅ 스코프 기반 DI 시스템 설정 완료", level: .info)
        return kernel
    }
    

    



    
    /// 테스트용 완전한 상태 초기화 메서드
    public func resetForTesting() async {
        // 기존 관찰 작업 정리
        stateObservationTask?.cancel()
        stateObservationTask = nil
        
        // 기존 커널을 완전히 종료하여 리소스 정리
        if let kernel = globalKernel {
            await kernel.shutdown()
            await logger.log(message: "🧪 기존 커널 완전 종료: \(type(of: kernel))", level: .debug)
        }
        
        // 상태 완전 초기화
        globalKernel = nil
        cachedKernelState = .idle
        scopeManager = DefaultDependencyScope()
        
        // 정리 완료를 위한 충분한 대기 (비동기 정리 완료 보장)
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        await logger.log(message: "🧪 테스트용 전역 상태 완전 초기화 완료", level: .debug)
    }
    
    
    /// 특정 컨테이너를 현재 작업 범위로 설정하고 주어진 `operation`을 실행합니다.
    public func withScope<R: Sendable>(_ container: WeaverContainer, operation: @Sendable () async throws -> R) async rethrows -> R {
        try await scopeManager.withScope(container, operation: operation)
    }
    
    /// 앱 생명주기 이벤트를 전역 커널의 컨테이너에 전파합니다.
    public func handleAppLifecycleEvent(_ event: AppLifecycleEvent) async {
        guard let kernel = globalKernel else {
            await logger.log(message: "앱 생명주기 이벤트 무시됨 - 전역 커널 없음: \(event)", level: .debug)
            return
        }
        
        // 커널이 준비된 상태에서만 이벤트 처리
        let currentState = await kernel.currentState
        guard case .ready(let resolver) = currentState,
              let container = resolver as? WeaverContainer else {
            await logger.log(message: "앱 생명주기 이벤트 무시됨 - 커널 준비되지 않음: \(event)", level: .debug)
            return
        }
        
        switch event {
        case .didEnterBackground:
            await container.handleAppDidEnterBackground()
        case .willEnterForeground:
            await container.handleAppWillEnterForeground()
        case .willTerminate:
            await container.shutdown()
        }
    }
    
    // MARK: - Private Implementation
    
    /// 커널의 상태 변화를 관찰하는 Task를 시작합니다.
    private func startKernelStateObservation(_ kernel: any WeaverKernelProtocol) async {
        stateObservationTask = Task { [weak self] in
            for await state in kernel.stateStream {
                await self?.handleKernelStateChange(state)
                if Task.isCancelled { break }
            }
        }
    }
    
    /// 커널 상태 변화를 처리하고 로깅합니다.
    private func handleKernelStateChange(_ newState: LifecycleState) async {
        let oldState = cachedKernelState
        
        // 상태 업데이트를 원자적으로 처리
        cachedKernelState = newState
        
        // 상태 변화 로깅
        await logStateTransition(from: oldState, to: newState)
        
        // 특별한 상태에 대한 추가 처리
        switch newState {
        case .failed(let error):
            await logger.log(message: "커널 실패 감지: \(error.localizedDescription)", level: .error)
        case .ready:
            await logger.log(message: "커널 준비 완료", level: .info)
        case .shutdown:
            await logger.log(message: "커널 종료됨", level: .info)
        default:
            break
        }
    }
    
    /// 상태 전환을 상세히 로깅합니다.
    private func logStateTransition(from oldState: LifecycleState, to newState: LifecycleState) async {
        await logger.logStateTransition(from: oldState, to: newState, reason: nil)
    }
    
    /// LifecycleState의 사람이 읽기 쉬운 설명을 반환합니다.
    private func stateDescription(_ state: LifecycleState) -> String {
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

/// 편의를 위한 전역 접근 인터페이스
public enum Weaver {
    /// WeaverGlobalState 싱글톤에 대한 편의 접근자
    public static var shared: WeaverGlobalState { WeaverGlobalState.shared }
    
    /// 현재 작업 범위에 활성화된 `WeaverContainer`입니다.
    /// - Returns: 현재 TaskLocal 스코프의 WeaverContainer 또는 nil
    public static var current: WeaverContainer? {
        get async { await shared.current }
    }
    
    /// 현재 커널의 상태를 반환합니다.
    /// - Returns: 현재 전역 커널의 LifecycleState
    public static var currentKernelState: LifecycleState {
        get async { await shared.currentKernelState }
    }
    
    /// 전역 커널을 설정합니다.
    /// - Parameter kernel: 설정할 WeaverKernel 인스턴스 또는 nil
    public static func setGlobalKernel(_ kernel: (any WeaverKernelProtocol)?) async {
        await shared.setGlobalKernel(kernel)
    }
    
    /// 현재 설정된 전역 커널을 반환합니다.
    /// - Returns: 현재 설정된 WeaverKernel 인스턴스 또는 nil
    public static func getGlobalKernel() async -> (any WeaverKernelProtocol)? {
        await shared.getGlobalKernel()
    }
    
    /// 안전한 의존성 해결을 수행합니다.
    /// - Parameter keyType: 해결할 DependencyKey 타입
    /// - Returns: 해결된 의존성 또는 기본값
    public static func safeResolve<Key: DependencyKey>(_ keyType: Key.Type) async -> Key.Value {
        await shared.safeResolve(keyType)
    }
    
    /// 커널이 준비 완료 상태가 될 때까지 대기합니다.
    /// - Returns: 준비된 Resolver 인스턴스
    /// - Throws: WeaverError (커널 없음, 실패 등)
    public static func waitForReady() async throws -> any Resolver {
        try await shared.waitForReady()
    }
    
    /// 현재 설정된 스코프 매니저를 반환합니다.
    /// - Returns: 현재 DependencyScope 구현체
    public static var scopeManager: DependencyScope {
        get async { await shared.getScopeManager() }
    }
    
    /// 스코프 매니저를 설정합니다.
    /// - Parameter manager: 새로운 DependencyScope 구현체
    public static func setScopeManager(_ manager: DependencyScope) async {
        await shared.setScopeManager(manager)
    }
    
    /// 특정 컨테이너를 현재 작업 범위로 설정하고 주어진 `operation`을 실행합니다.
    /// - Parameters:
    ///   - container: 스코프로 설정할 WeaverContainer
    ///   - operation: 해당 스코프에서 실행할 작업
    /// - Returns: operation의 실행 결과
    public static func withScope<R: Sendable>(_ container: WeaverContainer, operation: @Sendable () async throws -> R) async rethrows -> R {
        try await shared.withScope(container, operation: operation)
    }
    
    /// 앱 생명주기 이벤트를 처리합니다.
    /// - Parameter event: 처리할 앱 생명주기 이벤트
    public static func handleAppLifecycleEvent(_ event: AppLifecycleEvent) async {
        await shared.handleAppLifecycleEvent(event)
    }
    
    /// 앱 시작 시 의존성 시스템을 초기화하는 편의 메서드
    /// - Parameters:
    ///   - modules: 등록할 모듈 배열
    /// - Throws: 초기화 실패 시 WeaverError
    public static func setup(modules: [Module]) async throws {
        await shared.logger.log(message: "🚀 앱 의존성 시스템 초기화 시작", level: .info)
        
        let kernel = WeaverKernel.scoped(modules: modules, logger: shared.logger)
        await shared.setGlobalKernel(kernel)
        await kernel.build()
        
        _ = try await kernel.waitForReady()
        await shared.logger.log(message: "✅ 앱 의존성 시스템 초기화 완료", level: .info)
    }
    

    

    
    /// 테스트용 완전한 상태 초기화
    public static func resetForTesting() async {
        await shared.resetForTesting()
    }
    
    /// 스코프 기반 DI 시스템을 설정하는 편의 메서드 (고급 사용자용)
    /// 앱 시작 시 Bootstrap 스코프만 즉시 활성화하고, 나머지는 사용 시점에 로딩합니다.
    /// - Parameters:
    ///   - modules: 등록할 모듈 배열
    /// - Returns: 설정된 커널
    @discardableResult
    public static func setupScoped(modules: [Module]) async -> WeaverKernel {
        await shared.setupScoped(modules: modules)
    }
    

}

// MARK: - ==================== @Inject Property Wrapper ====================

/// 의존성을 선언하고 주입받기 위한 프로퍼티 래퍼입니다.
///
/// 사용법:
/// ```
/// @Inject(MyServiceKey.self) private var myService
///
/// func doSomething() async {
///     // 1. 기본 안전 버전 (권장) - 절대 크래시하지 않음
///     let service = await myService()
///     service.performAction()
///
///     // 2. 에러 처리 버전 - 명시적 에러 처리가 필요할 때
///     do {
///         let service = try await $myService.resolve()
///         service.performAction()
///     } catch {
///         print("Error: \(error)")
///     }
/// }
/// ```
@propertyWrapper
public struct Inject<Key: DependencyKey>: Sendable {
    private let keyType: Key.Type

    public init(_ keyType: Key.Type) {
        self.keyType = keyType
    }

    /// 래핑된 프로퍼티는 프로퍼티 래퍼 자신을 반환하여, `callAsFunction` 등의 메서드에 접근할 수 있도록 합니다.
    public var wrappedValue: Self {
        self
    }

    /// `$myService`와 같이 ` 접두사를 통해 접근하는 projectedValue는 에러를 던지는(throwing) API 등 대체 기능을 제공합니다.
    public var projectedValue: InjectProjection<Key> {
        InjectProjection(keyType: keyType)
    }

    /// 기본 안전 의존성 접근 방식입니다. `await myService()`와 같이 함수처럼 호출하여 사용합니다.
    /// 어떤 상황에서도 크래시하지 않으며, 실패 시 `Key.defaultValue`를 반환합니다.
    public func callAsFunction() async -> Key.Value {
        let keyName = String(describing: keyType)
        
        // 🔧 [IMPROVED] 일관된 해결 전략 - 우선순위 기반 접근
        return await resolveWithFallbackStrategy(keyName: keyName)
    }
    
    /// 의존성 해결을 위한 명확한 전략을 실행합니다.
    /// DevPrinciples Article 3에 따라 단순하고 명확한 해결 순서를 제공합니다.
    private func resolveWithFallbackStrategy(keyName: String) async -> Key.Value {
        // 1. TaskLocal 스코프 우선 시도
        if let container = await Weaver.current {
            do {
                return try await container.resolve(keyType)
            } catch {
                // 로깅만 수행하고 다음 단계로 진행
                if WeaverEnvironment.isDevelopment {
                    await Weaver.shared.logger.log(
                        message: "TaskLocal 해결 실패, Global로 진행: \(keyName)",
                        level: .debug
                    )
                }
            }
        }
        
        // 2. 전역 커널 시도
        let result = await Weaver.shared.safeResolve(keyType)
        return result
    }
    

}

/// `@Inject`의 `projectedValue`(`$myService`)를 통해 제공되는 기능을 담는 구조체입니다.
/// DevPrinciples Article 3에 따라 단순화된 2가지 API만 제공합니다.
public struct InjectProjection<Key: DependencyKey>: Sendable {
    fileprivate let keyType: Key.Type

    /// 의존성을 해결하고, 실패 시 명확한 에러를 발생시킵니다.
    /// DevPrinciples Article 10에 따라 명시적인 에러 처리를 제공합니다.
    /// 
    /// 사용 예시:
    /// ```swift
    /// do {
    ///     let service = try await $myService.resolve()
    ///     service.performAction()
    /// } catch {
    ///     print("Error: \(error)")
    /// }
    /// ```
    public func resolve() async throws -> Key.Value {
        let keyName = String(describing: keyType)
        
        // 1. TaskLocal 스코프에서 먼저 시도
        if let resolver = await Weaver.current {
            do {
                return try await resolver.resolve(keyType)
            } catch {
                // TaskLocal 해결 실패 시 전역 커널로 fallback
                await Weaver.shared.logger.logResolutionFailure(
                    keyName: keyName, 
                    currentState: .ready(resolver), 
                    error: error
                )
            }
        }
        
        // 2. 전역 커널 상태 확인 및 적절한 에러 발생
        guard await Weaver.getGlobalKernel() != nil else {
            let error = WeaverError.containerNotFound
            await Weaver.shared.logger.logResolutionFailure(
                keyName: keyName, 
                currentState: .idle, 
                error: error
            )
            throw error
        }
        
        let currentState = await Weaver.currentKernelState
        switch currentState {
        case .ready(let resolver):
            do {
                return try await resolver.resolve(keyType)
            } catch {
                let weaverError = WeaverError.dependencyResolutionFailed(
                    keyName: keyName, 
                    currentState: currentState, 
                    underlying: error
                )
                await Weaver.shared.logger.logResolutionFailure(
                    keyName: keyName, 
                    currentState: currentState, 
                    error: error
                )
                throw weaverError
            }
        case .failed(let error):
            let weaverError = WeaverError.containerFailed(underlying: error)
            await Weaver.shared.logger.logResolutionFailure(
                keyName: keyName, 
                currentState: currentState, 
                error: error
            )
            throw weaverError
        default:
            let weaverError = WeaverError.containerNotReady(currentState: currentState)
            await Weaver.shared.logger.logResolutionFailure(
                keyName: keyName, 
                currentState: currentState, 
                error: weaverError
            )
            throw weaverError
        }
    }
    

    

}

// Weaver/Sources/Weaver/Weaver.swift

import Foundation
import os

// MARK: - ==================== Weaver Namespace ====================

/// 단순화된 전역 상태 관리 Actor - DependencyValues와의 호환성에 집중
/// 새로운 @Dependency 시스템과 기존 @Inject 시스템 간의 브리지 역할
public actor WeaverGlobalState {
    // MARK: - Simplified Properties
    
    /// 전역적으로 사용될 의존성 범위 관리자입니다.
    private var scopeManager: DependencyScope = DefaultDependencyScope()
    
    /// 앱 레벨에서 사용할 전역 커널입니다.
    private var globalKernel: (any WeaverKernelProtocol)? = nil
    
    /// 향상된 로깅을 위한 로거입니다.
    internal let logger: WeaverLogger = DefaultLogger()
    
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
    /// 단순화: 캐싱 없이 직접 커널 상태를 조회
    public var currentKernelState: LifecycleState {
        get async { 
            return await globalKernel?.currentState ?? .idle
        }
    }
    
    /// 전역 커널을 설정합니다 (단순화된 버전)
    public func setGlobalKernel(_ kernel: (any WeaverKernelProtocol)?) async {
        // 이전 커널 정보 로깅
        if let previousKernel = globalKernel {
            let newKernelType = kernel.map { String(describing: type(of: $0)) } ?? "nil"
            await logger.log(message: "전역 커널 교체: \(type(of: previousKernel)) → \(newKernelType)", level: .info)
        }
        
        self.globalKernel = kernel
        
        if let kernel = kernel {
            await logger.log(message: "전역 커널 설정 완료: \(type(of: kernel))", level: .info)
        } else {
            await logger.log(message: "전역 커널 제거됨", level: .info)
        }
    }
    
    public func safeResolve<Key: DependencyKey>(_ keyType: Key.Type) async -> Key.Value {
        switch await DependencyValues.currentContext {
        case .preview: return Key.previewValue
        case .test:    return Key.testValue
        case .live:
            if let kernel = globalKernel {
                return await kernel.safeResolve(keyType)
            }
            return Key.liveValue   // 마지막 안전망
        }
    }
    
    /// 커널이 준비 완료 상태인지 확인하고 준비된 Resolver를 반환합니다.
    public func ensureReady() async throws -> any Resolver {
        guard let kernel = globalKernel else {
            await logger.log(message: "전역 커널이 설정되지 않음. ensureReady 실패", level: .error)
            throw WeaverError.containerNotFound
        }
        
        return try await kernel.ensureReady()
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
    /// - Throws: DependencySetupError - 의존성 그래프에 문제가 있는 경우
    @discardableResult
    public func setupScoped(modules: [Module]) async throws -> WeaverKernel {
        await logger.log(message: "🚀 스코프 기반 DI 시스템 설정 시작", level: .info)
        
        let kernel = WeaverKernel.scoped(modules: modules, logger: logger)
        await setGlobalKernel(kernel)
        try await kernel.build()
        
        await logger.log(message: "✅ 스코프 기반 DI 시스템 설정 완료", level: .info)
        return kernel
    }
    

    



    
    /// 테스트용 단순화된 상태 초기화 메서드
    public func resetForTesting() async {
        // 기존 커널을 완전히 종료하여 리소스 정리
        if let kernel = globalKernel {
            await kernel.shutdown()
            await logger.log(message: "🧪 기존 커널 완전 종료: \(type(of: kernel))", level: .debug)
        }
        
        // 상태 완전 초기화
        globalKernel = nil
        scopeManager = DefaultDependencyScope()
        
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
    
    // MARK: - Private Implementation (단순화됨)
    // 복잡한 상태 관찰 및 캐싱 로직 제거
    // DependencyValues 시스템이 이미 컨텍스트별 의존성 해결을 제공
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
    
    /// 커널이 준비 완료 상태인지 확인하고 준비된 Resolver를 반환합니다.
    /// - Returns: 준비된 Resolver 인스턴스
    /// - Throws: WeaverError (커널 없음, 실패 등)
    public static func ensureReady() async throws -> any Resolver {
        try await shared.ensureReady()
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
    /// - Throws: 초기화 실패 시 WeaverError 또는 DependencySetupError
    public static func setup(modules: [Module]) async throws {
        await shared.logger.log(message: "🚀 앱 의존성 시스템 초기화 시작", level: .info)
        
        let kernel = WeaverKernel.scoped(modules: modules, logger: shared.logger)
        await shared.setGlobalKernel(kernel)
        try await kernel.build()
        
        _ = try await kernel.ensureReady()
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
    /// - Throws: DependencySetupError - 의존성 그래프에 문제가 있는 경우
    @discardableResult
    public static func setupScoped(modules: [Module]) async throws -> WeaverKernel {
        try await shared.setupScoped(modules: modules)
    }
    

}



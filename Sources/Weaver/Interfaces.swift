// Weaver/Sources/Weaver/Interfaces.swift

import Foundation
import os

// MARK: - ==================== Core Public Protocols ====================
// 애플리케이션 개발자가 주로 사용하게 될 핵심 프로토콜입니다.

/// 의존성을 정의하는 키(Key) 타입에 대한 프로토콜입니다.
/// 모든 의존성 키는 이 프로토콜을 준수해야 하며, 의존성의 타입과 기본값을 정의합니다.
public protocol DependencyKey: Sendable {
    /// 의존성으로 등록될 값의 타입입니다.
    associatedtype Value: Sendable
    
    /// 의존성을 해결할 수 없을 때 사용될 안전한 기본값입니다.
    /// SwiftUI Preview 또는 테스트 환경에서 유용하게 사용될 수 있습니다.
    static var defaultValue: Value { get }
}

/// 의존성을 해결(resolve)하는 기능을 정의하는 프로토콜입니다.
/// `WeaverContainer`가 이 프로토콜을 구현하며, 등록된 의존성을 꺼내올 때 사용됩니다.
public protocol Resolver: Sendable {
    /// 지정된 키 타입에 해당하는 의존성을 비동기적으로 해결하여 반환합니다.
    /// - Parameter keyType: 해결할 의존성의 `DependencyKey` 타입.
    /// - Returns: 해결된 의존성 인스턴스.
    /// - Throws: `WeaverError` - 의존성 해결 과정에서 문제가 발생한 경우.
    func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value
}

/// 관련 의존성들을 하나의 논리적 단위로 그룹화하고 등록 로직을 모듈화하기 위한 프로토콜입니다.
public protocol Module: Sendable {
    /// `WeaverBuilder`를 사용하여 관련 의존성들을 컨테이너에 등록합니다.
    /// - Parameter builder: 의존성을 등록할 `WeaverBuilder` 인스턴스.
    func configure(_ builder: WeaverBuilder) async
}

/// 컨테이너 스코프로 등록된 인스턴스 중, 컨테이너가 소멸될 때 정리(clean-up) 작업이 필요한 경우 채택하는 프로토콜입니다.
/// 예를 들어, 네트워크 연결 종료, 파일 핸들러 닫기 등의 작업을 수행할 수 있습니다.
public protocol Disposable: Sendable {
    /// 인스턴스가 소유한 리소스를 해제하는 정리 작업을 수행합니다.
    /// - Throws: 리소스 해제 중 발생한 에러
    func dispose() async throws
}




// MARK: - ==================== Lifecycle Management ====================
// DI 컨테이너의 생성, 준비, 종료 등 생명주기를 관리하고 관찰하기 위한 인터페이스입니다.

/// 컨테이너의 생명주기 상태를 명확하게 나타내는 열거형입니다.
public enum LifecycleState: Sendable, Equatable {
    /// 커널은 생성되었지만, 빌드가 시작되기 전의 초기 상태입니다.
    case idle
    /// 모듈 구성 및 기본 설정이 진행 중인 상태입니다.
    case configuring
    /// Eager-scoped 의존성들이 비동기적으로 초기화(warm-up)되고 있는 상태입니다.
    /// `progress` 값을 통해 로딩 UI 등에 활용할 수 있습니다.
    case warmingUp(progress: Double)
    /// 모든 초기화가 완료되어 의존성 해결(resolve)이 가능한 상태입니다.
    case ready(Resolver)
    /// 빌드 또는 초기화 과정에서 복구 불가능한 에러가 발생한 상태입니다.
    case failed(any Error & Sendable)
    /// 컨테이너가 종료되어 모든 리소스가 해제된 상태입니다.
    case shutdown
    
    // MARK: - Equatable 구현
    public static func == (lhs: LifecycleState, rhs: LifecycleState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.configuring, .configuring):
            return true
        case (.warmingUp(let lhsProgress), .warmingUp(let rhsProgress)):
            return lhsProgress == rhsProgress
        case (.ready(_), .ready(_)):
            return true // Resolver 인스턴스 비교는 의미가 없으므로 상태만 비교
        case (.failed(_), .failed(_)):
            return true // 에러 비교는 복잡하므로 상태만 비교
        case (.shutdown, .shutdown):
            return true
        default:
            return false
        }
    }
}

/// 컨테이너의 생명주기(빌드, 상태 전파, 종료)만을 관리하는 프로토콜입니다.
/// 단일 책임 원칙에 따라 생명주기 관리 기능만 담당합니다.
public protocol LifecycleManager: Sendable {
    /// 컨테이너의 현재 `LifecycleState`를 관찰할 수 있는 비동기 스트림입니다.
    /// 이 스트림을 통해 컨테이너의 상태 변화에 따라 UI를 업데이트하거나 특정 로직을 수행할 수 있습니다.
    var stateStream: AsyncStream<LifecycleState> { get }
    
    /// 등록된 모듈과 설정을 기반으로 컨테이너 빌드 및 초기화(`warmUp`)를 시작합니다.
    /// 이 메서드는 즉시 반환되며, 실제 빌드 과정은 백그라운드에서 비동기적으로 수행됩니다.
    func build() async

    /// 활성화된 컨테이너를 안전하게 종료하고 모든 `Disposable` 인스턴스의 리소스를 해제합니다.
    func shutdown() async
}

/// 안전한 의존성 해결 기능만을 담당하는 프로토콜입니다.
/// 단일 책임 원칙에 따라 의존성 해결과 관련된 안전망 기능만 제공합니다.
public protocol SafeResolver: Sendable {
    /// 현재 커널의 상태를 동기적으로 조회합니다.
    /// 앱 초기화 과정에서 안전한 의존성 해결을 위해 사용됩니다.
    var currentState: LifecycleState { get async }
    
    /// 컨테이너가 준비되지 않은 상태에서도 안전하게 의존성을 해결합니다.
    /// 준비되지 않은 경우 `DependencyKey`의 `defaultValue`를 반환합니다.
    func safeResolve<Key: DependencyKey>(_ keyType: Key.Type) async -> Key.Value
    
    /// 컨테이너가 준비 완료 상태가 될 때까지 대기합니다.
    /// 타임아웃이나 실패 시 에러를 발생시킵니다.
    func waitForReady(timeout: TimeInterval?) async throws -> any Resolver
}

/// 두 프로토콜을 조합하여 완전한 커널 기능을 제공하는 프로토콜입니다.
/// SwiftUI를 사용하지 않는 환경(UIKit, AppKit, Server-side)에서 DI 컨테이너를 제어하는 표준 진입점 역할을 합니다.
public protocol WeaverKernelProtocol: LifecycleManager, SafeResolver {
    // 조합으로 기능 제공, 추가 메서드 없음
}


// MARK: - ==================== Configuration & Extensibility ====================
// Weaver의 동작을 커스터마이징하거나 확장할 때 사용하는 프로토콜입니다.

/// Weaver 내부의 로그 출력을 위한 프로토콜입니다.
/// 기본 `DefaultLogger` 외에 커스텀 로깅 시스템(e.g., SwiftyBeaver, os_log)과 연동할 때 사용합니다.
/// DevPrinciples Article 10에 따라 명확한 에러 정보 전파를 지원합니다.
public protocol WeaverLogger: Sendable {
    /// 지정된 레벨로 로그 메시지를 기록합니다.
    /// - Parameters:
    ///   - message: 기록할 로그 메시지.
    ///   - level: OSLogType 레벨 (e.g., `.debug`, `.error`, `.fault`).
    func log(message: String, level: OSLogType) async
    
    /// 의존성 해결 실패에 대한 상세한 로그를 기록합니다.
    /// - Parameters:
    ///   - keyName: 해결하려던 의존성 키 이름
    ///   - currentState: 현재 커널 상태
    ///   - error: 발생한 에러
    func logResolutionFailure(keyName: String, currentState: LifecycleState, error: any Error & Sendable) async
    
    /// 상태 변경에 대한 상세한 로그를 기록합니다.
    /// - Parameters:
    ///   - from: 이전 상태
    ///   - to: 새로운 상태
    ///   - reason: 상태 변경 이유 (선택적)
    func logStateTransition(from: LifecycleState, to: LifecycleState, reason: String?) async
}

/// `@Inject`가 현재 컨테이너를 찾을 때 사용하는 의존성 해결 범위(Scope)를 관리하기 위한 프로토콜입니다.
/// 기본적으로 `TaskLocal`을 사용하는 `DefaultDependencyScope`가 사용됩니다.
public protocol DependencyScope: Sendable {
    /// 현재 `Task` 컨텍스트에서 활성화된 `WeaverContainer`를 반환합니다.
    var current: WeaverContainer? { get async }
    
    /// 지정된 `operation`을 특정 컨테이너 범위 내에서 실행하여, 해당 작업 동안 `current`가 지정된 컨테이너를 반환하도록 합니다.
    func withScope<R: Sendable>(_ container: WeaverContainer, operation: @Sendable () async throws -> R) async rethrows -> R
}


// MARK: - ==================== Internal Manager Protocols ====================
// 고급 기능(캐시, 메트릭)의 동작을 정의하는 내부 프로토콜입니다.
// 대부분의 경우 직접 구현할 필요는 없지만, 특정 요구사항에 맞춰 기본 동작을 교체할 때 사용할 수 있습니다.

/// 의존성 해결에 대한 상세 메트릭을 수집하는 기능을 정의하는 프로토콜입니다.
public protocol MetricsCollecting: Sendable {
    /// 의존성 해결 성공 시 소요 시간을 기록합니다.
    func recordResolution(duration: TimeInterval) async
    /// 의존성 해결 실패를 기록합니다.
    func recordFailure() async
    /// 캐시 히트 또는 미스를 기록합니다.
    func recordCache(hit: Bool) async
    /// 수집된 모든 메트릭 정보를 종합하여 반환합니다.
    func getMetrics(cacheHits: Int, cacheMisses: Int) async -> ResolutionMetrics
}

/// `.cached` 스코프 의존성의 캐싱 전략을 관리하는 기능을 정의하는 프로토ocol입니다.
public protocol CacheManaging: Sendable {
    /// 캐시에서 인스턴스를 찾거나, 없는 경우 `factory`를 통해 생성하는 Task를 반환합니다.
    /// - Returns: 인스턴스를 생성하는 `Task`와 캐시 히트 여부를 담은 튜플 `(task: Task<any Sendable, Error>, isHit: Bool)`.
    func taskForInstance<T: Sendable>(key: AnyDependencyKey, factory: @Sendable @escaping () async throws -> T) async -> (task: Task<any Sendable, Error>, isHit: Bool)
    
    /// 현재 캐시의 히트/미스 메트릭을 반환합니다.
    func getMetrics() async -> (hits: Int, misses: Int)
    
    /// 모든 캐시된 인스턴스를 제거합니다.
    func clear() async
}


// MARK: - ==================== Utility Types ====================



// MARK: - ==================== Timeout 없는 검증 시스템 ====================

/// 의존성 설정 결과를 나타내는 열거형입니다.
public enum DependencySetupResult: Sendable {
    case success
    case failure(DependencySetupError)
}

/// 의존성 설정 실패 원인을 나타내는 열거형입니다.
public enum DependencySetupError: Error, LocalizedError, Sendable {
    case missingDependencies([String])
    case circularDependency([String])
    case invalidConfiguration(String, Error)
    
    public var errorDescription: String? {
        switch self {
        case .missingDependencies(let deps):
            return "누락된 의존성: \(deps.joined(separator: ", "))"
        case .circularDependency(let path):
            return "순환 참조: \(path.joined(separator: " → "))"
        case .invalidConfiguration(let key, let error):
            return "잘못된 설정 '\(key)': \(error.localizedDescription)"
        }
    }
}

/// 의존성 검증 결과를 나타내는 열거형입니다.
public enum DependencyValidation: Sendable {
    case valid
    case missing([String])
    case circular([String])
    case invalid(String, Error)
}

/// 의존성 그래프를 분석하고 검증하는 구조체입니다.
public struct DependencyGraph: Sendable {
    private let registrations: [AnyDependencyKey: DependencyRegistration]
    
    public init(registrations: [AnyDependencyKey: DependencyRegistration]) {
        self.registrations = registrations
    }
    
    /// 의존성 그래프를 검증합니다 (동기적, 빠름)
    public func validate() -> DependencyValidation {
        // 1. 순환 참조 검사
        if let cycle = detectCircularDependencies() {
            return .circular(cycle)
        }
        
        // 2. 누락된 의존성 검사
        let missing = findMissingDependencies()
        if !missing.isEmpty {
            return .missing(missing)
        }
        
        // 3. 모든 검증 통과
        return .valid
    }
    
    private func detectCircularDependencies() -> [String]? {
        // 간단한 DFS 기반 순환 참조 검사
        var visited: Set<AnyDependencyKey> = []
        var recursionStack: Set<AnyDependencyKey> = []
        
        for key in registrations.keys {
            if !visited.contains(key) {
                if let cycle = dfsDetectCycle(key: key, visited: &visited, recursionStack: &recursionStack) {
                    return cycle
                }
            }
        }
        
        return nil
    }
    
    private func dfsDetectCycle(
        key: AnyDependencyKey,
        visited: inout Set<AnyDependencyKey>,
        recursionStack: inout Set<AnyDependencyKey>
    ) -> [String]? {
        visited.insert(key)
        recursionStack.insert(key)
        
        // 현재 구현에서는 의존성 정보가 문자열로만 저장되어 있어
        // 실제 순환 참조 검사는 제한적입니다.
        // 실제 구현에서는 더 정교한 그래프 분석이 필요합니다.
        
        recursionStack.remove(key)
        return nil
    }
    
    private func findMissingDependencies() -> [String] {
        // 등록된 의존성들이 참조하는 다른 의존성들이 실제로 등록되어 있는지 확인
        // 현재 구현에서는 의존성 정보가 제한적이므로 기본 검증만 수행
        return []
    }
}

/// 환경 관련 유틸리티를 제공하는 네임스페이스입니다.
/// DevPrinciples Article 5에 따라 명확하고 일관된 API를 제공합니다.
public enum WeaverEnvironment {
    /// 현재 코드가 SwiftUI Preview 환경에서 실행 중인지 여부를 반환합니다.
    /// Preview 환경에서는 `fatalError` 대신 `DependencyKey`의 `defaultValue`를 사용하도록 유도하여 Preview 중단을 방지할 수 있습니다.
    public static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    
    /// 현재 코드가 개발 환경(DEBUG 빌드)에서 실행 중인지 여부를 반환합니다.
    /// 개발 환경에서는 더 상세한 디버그 정보와 로깅을 제공합니다.
    public static var isDevelopment: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    /// 현재 코드가 테스트 환경에서 실행 중인지 여부를 반환합니다.
    /// 테스트 환경에서는 동기적 초기화 옵션을 제공하여 테스트 속도를 향상시킵니다.
    public static var isTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        NSClassFromString("XCTest") != nil
    }
}

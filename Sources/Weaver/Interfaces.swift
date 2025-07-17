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
    func dispose() async
}


// MARK: - ==================== Lifecycle Management ====================
// DI 컨테이너의 생성, 준비, 종료 등 생명주기를 관리하고 관찰하기 위한 인터페이스입니다.

/// 컨테이너의 생명주기 상태를 명확하게 나타내는 열거형입니다.
public enum LifecycleState: Sendable {
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
}

/// 컨테이너의 생명주기(빌드, 상태 전파, 종료)를 관리하는 핵심 컨트롤 타워 프로토콜입니다.
/// SwiftUI를 사용하지 않는 환경(UIKit, AppKit, Server-side)에서 DI 컨테이너를 제어하는 표준 진입점 역할을 합니다.
public protocol WeaverKernel: Sendable {
    /// 컨테이너의 현재 `LifecycleState`를 관찰할 수 있는 비동기 스트림입니다.
    /// 이 스트림을 통해 컨테이너의 상태 변화에 따라 UI를 업데이트하거나 특정 로직을 수행할 수 있습니다.
    var stateStream: AsyncStream<LifecycleState> { get }
    
    /// 등록된 모듈과 설정을 기반으로 컨테이너 빌드 및 초기화(`warmUp`)를 시작합니다.
    /// 이 메서드는 즉시 반환되며, 실제 빌드 과정은 백그라운드에서 비동기적으로 수행됩니다.
    func build() async

    /// 활성화된 컨테이너를 안전하게 종료하고 모든 `Disposable` 인스턴스의 리소스를 해제합니다.
    func shutdown() async
}


// MARK: - ==================== Configuration & Extensibility ====================
// Weaver의 동작을 커스터마이징하거나 확장할 때 사용하는 프로토콜입니다.

/// Weaver 내부의 로그 출력을 위한 프로토콜입니다.
/// 기본 `DefaultLogger` 외에 커스텀 로깅 시스템(e.g., SwiftyBeaver, os_log)과 연동할 때 사용합니다.
public protocol WeaverLogger: Sendable {
    /// 지정된 레벨로 로그 메시지를 기록합니다.
    /// - Parameters:
    ///   - message: 기록할 로그 메시지.
    ///   - level: OSLogType 레벨 (e.g., `.debug`, `.error`, `.fault`).
    func log(message: String, level: OSLogType) async
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

/// 환경 관련 유틸리티를 제공하는 네임스페이스입니다.
public enum WeaverEnvironment {
    /// 현재 코드가 SwiftUI Preview 환경에서 실행 중인지 여부를 반환합니다.
    /// Preview 환경에서는 `fatalError` 대신 `DependencyKey`의 `defaultValue`를 사용하도록 유도하여 Preview 중단을 방지할 수 있습니다.
    public static var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

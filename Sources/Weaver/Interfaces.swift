// Interfaces.swift

import Foundation
import os

// MARK: - ==================== Core Protocols ====================

/// 의존성을 정의하는 키 타입에 대한 프로토콜입니다.
/// 모든 의존성 키는 이 프로토콜을 준수해야 합니다.
public protocol DependencyKey: Sendable {
    /// 의존성 값의 타입입니다.
    associatedtype Value: Sendable
    /// 의존성을 해결할 수 없을 때 사용될 기본값입니다.
    static var defaultValue: Value { get }
}

/// 의존성을 해결(resolve)하는 기능을 정의하는 프로토콜입니다.
/// `WeaverContainer`가 이 프로토콜을 구현합니다.
public protocol Resolver: Sendable {
    /// 지정된 키 타입에 해당하는 의존성을 해결하여 반환합니다.
    /// - Parameter keyType: 해결할 의존성의 `DependencyKey` 타입.
    /// - Returns: 해결된 의존성 인스턴스.
    /// - Throws: `WeaverError` - 의존성 해결에 실패한 경우.
    func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value
}

/// 관련 의존성들을 그룹화하고 등록 로직을 모듈화하기 위한 프로토콜입니다.
public protocol Module: Sendable {
    /// 빌더를 사용하여 관련 의존성들을 등록합니다.
    /// - Parameter builder: 의존성을 등록할 `WeaverBuilder` 인스턴스.
    func configure(_ builder: WeaverBuilder) async
}

/// 컨테이너 스코프로 등록된 인스턴스 중, 컨테이너가 종료될 때 정리 작업이 필요한 경우 채택하는 프로토콜입니다.
public protocol Disposable: Sendable {
    /// 인스턴스 정리 작업을 수행합니다.
    func dispose() async
}

/// Weaver 내부의 로그 출력을 위한 프로토콜입니다.
public protocol WeaverLogger: Sendable {
    /// 지정된 레벨로 로그 메시지를 기록합니다.
    /// - Parameters:
    ///   - message: 기록할 로그 메시지.
    ///   - level: OSLogType 레벨 (e.g., `.debug`, `.error`).
    func log(message: String, level: OSLogType) async
}

/// 의존성 해결 범위를 관리하기 위한 프로토콜입니다.
public protocol DependencyScope: Sendable {
    /// 현재 활성화된 `WeaverContainer`를 반환합니다.
    var current: WeaverContainer? { get async }
    /// 지정된 `operation`을 특정 컨테이너 범위 내에서 실행합니다.
    func withScope<R: Sendable>(_ container: WeaverContainer, operation: @Sendable () async throws -> R) async rethrows -> R
}

// MARK: - ==================== Manager Protocols ====================

/// 의존성 해결에 대한 메트릭을 수집하는 기능을 정의하는 프로토콜입니다.
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

/// 캐시 로직을 관리하는 기능을 정의하는 프로토콜입니다.
public protocol CacheManaging: Sendable {
    /// 캐시에서 인스턴스를 가져오거나, 없는 경우 `factory`를 통해 생성하고 캐시에 저장합니다.
    /// - Returns: 해결된 인스턴스와 캐시 히트 여부를 담은 튜플 `(value: T, isHit: Bool)`.
    func getOrCreateInstance<T: Sendable>(key: AnyDependencyKey, factory: @Sendable @escaping () async throws -> T) async throws -> (value: T, isHit: Bool)
    
    /// 현재 캐시의 히트/미스 메트릭을 반환합니다.
    func getMetrics() async -> (hits: Int, misses: Int)
    
    /// 모든 캐시를 비웁니다.
    func clear() async
}

// Weaver/Sources/Weaver/PlatformAppropriateLock.swift
// iOS 15 지원을 위한 크로스 플랫폼 잠금 메커니즘

import Foundation
import os

/// OS 버전에 맞춰 최적의 잠금 메커니즘을 제공하는 래퍼 구조체입니다.
/// - iOS 16.0 이상: `OSAllocatedUnfairLock`을 사용합니다.
/// - 이전 버전: `NSLock`을 사용하여 스레드 안전성을 보장합니다.
///
/// DevPrinciples Article 5 Rule 2에 따라 의존성을 추상화하여 테스트 가능성을 높입니다.
public struct PlatformAppropriateLock<State: Sendable>: Sendable {

    /// 실제 잠금 구현을 추상화하는 내부 클래스 (Type Eraser).
    /// 상속이 필요하므로 `final`이 아니며, 개발자가 동시성 안전을 보장하므로 `@unchecked Sendable`로 표시합니다.
    internal class AnyLock: @unchecked Sendable {
        /// 하위 클래스에서 반드시 재정의해야 하는 추상 메서드.
        func withLock<R: Sendable>(_ body: @Sendable (inout State) throws -> R) rethrows -> R {
            fatalError("Subclass must override this method.")
        }
    }

    /// iOS 16+에서 사용될 `OSAllocatedUnfairLock` 래퍼.
    /// 상위 클래스의 @unchecked Sendable 준수를 다시 명시합니다.
    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    private final class ModernLock: AnyLock, @unchecked Sendable {
        private let lock: OSAllocatedUnfairLock<State>

        init(initialState: State) {
            self.lock = .init(initialState: initialState)
        }

        override func withLock<R: Sendable>(_ body: @Sendable (inout State) throws -> R) rethrows -> R {
            return try lock.withLock(body)
        }
    }

    /// iOS 15 및 이전 버전에서 사용될 `NSLock` 래퍼.
    /// 상위 클래스의 @unchecked Sendable 준수를 다시 명시합니다.
    private final class LegacyLock: AnyLock, @unchecked Sendable {
        private let nsLock = NSLock()
        private var state: State

        init(initialState: State) {
            self.state = initialState
            self.nsLock.name = "com.weaver.legacylock"
        }

        override func withLock<R: Sendable>(_ body: @Sendable (inout State) throws -> R) rethrows -> R {
            nsLock.lock()
            defer { nsLock.unlock() }
            return try body(&state)
        }
    }

    /// 실제 잠금 객체. `AnyLock` 타입으로 저장하여 구현을 숨깁니다.
    /// public func에서 접근해야 하므로 internal로 변경합니다.
    internal let _lock: AnyLock

    /// 런타임에 OS 버전을 확인하여 적절한 잠금 구현체를 생성합니다.
    public init(initialState: State) {
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
            self._lock = ModernLock(initialState: initialState)
        } else {
            self._lock = LegacyLock(initialState: initialState)
        }
    }

    /// 잠금을 획득하고 주어진 클로저를 실행한 뒤 잠금을 해제합니다.
    /// - Parameter body: @Sendable 클로저. 반환 타입 R도 Sendable이어야 합니다.
    /// `@inlinable`을 제거하여 internal 멤버 접근 오류를 해결합니다.
    public func withLock<R: Sendable>(_ body: @Sendable (inout State) throws -> R) rethrows -> R {
        return try _lock.withLock(body)
    }
}

// MARK: - Performance Monitoring Extension

extension PlatformAppropriateLock {
    /// 현재 사용 중인 잠금 메커니즘 타입을 반환합니다.
    /// 디버깅 및 성능 모니터링 용도로 사용됩니다.
    public var lockMechanismInfo: String {
        // _lock이 internal이 되었으므로, extension에서 접근 가능합니다.
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
            if _lock is ModernLock {
                return "OSAllocatedUnfairLock (iOS 16+)"
            } else {
                // Modern OS에서 LegacyLock이 실행될 일은 없지만, 안전을 위해 분기 처리
                return "NSLock (Fallback on Modern OS)"
            }
        } else {
            return "NSLock (iOS 15)"
        }
    }
}

// MARK: - Testing Support

#if DEBUG
extension PlatformAppropriateLock {
    /// 테스트 환경에서 잠금 상태를 확인할 수 있는 헬퍼 메서드.
    public func withLockForTesting<R: Sendable>(_ body: @Sendable (State) throws -> R) rethrows -> R {
        return try withLock { state in
            return try body(state)
        }
    }
}
#endif

// Weaver/Sources/Weaver/Use.swift

import Foundation

// MARK: - ==================== @Use Property Wrapper (UX-First) ====================

/// UX-First: 즉시 안전값을 제공하고, 준비 완료 시 자동 업그레이드를 구독할 수 있는 래퍼
/// - 동기 접근: `await use()` 로 현재 안전값 획득 (크래시 없음)
/// - 비동기 업그레이드: `$use.updates()` 로 준비/재준비 시 최신 값 스트림 구독
@propertyWrapper
public struct Use<Key: DependencyKey>: Sendable {
    private let keyType: Key.Type

    public init(_ keyType: Key.Type) {
        self.keyType = keyType
    }

    /// 래퍼 자체를 반환하여 `callAsFunction()`과 `$` API를 노출
    public var wrappedValue: Self { self }

    /// `$dep` 투영 값: 업데이트 스트림과 명시적 resolve 제공
    public var projectedValue: UseProjection<Key> { UseProjection(keyType: keyType) }

    /// 동기 안전값 접근: 준비 전에는 컨텍스트별 안전 기본값을, 준비 후에는 live 값을 보장
    /// View/VM에서는 `let value = await dep()` 형태로 사용
    public func callAsFunction() async -> Key.Value {
        // 컨텍스트 기반 안전값 (Preview/Test/live)
        let ctx = await DependencyValues.currentContext
        let initial: Key.Value = {
            switch ctx {
            case .preview: return Key.previewValue
            case .test: return Key.testValue
            case .live: return Key.liveValue
            }
        }()

        // 커널이 준비된 경우 안전 해결, 아니면 안전값 반환
        if let kernel = await Weaver.getGlobalKernel() {
            let state = await kernel.currentState
            if case .ready(let resolver) = state {
                if let resolved = try? await resolver.resolve(Key.self) {
                    return resolved
                }
            }
        }
        return initial
    }

    /// 컨텍스트 기반 기본값을 비동기적으로 제공합니다.
    public func immediateDefault() async -> Key.Value {
        let ctx = await DependencyValues.currentContext
        switch ctx {
        case .preview: return Key.previewValue
        case .test: return Key.testValue
        case .live: return Key.liveValue
        }
    }
}

// MARK: - ==================== Projection ====================

/// @Use의 투영 값: 업데이트 스트림과 명시적 resolve 제공
public struct UseProjection<Key: DependencyKey>: Sendable {
    fileprivate let keyType: Key.Type

    /// 준비 완료(ready) 시점과 이후 재준비 시 최신 값을 흘려보내는 스트림
    /// 첫 이벤트는 컨텍스트별 안전 기본값을 즉시 방출
    public func updates() -> AsyncStream<Key.Value> {
        AsyncStream { continuation in
            let task = Task {
                // 1) 즉시 안전값 방출
                let ctx = await DependencyValues.currentContext
                let initial: Key.Value = {
                    switch ctx {
                    case .preview: return Key.previewValue
                    case .test: return Key.testValue
                    case .live: return Key.liveValue
                    }
                }()
                continuation.yield(initial)

                // 2) 커널 상태 스트림을 구독하며 준비 시점에 최신 값 방출
                if let kernel = await Weaver.getGlobalKernel() {
                                        let stream = kernel.stateStream
                    for await state in stream {
                        if case .ready(let resolver) = state {
                            if let resolved = try? await resolver.resolve(Key.self) {
                                continuation.yield(resolved)
                            }
                        }
                    }
                } else {
                    // 커널 미설정 환경에서는 안전값만 제공
                }

                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 명시적으로 최신 값을 해결 (준비 안 되었으면 에러)
    public func resolve() async throws -> Key.Value {
        let resolver = try await Weaver.ensureReady()
        return try await resolver.resolve(Key.self)
    }
}

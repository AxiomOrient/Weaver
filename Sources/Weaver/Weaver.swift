import Foundation
import os

// MARK: - ==================== Weaver Namespace ====================

/// Weaver의 전역적인 설정 및 범위 관리를 위한 네임스페이스입니다.
@MainActor
public enum Weaver {
    /// 전역적으로 사용될 의존성 범위 관리자입니다.
    /// TaskLocal을 사용하여 현재 실행 컨텍스트에 맞는 DI 컨테이너를 관리합니다.
    public static var scopeManager: DependencyScope = DefaultDependencyScope()

    /// 현재 작업 범위에 활성화된 `WeaverContainer`입니다.
    public static var current: WeaverContainer? {
        get async { await scopeManager.current }
    }

    /// 특정 컨테이너를 현재 작업 범위로 설정하고 주어진 `operation`을 실행합니다.
    public static func withScope<R: Sendable>(_ container: WeaverContainer, operation: @Sendable () async throws -> R) async rethrows -> R {
        try await scopeManager.withScope(container, operation: operation)
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
///     // non-throwing, 실패 시 defaultValue 반환
///     let service = await myService()
///     service.performAction()
///
///     // throwing, 실패 시 에러 발생
///     do {
///         let service = try await $myService.resolved
///         service.performAction()
///     } catch {
///         print("Error: \(error)")
///     }
/// }
/// ```
@propertyWrapper
public struct Inject<Key: DependencyKey>: Sendable {
    private let keyType: Key.Type
    private let storage = ValueStorage<Key.Value>()
    
    public init(_ keyType: Key.Type) {
        self.keyType = keyType
    }
    
    /// 래핑된 프로퍼티는 프로퍼티 래퍼 자신을 반환하여, `callAsFunction` 등의 메서드에 접근할 수 있도록 합니다.
    public var wrappedValue: Self {
        return self
    }
    
    /// `$myService`와 같이 접두사를 통해 접근하는 projectedValue는 에러를 던지는(throwing) API 등 대체 기능을 제공합니다.
    public var projectedValue: InjectProjection<Key> {
        InjectProjection(keyType: keyType, getOrResolveValue: { @Sendable in
            try await self.getOrResolveValue()
        })
    }
    
    /// 기본 의존성 접근 방식입니다. `await service()`와 같이 함수처럼 호출하여 사용합니다.
    ///
    /// 의존성 해결에 실패할 경우 `Key.defaultValue`를 반환하고, 디버깅을 위해 로그를 남깁니다.
    public func callAsFunction() async -> Key.Value {
        do {
            return try await getOrResolveValue()
        } catch {
            let errorMessage = "의존성 해결 실패: \(Key.self). 기본값을 반환합니다. 에러: \(error.localizedDescription)"
            Task { await Weaver.current?.logger?.log(message: errorMessage, level: .debug) }
            return Key.defaultValue
        }
    }
    
    private func getOrResolveValue() async throws -> Key.Value {
        if let cachedResult = await storage.getResult() {
            return try cachedResult.get()
        }
        let newResult: Result<Key.Value, Error>
        do {
            guard let container = await Weaver.current else {
                throw WeaverError.containerNotFound
            }
            let value = try await container.resolve(keyType)
            newResult = .success(value)
        } catch {
            newResult = .failure(error)
        }
        await storage.setResult(newResult)
        return try newResult.get()
    }
    
    private actor ValueStorage<Value: Sendable> {
        private var resolutionResult: Result<Value, Error>?
        func getResult() -> Result<Value, Error>? { resolutionResult }
        func setResult(_ newResult: Result<Value, Error>) { resolutionResult = newResult }
    }
}

/// `@Inject`의 `projectedValue`를 통해 제공되는 기능을 담는 구조체입니다.
public struct InjectProjection<Key: DependencyKey>: Sendable {
    fileprivate let getOrResolveValue: @Sendable () async throws -> Key.Value
    fileprivate let keyType: Key.Type
    
    public var resolved: Key.Value {
        get async throws {
            try await getOrResolveValue()
        }
    }
    
    /// 지정된 `Resolver`로부터 의존성을 해결합니다.
    /// 테스트 또는 특정 스코프의 `Resolver`를 명시적으로 사용하고 싶을 때 유용합니다.
    public func from(_ resolver: any Resolver) async throws -> Key.Value {
        try await resolver.resolve(keyType)
    }
    
    // 초기화 메서드
    fileprivate init(keyType: Key.Type, getOrResolveValue: @escaping @Sendable () async throws -> Key.Value) {
        self.keyType = keyType
        self.getOrResolveValue = getOrResolveValue
    }
}

// MARK: - ==================== Default Implementations ====================

/// `TaskLocal`을 사용하여 의존성 해결 범위를 관리하는 기본 구현체입니다.
public struct DefaultDependencyScope: DependencyScope {
    @TaskLocal private static var _current: WeaverContainer?
    
    public var current: WeaverContainer? {
        get { Self._current }
    }
    
    public func withScope<R: Sendable>(_ container: WeaverContainer, operation: @Sendable () async throws -> R) async rethrows -> R {
        try await Self.$_current.withValue(container, operation: operation)
    }
}

/// 기본 로거 구현체입니다.
public actor DefaultLogger: WeaverLogger {
    private let logger = Logger(subsystem: "com.weaver.di", category: "Weaver")
    public init() {}
    public func log(message: String, level: OSLogType) {
        logger.log(level: level, "\(message)")
    }
}
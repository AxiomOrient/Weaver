import Foundation

// MARK: - 컨테이너 내부 데이터 구조

internal struct DependencyRegistration: Sendable {
    let scope: Scope
    let factory: @Sendable (Resolver) async throws -> Any
    let keyName: String
    let registrationTime: Date
    
    init<Value>(
        scope: Scope,
        factory: @escaping @Sendable (Resolver) async throws -> Value,
        keyName: String
    ) {
        self.scope = scope
        self.factory = { resolver in try await factory(resolver) }
        self.keyName = keyName
        self.registrationTime = Date()
    }
}

/// Weaver가 내부적으로 사용하는 로그의 레벨을 정의합니다.
public enum LogLevel: String, Sendable {
    case debug = "🔍 DEBUG"
    case info = "ℹ️ INFO"
    case warning = "⚠️ WARNING"
    case error = "❌ ERROR"
}

/// 의존성 인스턴스를 예상 타입으로 캐스팅하는 데 실패했을 때 발생하는 에러입니다.
public struct CastingError: Error, LocalizedError {
    public let description: String
    
    public init(_ message: String = "Failed to cast dependency instance to expected type") {
        self.description = message
    }
    public var errorDescription: String? { description }
}

/// Weaver 컨테이너의 로그 출력을 처리하는 로거 프로토콜입니다.
public protocol WeaverLogger: Sendable {
    func log(message: String, level: LogLevel)
}

/// 콘솔에 로그를 출력하는 기본 로거입니다.
internal struct ConsoleLogger: WeaverLogger {
    func log(message: String, level: LogLevel) {
        print("[(level.rawValue)] [Weaver] \(message)")
    }
}

// MARK: - WeaverContainer

public final class WeaverContainer: Resolver, @unchecked Sendable {
    private let parent: WeaverContainer?
    private let registrations: [AnyDependencyKey: DependencyRegistration]
    private let scopeManager = ScopeManager()
    private let factoryManager = FactoryManager()
    private var logger: WeaverLogger?

    @TaskLocal private static var resolutionStack: Set<AnyDependencyKey> = []

    public init(modules: [Module], parent: WeaverContainer? = nil) {
        self.parent = parent
        
        let builder = ContainerBuilder()
        for module in modules {
            module.configure(builder)
        }
        self.registrations = builder.registrations
        self.logger = parent?.logger
    }
    
    public func newScope(modules: [Module], overrides: [Module] = []) -> WeaverContainer {
        let container = WeaverContainer(modules: modules, parent: self)
        if !overrides.isEmpty {
            return WeaverContainer(modules: overrides, parent: container)
        }
        return container
    }

    // MARK: - 의존성 해결

    public func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value {
        let key = AnyDependencyKey(keyType)
        let keyName = String(describing: keyType)

        if let registration = registrations[key] {
            return try await resolve(key: key, keyName: keyName, registration: registration)
        } else if let parent = parent {
            log("Could not find '\(keyName)' in current scope. Trying parent.", level: .debug)
            return try await parent.resolve(keyType)
        } else {
            log("No registration for '\(keyName)'. Returning default value.", level: .warning)
            return Key.defaultValue
        }
    }
    
    private func resolve<Value>(key: AnyDependencyKey, keyName: String, registration: DependencyRegistration) async throws -> Value {
        if registration.scope != .transient {
            if let cachedValue: Value = await scopeManager.getInstance(key: key, scope: registration.scope) {
                log("Cache hit for '\(keyName)' in scope: \(registration.scope)", level: .debug)
                return cachedValue
            }
        }

        guard !Self.resolutionStack.contains(key) else {
            let cycle = Self.resolutionStack.map { $0.description }.joined(separator: " -> ")
            throw DependencyError.circularDependency("\(cycle) -> \(keyName)")
        }

        return try await Self.$resolutionStack.withValue(Self.resolutionStack.union([key])) {
            log("Creating new instance for '\(keyName)' with scope: \(registration.scope)", level: .info)
            
            let instance: Value = try await factoryManager.executeFactory(
                key: key,
                factory: { try await registration.factory(self) },
                keyName: keyName
            )
            
            if registration.scope != .transient {
                await scopeManager.storeInstance(key: key, value: instance, scope: registration.scope)
                log("Stored new instance for '\(keyName)' in scope: \(registration.scope)", level: .debug)
            }
            return instance
        }
    }

    // MARK: - 디버깅 지원
    
    public func setLogger(_ logger: WeaverLogger?) {
        self.logger = logger
    }

    internal func log(_ message: String, level: LogLevel) {
        logger?.log(message: message, level: level)
    }
}

// MARK: - ContainerBuilder

public final class ContainerBuilder: @unchecked Sendable {
    fileprivate var registrations: [AnyDependencyKey: DependencyRegistration] = [:]

    public func register<Key: DependencyKey>(
        _ keyType: Key.Type,
        scope: Scope = .transient,
        factory: @escaping @Sendable (Resolver) async throws -> Key.Value
    ) {
        let key = AnyDependencyKey(keyType)
        let keyName = String(describing: keyType)
        let registration = DependencyRegistration(
            scope: scope,
            factory: factory,
            keyName: keyName
        )
        registrations[key] = registration
    }
}
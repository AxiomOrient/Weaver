// Sources/Weaver/DependencyInterfaces.swift

import Foundation
import os

// MARK: - Core Context & Keys

public enum DependencyContext: Sendable {
    case live
    case preview
    case test
}

public protocol DependencyKey: Sendable {
    associatedtype Value: Sendable
    static var liveValue: Value { get }
    static var previewValue: Value { get }
    static var testValue: Value { get }
}

public extension DependencyKey {
    static var previewValue: Value { liveValue }
    static var testValue: Value { liveValue }
}

// MARK: - Lifetime & Registration

public enum DependencyLifetime: Sendable {
    case singleton
    case weakReference
    case transient
}

public struct DependencyRegistration: Sendable {
    public let lifetime: DependencyLifetime
    public let factory: @Sendable (DependencyResolver) async throws -> any Sendable
    public let keyName: String
    public let dependencies: Set<AnyDependencyKey>

    public init(
        lifetime: DependencyLifetime,
        factory: @escaping @Sendable (DependencyResolver) async throws -> any Sendable,
        keyName: String,
        dependencies: Set<AnyDependencyKey> = []
    ) {
        self.lifetime = lifetime
        self.factory = factory
        self.keyName = keyName
        self.dependencies = dependencies
    }
}

// MARK: - Resolver & Modules

public protocol DependencyResolver: Sendable {
    func resolve<Key: DependencyKey>(_ key: Key.Type) async throws -> Key.Value
}

public protocol DependencyModule: Sendable {
    func register(in registry: DependencyRegistry) async
}

// MARK: - Logging

public protocol DependencyLogger: Sendable {
    func log(_ message: String, level: OSLogType) async
    func recordResolutionFailure(for key: String, error: Error) async
}

public actor DefaultDependencyLogger: DependencyLogger {
    private let logger = Logger(subsystem: "com.weaver.di", category: "Dependency")

    public init() {}

    public func log(_ message: String, level: OSLogType) async {
        logger.log(level: level, "\(message)")
    }

    public func recordResolutionFailure(for key: String, error: Error) async {
        logger.error("Resolution failed for \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
}

// MARK: - AnyDependencyKey

public struct AnyDependencyKey: Hashable, Sendable, CustomStringConvertible {
    private let keyType: any DependencyKey.Type
    private let identifier: String
    private let objectID: ObjectIdentifier

    public init<Key: DependencyKey>(_ key: Key.Type) {
        self.keyType = key
        self.identifier = String(describing: key)
        self.objectID = ObjectIdentifier(key)
    }

    public init<T: Sendable>(_ valueType: T.Type) {
        self.keyType = _TemporaryKey<T>.self
        self.identifier = String(describing: valueType)
        self.objectID = ObjectIdentifier(_TemporaryKey<T>.self)
    }

    public var description: String { identifier }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(objectID)
    }

    public static func == (lhs: AnyDependencyKey, rhs: AnyDependencyKey) -> Bool {
        lhs.objectID == rhs.objectID
    }

    internal var originalType: any DependencyKey.Type { keyType }
}

private enum _TemporaryKey<T: Sendable>: DependencyKey {
    static var liveValue: T { fatalError("Temporary keys are not meant to be resolved directly") }
}

// MARK: - Graph Validation

public enum DependencyValidationResult: Sendable {
    case valid
    case missing([String])
    case circular([String])
}

public struct DependencyGraph {
    private let registrations: [AnyDependencyKey: DependencyRegistration]

    public init(registrations: [AnyDependencyKey: DependencyRegistration]) {
        self.registrations = registrations
    }

    public func validate() -> DependencyValidationResult {
        if let cycle = detectCycle() {
            return .circular(cycle)
        }

        let missing = locateMissingDependencies()
        if !missing.isEmpty {
            return .missing(missing)
        }

        return .valid
    }

    private func detectCycle() -> [String]? {
        var visiting: Set<AnyDependencyKey> = []
        var visited: Set<AnyDependencyKey> = []
        var stack: [AnyDependencyKey] = []

        func dfs(_ key: AnyDependencyKey) -> [String]? {
            if visiting.contains(key) {
                if let start = stack.firstIndex(of: key) {
                    let cycle = stack[start...] + [key]
                    return cycle.map { $0.description }
                }
                return nil
            }

            if visited.contains(key) { return nil }

            visiting.insert(key)
            stack.append(key)

            for dependency in registrations[key]?.dependencies ?? [] {
                if let cycle = dfs(dependency) {
                    return cycle
                }
            }

            _ = stack.popLast()
            visiting.remove(key)
            visited.insert(key)
            return nil
        }

        for key in registrations.keys {
            if let cycle = dfs(key) {
                return cycle
            }
        }
        return nil
    }

    private func locateMissingDependencies() -> [String] {
        var missing: [String] = []
        for (key, registration) in registrations {
            for dependency in registration.dependencies where registrations[dependency] == nil {
                missing.append("\(key.description) depends on unregistered \(dependency.description)")
            }
        }
        return missing
    }
}

// MARK: - DependencyRegistry

public actor DependencyRegistry {
    private var registrations: [AnyDependencyKey: DependencyRegistration] = [:]
    private let registryLogger = Logger(subsystem: "com.weaver.di", category: "DependencyRegistry")

    public init() {}

    public func register<Key: DependencyKey>(
        _ key: Key.Type,
        lifetime: DependencyLifetime = .singleton,
        dependsOn dependencies: [AnyDependencyKey] = [],
        factory: @escaping @Sendable (DependencyResolver) async throws -> Key.Value
    ) {
        let dependencySet = Set(dependencies)
        let anyKey = AnyDependencyKey(key)

        if registrations[anyKey] != nil {
            registryLogger.warning("Overwriting existing dependency registration for \(String(describing: key), privacy: .public)")
        }

        registrations[anyKey] = DependencyRegistration(
            lifetime: lifetime,
            factory: { resolver in try await factory(resolver) },
            keyName: String(describing: key),
            dependencies: dependencySet
        )
    }

    internal func merge(_ newRegistrations: [AnyDependencyKey: DependencyRegistration]) {
        registrations.merge(newRegistrations) { _, new in new }
    }

    public func allRegistrations() -> [AnyDependencyKey: DependencyRegistration] {
        registrations
    }
}

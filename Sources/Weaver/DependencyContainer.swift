// Sources/Weaver/DependencyContainer.swift

import Foundation

public actor DependencyContainer: DependencyResolver {
    private final class WeakReference {
        weak var object: AnyObject?
        init(_ object: AnyObject) { self.object = object }
    }

    private struct CachedSingleton: Sendable {
        private let storage: any Sendable
        private let type: Any.Type

        init<Value: Sendable>(_ value: Value) {
            self.storage = value
            self.type = Value.self
        }

        func value<Value>(as _: Value.Type) -> Value? {
            guard Value.self == type else { return nil }
            return storage as? Value
        }
    }

    private enum CacheEntry {
        case singleton(CachedSingleton)
        case weak(WeakReference)
    }

    private let registrations: [AnyDependencyKey: DependencyRegistration]
    private weak var parent: DependencyContainer?
    private let logger: DependencyLogger

    private var cache: [AnyDependencyKey: CacheEntry] = [:]
    private var pending: [AnyDependencyKey: Task<any Sendable, Error>] = [:]

    public init(
        registrations: [AnyDependencyKey: DependencyRegistration],
        parent: DependencyContainer? = nil,
        logger: DependencyLogger = DefaultDependencyLogger.shared
    ) {
        self.registrations = registrations
        self.parent = parent
        self.logger = logger
    }

    // MARK: - Public API

    public func resolve<Key: DependencyKey>(_ key: Key.Type) async throws -> Key.Value {
        let identifier = AnyDependencyKey(key)

        if let cached = await cachedValue(for: identifier, as: Key.self) {
            return cached
        }

        let produced = try await produceValue(for: identifier)

        guard let typed = produced as? Key.Value else {
            throw DependencyError.typeMismatch(
                expected: Key.Value.self,
                actual: type(of: produced),
                key: identifier.description
            )
        }

        return typed
    }

    // MARK: - Internal Helpers

    private func cachedValue<Key: DependencyKey>(
        for key: AnyDependencyKey,
        as _: Key.Type
    ) async -> Key.Value? {
        switch cache[key] {
        case .singleton(let cached):
            return cached.value(as: Key.Value.self)
        case .weak(let entry):
            if let object = entry.object as? Key.Value {
                return object
            }
            cache.removeValue(forKey: key)
            return nil
        case .none:
            if let parent {
                return await parent.cachedValue(for: key, as: Key.self)
            }
            return nil
        }
    }

    private func produceValue(for key: AnyDependencyKey) async throws -> any Sendable {
        if let task = pending[key] {
            return try await task.value
        }

        guard let registration = registrations[key] else {
            if let parent {
                return try await parent.produceValue(for: key)
            }
            throw DependencyError.unregisteredDependency(key: key.description)
        }

        let creation = Task<any Sendable, Error> { [weak self] in
            guard let self else { throw DependencyError.containerDeallocated }
            return try await registration.factory(self)
        }
        pending[key] = creation

        defer { pending.removeValue(forKey: key) }

        do {
            let value = try await creation.value
            try await cache(value, for: key, lifetime: registration.lifetime)
            return value
        } catch {
            await logger.recordResolutionFailure(for: registration.keyName, error: error)
            throw error
        }
    }

    private func cache(
        _ value: any Sendable,
        for key: AnyDependencyKey,
        lifetime: DependencyLifetime
    ) async throws {
        switch lifetime {
        case .singleton:
            cache[key] = .singleton(CachedSingleton(value))
        case .weakReference:
            guard let object = (value as AnyObject?) else {
                throw DependencyError.weakNonObject(key: key.description)
            }
            cache[key] = .weak(WeakReference(object))
        case .transient:
            cache.removeValue(forKey: key)
        }
    }

    // MARK: - Hierarchy

    public func makeChildContainer(_ modules: [DependencyModule]) async -> DependencyContainer {
        let registry = DependencyRegistry()
        for module in modules {
            await module.register(in: registry)
        }
        var merged = await registry.allRegistrations()
        merged.merge(registrations) { _, existing in existing }
        return DependencyContainer(registrations: merged, parent: self, logger: logger)
    }
}

// MARK: - Errors

public enum DependencyError: Error, CustomStringConvertible {
    case unregisteredDependency(key: String)
    case typeMismatch(expected: Any.Type, actual: Any.Type, key: String)
    case weakNonObject(key: String)
    case containerDeallocated

    public var description: String {
        switch self {
        case .unregisteredDependency(let key):
            return "Dependency for \(key) is not registered"
        case let .typeMismatch(expected, actual, key):
            return "Expected \(expected) but resolved \(actual) for \(key)"
        case .weakNonObject(let key):
            return "Weak lifetime requires class type for \(key)"
        case .containerDeallocated:
            return "Dependency container was deallocated before resolution finished"
        }
    }
}

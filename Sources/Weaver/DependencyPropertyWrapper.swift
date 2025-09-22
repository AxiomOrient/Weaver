// Sources/Weaver/DependencyPropertyWrapper.swift

import Foundation

@propertyWrapper
public struct DependencyValue<Key: DependencyKey>: Sendable {
    private let key: Key.Type

    public init(_ key: Key.Type) {
        self.key = key
    }

    public var wrappedValue: Accessor {
        Accessor(key: key)
    }

    public struct Accessor: Sendable {
        fileprivate let key: Key.Type

        public func callAsFunction() async throws -> Key.Value {
            try await Dependency.resolve(key)
        }

        public func require() async throws -> Key.Value {
            let resolver = try await Dependency.resolver()
            return try await resolver.resolve(key)
        }
    }
}

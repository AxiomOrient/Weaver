// Sources/Weaver/DependencyContextStore.swift
import Foundation

// MARK: - Dependency Context Store

public actor DependencyContextStore {
    public static let shared = DependencyContextStore()

    private enum TaskContextStorage {
        @TaskLocal static var scopedOverride: DependencyContext?
    }

    private var defaultContext: DependencyContext = .live

    private init() {}

    public func get() -> DependencyContext {
        if let scoped = TaskContextStorage.scopedOverride {
            return scoped
        }

        return defaultContext
    }

    public func set(_ value: DependencyContext) {
        defaultContext = value
    }

    public func reset() {
        defaultContext = .live
    }

    public func withContext<R: Sendable>(
        _ context: DependencyContext,
        operation: @Sendable () async throws -> R
    ) async rethrows -> R {
        try await TaskContextStorage.$scopedOverride.withValue(context) {
            try await operation()
        }
    }

}

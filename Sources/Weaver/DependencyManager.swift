// Sources/Weaver/DependencyManager.swift

import Foundation
import os

public actor DependencyManager {
    public static let shared = DependencyManager()

    private var kernel: DependencyKernel?
    private let logger: DependencyLogger

    private init(logger: DependencyLogger = DefaultDependencyLogger()) {
        self.logger = logger
    }

    public func bootstrap(with modules: [DependencyModule]) async throws {
        let kernel = DependencyKernel(modules: modules, logger: logger)
        try await kernel.build()
        self.kernel = kernel
    }

    public func reset() {
        kernel = nil
    }

    public func resolver() async throws -> DependencyResolver {
        guard let kernel else {
            throw DependencyKernelError.kernelNotReady
        }
        return try await kernel.ensureReady()
    }

    public func resolve<Key: DependencyKey>(_ key: Key.Type) async throws -> Key.Value {
        guard let kernel else {
            throw DependencyKernelError.kernelNotReady
        }
        return try await kernel.resolve(key)
    }

    public func currentState() async -> DependencyKernelState {
        guard let kernel else { return .idle }
        return await kernel.currentState()
    }
}

public enum Dependency {
    public static func bootstrap(with modules: [DependencyModule]) async throws {
        try await DependencyManager.shared.bootstrap(with: modules)
    }

    public static func resolve<Key: DependencyKey>(_ key: Key.Type) async throws -> Key.Value {
        let context = await Self.currentContext
        switch context {
        case .preview:
            return Key.previewValue
        case .test:
            return Key.testValue
        case .live:
            return try await DependencyManager.shared.resolve(key)
        }
    }

    public static func resolver() async throws -> DependencyResolver {
        try await DependencyManager.shared.resolver()
    }

    public static func state() async -> DependencyKernelState {
        await DependencyManager.shared.currentState()
    }

    public static func reset() async {
        await DependencyManager.shared.reset()
        await DependencyContextStore.shared.reset()
    }

    public static func withContext<R: Sendable>(
        _ context: DependencyContext,
        operation: @Sendable () async throws -> R
    ) async rethrows -> R {
        try await DependencyContextStore.shared.withContext(context, operation: operation)
    }

    // MARK: - Context Management

    public static var currentContext: DependencyContext {
        get async { await DependencyContextStore.shared.get() }
    }

    public static func setContext(_ context: DependencyContext) async {
        await DependencyContextStore.shared.set(context)
    }
}

// Sources/Weaver/DependencyKernel.swift

import Foundation
import os

public enum DependencyKernelState: Sendable {
    case idle
    case building
    case ready(DependencyContainer)
    case failed(Error)
}

public actor DependencyKernel: DependencyResolver {
    private let modules: [DependencyModule]
    private let logger: DependencyLogger
    private var state: DependencyKernelState = .idle
    private var container: DependencyContainer?
    private var buildTask: Task<DependencyContainer, Error>?

    public init(
        modules: [DependencyModule],
        logger: DependencyLogger = DefaultDependencyLogger()
    ) {
        self.modules = modules
        self.logger = logger
    }

    public func build() async throws {
        _ = try await ensureReady()
    }

    public func ensureReady() async throws -> DependencyContainer {
        if let existing = buildTask {
            return try await existing.value
        }

        switch state {
        case .ready(let container):
            return container
        case .failed(let error):
            throw DependencyKernelError.kernelFailed(error)
        case .building:
            if let existing = buildTask {
                return try await existing.value
            }
        case .idle:
            break
        }

        let task = Task { try await self.performBuild() }
        buildTask = task

        do {
            let container = try await task.value
            buildTask = nil
            return container
        } catch {
            buildTask = nil
            throw error
        }
    }

    public func resolve<Key: DependencyKey>(_ key: Key.Type) async throws -> Key.Value {
        let container = try await ensureReady()
        return try await container.resolve(key)
    }

    public func currentState() -> DependencyKernelState {
        state
    }

    // MARK: - Build implementation

    private func performBuild() async throws -> DependencyContainer {
        guard case .idle = state else {
            if case .ready(let container) = state { return container }
            if case .failed(let error) = state { throw DependencyKernelError.kernelFailed(error) }
            if let existing = buildTask { return try await existing.value }
            throw DependencyKernelError.kernelNotReady
        }
        state = .building
        await logger.log("Dependency kernel building", level: .info)

        let registry = DependencyRegistry()
        for module in modules {
            await module.register(in: registry)
        }

        let registrations = await registry.allRegistrations()
        let graph = DependencyGraph(registrations: registrations)

        switch graph.validate() {
        case .valid:
            break
        case .missing(let missing):
            let error = DependencyKernelError.missingDependencies(missing)
            state = .failed(error)
            await logger.log("Missing dependencies detected", level: .fault)
            throw error
        case .circular(let cycle):
            let error = DependencyKernelError.circularDependency(cycle)
            state = .failed(error)
            await logger.log("Circular dependency detected", level: .fault)
            throw error
        }

        let container = DependencyContainer(registrations: registrations, logger: logger)
        self.container = container
        state = .ready(container)
        await logger.log("Dependency kernel ready", level: .info)
        return container
    }
}

public enum DependencyKernelError: Error, CustomStringConvertible {
    case missingDependencies([String])
    case circularDependency([String])
    case kernelNotReady
    case kernelFailed(Error)

    public var description: String {
        switch self {
        case .missingDependencies(let missing):
            return "Missing dependencies: \(missing.joined(separator: ", "))"
        case .circularDependency(let cycle):
            return "Circular dependency: \(cycle.joined(separator: " -> "))"
        case .kernelNotReady:
            return "Dependency kernel is not ready"
        case .kernelFailed(let error):
            return "Dependency kernel failed: \(error.localizedDescription)"
        }
    }
}

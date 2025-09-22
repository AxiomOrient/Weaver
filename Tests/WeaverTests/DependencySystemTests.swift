// Tests/WeaverTests/DependencySystemTests.swift

import Foundation
import Testing

@testable import Weaver

// MARK: - Test Utilities

actor FactoryCallCounter {
    private var value: Int = 0

    func increment() async {
        value += 1
    }

    func count() async -> Int {
        value
    }
}

struct SingletonService: Sendable {
    let id = UUID()
}

final class WeakService: @unchecked Sendable {
    let id = UUID()
}

struct SingletonServiceKey: DependencyKey {
    static let liveValue = SingletonService()
    static let previewValue = SingletonService()
    static let testValue = SingletonService()
}

struct WeakServiceKey: DependencyKey {
    static let liveValue = WeakService()
    static let previewValue = WeakService()
    static let testValue = WeakService()
}

struct PreviewOnlyKey: DependencyKey {
    static let liveValue = "live"
    static let previewValue = "preview"
    static let testValue = "test"
}

struct ConcurrencyModule: DependencyModule {
    let counter: FactoryCallCounter

    func register(in registry: DependencyRegistry) async {
        await registry.register(SingletonServiceKey.self, lifetime: .singleton) { _ in
            await counter.increment()
            return SingletonService()
        }
    }
}

struct WeakModule: DependencyModule {
    func register(in registry: DependencyRegistry) async {
        await registry.register(WeakServiceKey.self, lifetime: .weakReference) { _ in
            WeakService()
        }
    }
}

// MARK: - Test Suite

@Suite("Dependency System", .serialized, .tags(.unit, .core, .critical))
struct DependencySystemTests {

    @Test("Kernel bootstrap resolves singleton once", .tags(.kernel, .unit, .fast))
    func testSingletonResolutionAfterBootstrap() async throws {
        await Dependency.reset()

        let counter = FactoryCallCounter()
        try await Dependency.bootstrap(with: [ConcurrencyModule(counter: counter)])

        let serviceA = try await Dependency.resolve(SingletonServiceKey.self)
        let serviceB = try await Dependency.resolve(SingletonServiceKey.self)

        let factoryCount = await counter.count()

        #expect(serviceA.id == serviceB.id, "Singleton lifetime should reuse instance")
        #expect(factoryCount == 1, "Factory must run exactly once for singleton dependency")

        await Dependency.reset()
    }

    @Test("Dependency graph flags missing registrations", .tags(.unit, .core, .fast))
    func testDependencyGraphDetectsMissingEntries() async {
        let registry = DependencyRegistry()
        await registry.register(SingletonServiceKey.self, dependsOn: [AnyDependencyKey(WeakServiceKey.self)]) { _ in
            SingletonService()
        }

        let graph = DependencyGraph(registrations: await registry.allRegistrations())
        let result = graph.validate()

        if case let .missing(missing) = result {
            #expect(missing.contains { $0.contains("WeakServiceKey") })
        } else {
            #expect(Bool(false), "Graph validation should report missing dependency")
        }
    }

    @Test("Concurrent resolutions reuse pending task", .tags(.concurrency, .kernel, .fast))
    func testConcurrentResolutionUsesSingleFactoryCall() async throws {
        await Dependency.reset()

        let counter = FactoryCallCounter()
        try await Dependency.bootstrap(with: [ConcurrencyModule(counter: counter)])

        async let valueA = Dependency.resolve(SingletonServiceKey.self)
        async let valueB = Dependency.resolve(SingletonServiceKey.self)
        async let valueC = Dependency.resolve(SingletonServiceKey.self)

        let serviceA = try await valueA
        let serviceB = try await valueB
        let serviceC = try await valueC

        let ids = Set([serviceA.id, serviceB.id, serviceC.id])
        let factoryCount = await counter.count()

        #expect(ids.count == 1, "All concurrent resolutions must receive identical instance")
        #expect(factoryCount == 1, "Factory should execute once despite concurrency")

        await Dependency.reset()
    }

    @Test("Preview context returns preview value without kernel", .tags(.environment, .unit, .fast))
    func testContextFallback() async throws {
        await Dependency.reset()
        let value = try await Dependency.withContext(.preview) {
            try await Dependency.resolve(PreviewOnlyKey.self)
        }
        #expect(value == "preview")
        await Dependency.reset()
    }

    @Test("Weak lifetime recreates object after deallocation", .tags(.weak, .unit, .memory))
    func testWeakLifetimeRecreation() async throws {
        await Dependency.reset()

        try await Dependency.bootstrap(with: [WeakModule()])

        var strongReference: WeakService? = try await Dependency.resolve(WeakServiceKey.self)
        weak var weakReference = strongReference
        let firstIdentifier = strongReference?.id

        #expect(weakReference != nil)
        strongReference = nil

        try await waitUntilWeakReferenceReleased(weakReference)

        let newInstance = try await Dependency.resolve(WeakServiceKey.self)
        #expect(weakReference == nil, "Original weak instance should be released")
        #expect(newInstance.id != firstIdentifier, "New resolve should create a fresh instance")

        await Dependency.reset()
    }

    @Test("resolveLive() bypasses test context", .tags(.environment, .unit, .fast))
    func testResolveLiveBypassesTestContext() async throws {
        await Dependency.reset()
        let counter = FactoryCallCounter()
        try await Dependency.bootstrap(with: [ConcurrencyModule(counter: counter)])

        let (liveResolved, testResolved) = try await Dependency.withContext(.test) {
            let dependency = DependencyValue(SingletonServiceKey.self)

            // resolveLive() should bypass the context and hit the container
            let live = try await dependency.wrappedValue.resolveLive()

            // Standard resolve() should use the context and return the static .testValue
            let test = try await Dependency.resolve(SingletonServiceKey.self)

            return (live, test)
        }

        let factoryCount = await counter.count()

        #expect(factoryCount == 1, "Factory for live value should be called exactly once")
        #expect(liveResolved.id != testResolved.id, "resolveLive() must return a different instance from the container, not the static testValue")

        await Dependency.reset()
    }
}

private func waitUntilWeakReferenceReleased(_ reference: WeakService?) async throws {
    for _ in 0..<50 {
        if reference == nil { return }
        try await Task.sleep(nanoseconds: 100_000) // 0.1ms
    }
    fatalError("Weak reference was not released after 50 attempts")
}

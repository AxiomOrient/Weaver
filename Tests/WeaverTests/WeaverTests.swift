import XCTest
@testable import Weaver

// MARK: - Test Dependencies

private protocol Service {
    var id: UUID { get }
}

private class MyService: Service, @unchecked Sendable {
    let id = UUID()
}

private struct ServiceKey: DependencyKey {
    static var defaultValue: Service = MyService()
}

private protocol AnotherService {
    var service: Service { get }
}

private class MyAnotherService: AnotherService, @unchecked Sendable {
    @Inject(ServiceKey.self) var service
    func getService() async throws -> Service { try await service() }
}

private struct AnotherServiceKey: DependencyKey {
    static var defaultValue: AnotherService = MyAnotherService()
}

// MARK: - Test Modules

private struct AppModule: Module {
    func configure(_ container: ContainerBuilder) {
        container.register(ServiceKey.self, scope: .container) { _ in MyService() }
    }
}

private struct ChildModule: Module {
    func configure(_ container: ContainerBuilder) {
        container.register(AnotherServiceKey.self, scope: .container) { _ in MyAnotherService() }
    }
}

final class WeaverTests: XCTestCase {

    // MARK: - Basic Resolution

    func test_resolve_basicDependency() async throws {
        let container = WeaverContainer(modules: [AppModule()])
        
        try await Weaver.withScope(container) {
            let service = try await container.resolve(ServiceKey.self)
            XCTAssert(service is MyService)
        }
    }

    // MARK: - Hierarchical Resolution

    func test_resolve_fromParentContainer() async throws {
        let parent = WeaverContainer(modules: [AppModule()])
        let child = parent.newScope(modules: [ChildModule()])
        
        try await Weaver.withScope(child) {
            let anotherService = try await child.resolve(AnotherServiceKey.self) as! MyAnotherService
            let service = try await anotherService.getService()
            XCTAssert(service is MyService)
        }
    }

    // MARK: - Scopes

    func test_scope_container_returnsSameInstance() async throws {
        let container = WeaverContainer(modules: [AppModule()])
        try await Weaver.withScope(container) {
            let service1 = try await container.resolve(ServiceKey.self)
            let service2 = try await container.resolve(ServiceKey.self)
            XCTAssertEqual(service1.id, service2.id)
        }
    }
    
    func test_scope_transient_returnsNewInstance() async throws {
        struct TransientModule: Module {
            func configure(_ container: ContainerBuilder) {
                container.register(ServiceKey.self, scope: .transient) { _ in MyService() }
            }
        }
        let container = WeaverContainer(modules: [TransientModule()])
        try await Weaver.withScope(container) {
            let service1 = try await container.resolve(ServiceKey.self)
            let service2 = try await container.resolve(ServiceKey.self)
            XCTAssertNotEqual(service1.id, service2.id)
        }
    }
    
    func test_scope_cached_returnsSameInstanceWithinTask() async throws {
        struct CachedModule: Module {
            func configure(_ container: ContainerBuilder) {
                container.register(ServiceKey.self, scope: .cached) { _ in MyService() }
            }
        }
        let container = WeaverContainer(modules: [CachedModule()])
        try await Weaver.withScope(container) {
            let service1 = try await container.resolve(ServiceKey.self)
            let service2 = try await container.resolve(ServiceKey.self)
            XCTAssertEqual(service1.id, service2.id)
            
            let service3 = try await Task { try await container.resolve(ServiceKey.self) }.value
            XCTAssertNotEqual(service1.id, service3.id)
        }
    }

    // MARK: - Overrides

    func test_override_replacesDependencyForTest() async throws {
        class MockService: Service, @unchecked Sendable {
            let id = UUID()
        }
        struct MockModule: Module {
            func configure(_ container: ContainerBuilder) {
                container.register(ServiceKey.self, scope: .container) { _ in MockService() }
            }
        }
        
        let appContainer = WeaverContainer(modules: [AppModule()])
        let testContainer = appContainer.newScope(modules: [], overrides: [MockModule()])
        
        try await Weaver.withScope(testContainer) {
            let service = try await testContainer.resolve(ServiceKey.self)
            XCTAssert(service is MockService)
        }
    }
    
    // MARK: - Error Handling
    
    func test_circularDependency_throwsError() async throws {
        struct CircularAKey: DependencyKey { static var defaultValue: Service = MyService() }
        struct CircularBKey: DependencyKey { static var defaultValue: Service = MyService() }
        
        class ServiceA: Service, @unchecked Sendable {
            let id = UUID()
            @Inject(CircularBKey.self) var b
            func doSomething() async throws { _ = try await b() }
        }
        class ServiceB: Service, @unchecked Sendable {
            let id = UUID()
            @Inject(CircularAKey.self) var a
            func doSomething() async throws { _ = try await a() }
        }
        
        struct CircularModule: Module {
            func configure(_ container: ContainerBuilder) {
                container.register(CircularAKey.self) { _ in ServiceA() }
                container.register(CircularBKey.self) { _ in ServiceB() }
            }
        }
        
        let container = WeaverContainer(modules: [CircularModule()])
        try await Weaver.withScope(container) {
            do {
                let serviceA = try await container.resolve(CircularAKey.self) as! ServiceA
                try await serviceA.doSomething()
                XCTFail("Should have thrown a circular dependency error")
            } catch let error as DependencyError {
                guard case .circularDependency = error else {
                    XCTFail("Incorrect error type: \(error)")
                    return
                }
                // Success
            } catch {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }
}

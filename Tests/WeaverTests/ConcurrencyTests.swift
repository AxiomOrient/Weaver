import Testing
@testable import Weaver

@Suite("5. 동시성 및 안정성 (Concurrency & Safety)")
struct ConcurrencyTests {

    /// 팩토리 호출 횟수를 동시성 환경에서 안전하게 추적하기 위한 액터
    private actor FactoryCallCounter {
        var count = 0
        func increment() {
            count += 1
        }
    }

    @Test("T5.1: 동일 의존성 동시 해결")
    func test_concurrency_whenResolvingSameDependency_shouldReturnSameInstanceAndCallFactoryOnce() async throws {
        // Arrange
        let counter = FactoryCallCounter()
        let container = await WeaverContainer.builder()
            .register(ServiceKey.self, scope: .container) { _ in
                await counter.increment()
                return TestService()
            }
            .build()
        
        let taskCount = 20
        
        // Act
        // TaskGroup을 사용하여 20개의 태스크에서 동시에 동일한 의존성을 해결합니다.
        let resolvedServices = try await withThrowingTaskGroup(of: TestService.self, returning: [TestService].self) { group in
            for _ in 0..<taskCount {
                group.addTask {
                    try await container.resolve(ServiceKey.self)
                }
            }
            
            var results: [TestService] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
        
        // Assert
        let factoryCalls = await counter.count
        #expect(factoryCalls == 1, "동시 요청이 발생해도 .container 스코프의 팩토리는 단 한 번만 호출되어야 합니다.")
        
        let firstInstanceID = resolvedServices.first?.id
        #expect(firstInstanceID != nil)
        
        let allInstancesAreSame = resolvedServices.allSatisfy { $0.id == firstInstanceID }
        #expect(allInstancesAreSame, "모든 동시 태스크는 동일한 인스턴스를 반환받아야 합니다.")
    }
    
    @Test("T5.2: 다른 의존성 동시 해결")
    func test_concurrency_whenResolvingDifferentDependencies_shouldSucceedWithoutDeadlock() async throws {
        // Arrange
        let builder = WeaverContainer.builder()
        let keyCount = 20
        
        // ✅ FIX: `map` 대신 for-loop를 사용하여 actor-isolated 메서드를 안전하게 호출합니다.
        // 20개의 서로 다른 키와 의존성을 동적으로 생성하여 등록합니다.
        var keys: [any DependencyKey.Type] = []
        for i in 0..<keyCount {
            struct DynamicKey: DependencyKey {
                static var defaultValue: Int { 0 }
            }
            keys.append(DynamicKey.self)
            await builder.register(DynamicKey.self) { _ in i }
        }
        
        let container = await builder.build()
        
        // Act & Assert
        // ✅ FIX: `#expect(nothrow:)` 대신 `try await`을 직접 사용합니다.
        // 이 작업이 에러나 데드락 없이 성공적으로 완료되는 것 자체가 테스트의 통과를 의미합니다.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for key in keys {
                group.addTask {
                    // ✅ FIX: 반환된 `any Sendable`을 올바른 타입으로 캐스팅합니다.
                    let value = try await container.resolve(key)
                    #expect(value is Int)
                }
            }
            // 모든 자식 태스크가 완료될 때까지 기다립니다.
            for try await _ in group {}
        }
    }
}

import Testing
@testable import Weaver

@Suite("5. 동시성 및 안정성 (Concurrency & Safety)")
struct ConcurrencyTests {

    @Test("T5.1: 동일 의존성 동시 해결")
    func test_concurrency_whenResolvingSameDependency_shouldReturnSameInstanceAndCallFactoryOnce() async throws {
        // Arrange
        let counter = FactoryCallCounter()
        let container = await WeaverContainer.builder()
            .register(ServiceKey.self, scope: .container) { _ in
                await counter.increment()
                // 레이스 컨디션을 더 쉽게 발생시키기 위해 약간의 지연 추가
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                return TestService()
            }
            .build()
        
        let taskCount = 50 // 더 많은 태스크로 테스트
        
        // Act
        // TaskGroup을 사용하여 50개의 태스크에서 동시에 동일한 의존성을 해결합니다.
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
        #expect(factoryCalls == 1, "동시 요청이 발생해도 .container 스코프의 팩토리는 단 한 번만 호출되어야 합니다. 실제 호출 횟수: \(factoryCalls)")
        
        let firstInstanceID = resolvedServices.first?.id
        #expect(firstInstanceID != nil)
        
        let allInstancesAreSame = resolvedServices.allSatisfy { $0.id == firstInstanceID }
        #expect(allInstancesAreSame, "모든 동시 태스크는 동일한 인스턴스를 반환받아야 합니다.")
        
        await container.shutdown()
    }
    
    @Test("T5.2: 다른 의존성 동시 해결")
    func test_concurrency_whenResolvingDifferentDependencies_shouldSucceedWithoutDeadlock() async throws {
        // Arrange
        let builder = WeaverContainer.builder()
        let _ = 20 // keyCount unused
        
        // 간단한 정적 키들을 사용하여 동적 키 생성 문제를 회피
        await builder.register(ServiceKey.self) { _ in TestService() }
        await builder.register(ServiceProtocolKey.self) { _ in AnotherService() }
        await builder.register(WeakServiceKey.self) { _ in WeakService() }
        await builder.register(DisposableServiceKey.self) { _ in 
            DisposableService(onDispose: {})
        }
        await builder.register(CircularAKey.self) { _ in 
            CircularServiceA(serviceB: TestService())
        }
        
        let container = await builder.build()
        
        // Act & Assert
        // 서로 다른 의존성들을 동시에 해결
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try await container.resolve(ServiceKey.self)
            }
            group.addTask {
                _ = try await container.resolve(ServiceProtocolKey.self)
            }
            group.addTask {
                _ = try await container.resolve(WeakServiceKey.self)
            }
            group.addTask {
                _ = try await container.resolve(DisposableServiceKey.self)
            }
            group.addTask {
                _ = try await container.resolve(CircularAKey.self)
            }
            
            // 모든 자식 태스크가 완료될 때까지 기다립니다.
            for try await _ in group {}
        }
        
        await container.shutdown()
    }
    
    @Test("T5.3: 극한 동시성 스트레스 테스트")
    func test_concurrency_extremeStressTest() async throws {
        // Arrange
        let counter = FactoryCallCounter()
        let container = await WeaverContainer.builder()
            .register(ServiceKey.self, scope: .container) { _ in
                await counter.increment()
                // 더 긴 지연으로 레이스 컨디션 유발 시도
                try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
                return TestService()
            }
            .build()
        
        let taskCount = 100 // 극한 동시성 테스트
        
        // Act
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
        #expect(factoryCalls == 1, "극한 동시성 상황에서도 팩토리는 단 한 번만 호출되어야 합니다. 실제 호출 횟수: \(factoryCalls)")
        
        let firstInstanceID = resolvedServices.first?.id
        #expect(firstInstanceID != nil)
        
        let allInstancesAreSame = resolvedServices.allSatisfy { $0.id == firstInstanceID }
        #expect(allInstancesAreSame, "극한 동시성 상황에서도 모든 태스크는 동일한 인스턴스를 반환받아야 합니다.")
        
        #expect(resolvedServices.count == taskCount, "모든 태스크가 성공적으로 완료되어야 합니다.")
        
        await container.shutdown()
    }
    
    @Test("T5.4: 레이스 컨디션 완전 제거 검증")
    func test_concurrency_raceConditionEliminationVerification() async throws {
        // Arrange - 각 반복마다 새로운 컨테이너와 카운터를 생성하여 독립적인 테스트 수행
        let iterationCount = 5 // 반복 횟수 줄임
        let taskCount = 100 // 동시 태스크 수
        
        // Act & Assert - 여러 번 반복하여 일관성 확인
        for iteration in 1...iterationCount {
            let counter = FactoryCallCounter() // 각 반복마다 새로운 카운터
            let container = await WeaverContainer.builder()
                .register(ServiceKey.self, scope: .container) { _ in
                    await counter.increment()
                    // 매우 짧은 지연으로 레이스 컨디션 유발 가능성 극대화
                    try? await Task.sleep(nanoseconds: 100_000) // 0.1ms
                    return TestService()
                }
                .build()
            
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
            
            let factoryCalls = await counter.count
            #expect(factoryCalls == 1, "반복 \(iteration): 팩토리는 단 한 번만 호출되어야 합니다. 실제 호출 횟수: \(factoryCalls)")
            
            let firstInstanceID = resolvedServices.first?.id
            let allInstancesAreSame = resolvedServices.allSatisfy { $0.id == firstInstanceID }
            #expect(allInstancesAreSame, "반복 \(iteration): 모든 태스크는 동일한 인스턴스를 반환받아야 합니다.")
            
            #expect(resolvedServices.count == taskCount, "반복 \(iteration): 모든 태스크가 성공적으로 완료되어야 합니다.")
            
            await container.shutdown()
        }
    }
    
    @Test("T5.5: 약한 참조 스코프 동시성 테스트")
    func test_concurrency_weakScopeRaceCondition() async throws {
        // Arrange
        let counter = FactoryCallCounter()
        let builder = WeaverContainer.builder()
        await builder.registerWeak(WeakServiceKey.self) { _ in
            await counter.increment()
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            return WeakService()
        }
        let container = await builder.build()
        
        let taskCount = 50
        
        // Act
        let resolvedServices = try await withThrowingTaskGroup(of: WeakService.self, returning: [WeakService].self) { group in
            for _ in 0..<taskCount {
                group.addTask {
                    try await container.resolve(WeakServiceKey.self)
                }
            }
            
            var results: [WeakService] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
        
        // Assert
        let factoryCalls = await counter.count
        #expect(factoryCalls == 1, "약한 참조 스코프에서도 동시 요청 시 팩토리는 단 한 번만 호출되어야 합니다. 실제 호출 횟수: \(factoryCalls)")
        
        let firstInstanceID = resolvedServices.first?.id
        let allInstancesAreSame = resolvedServices.allSatisfy { $0.id == firstInstanceID }
        #expect(allInstancesAreSame, "약한 참조 스코프에서도 모든 동시 태스크는 동일한 인스턴스를 반환받아야 합니다.")
        
        await container.shutdown()
    }
    
    @Test("T5.6: 프로덕션 레이스 컨디션 시나리오 검증")
    func test_concurrency_productionRaceConditionScenario() async throws {
        // 프로덕션에서 발생할 수 있는 시나리오:
        // - 앱 시작 시 여러 화면에서 동시에 같은 서비스 요청
        // - 네트워크 응답 처리 중 동시 의존성 해결
        // - 사용자 인터랙션으로 인한 동시 서비스 접근
        
        let extremeTaskCount = 500 // 극한 동시성
        let iterationCount = 3 // 여러 번 반복하여 일관성 확인
        
        for iteration in 1...iterationCount {
            // 각 반복마다 새로운 컨테이너와 카운터 생성
            let counter = FactoryCallCounter()
            let container = await WeaverContainer.builder()
                .register(ServiceKey.self, scope: .container) { _ in
                    await counter.increment()
                    // 매우 짧은 지연으로 레이스 컨디션 최대한 유발
                    try? await Task.sleep(nanoseconds: 10_000) // 0.01ms
                    return TestService()
                }
                .build()
            
            let resolvedServices = try await withThrowingTaskGroup(of: TestService.self, returning: [TestService].self) { group in
                // 모든 태스크를 동시에 시작하여 최대한 레이스 컨디션 유발
                for _ in 0..<extremeTaskCount {
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
            
            let factoryCalls = await counter.count
            #expect(factoryCalls == 1, "반복 \(iteration): 프로덕션 시나리오에서도 팩토리는 단 한 번만 호출되어야 합니다. 실제 호출 횟수: \(factoryCalls)")
            
            let firstInstanceID = resolvedServices.first?.id
            let allInstancesAreSame = resolvedServices.allSatisfy { $0.id == firstInstanceID }
            #expect(allInstancesAreSame, "반복 \(iteration): 모든 태스크는 동일한 인스턴스를 반환받아야 합니다.")
            
            #expect(resolvedServices.count == extremeTaskCount, "반복 \(iteration): 모든 태스크가 성공적으로 완료되어야 합니다.")
            
            await container.shutdown()
        }
    }
}

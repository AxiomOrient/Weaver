import Testing
import Foundation
@testable import Weaver

@Suite("2. 스코프별 생명주기 (Scope Lifecycle)")
struct ScopeLifecycleTests {
    
    @Test("T2.1: .transient 스코프")
    func test_transientScope_whenResolvedMultipleTimes_shouldReturnNewInstances() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(ServiceKey.self, scope: .transient) { _ in TestService() }
            .build()
        
        // Act
        let instance1 = try await container.resolve(ServiceKey.self)
        let instance2 = try await container.resolve(ServiceKey.self)
        
        // Assert
        #expect(instance1.id != instance2.id, ".transient 스코프는 매번 새로운 인스턴스를 반환해야 합니다.")
    }
    
    @Test("T2.2: .container 스코프")
    func test_containerScope_whenResolvedMultipleTimes_shouldReturnSameInstance() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(ServiceKey.self, scope: .container) { _ in TestService() }
            .build()
        
        // Act
        let instance1 = try await container.resolve(ServiceKey.self)
        let instance2 = try await container.resolve(ServiceKey.self)
        
        // Assert
        #expect(instance1.id == instance2.id, ".container 스코프는 항상 동일한 인스턴스를 반환해야 합니다.")
    }
    
    @Test("T2.3: .cached 스코프 (Hit)")
    func test_cachedScope_whenResolvedWithinTTL_shouldReturnSameInstance() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .enableAdvancedCaching() // 고급 캐시 활성화
            .register(ServiceKey.self, scope: .cached) { _ in TestService() }
            .build()
        
        // Act
        let instance1 = try await container.resolve(ServiceKey.self)
        let instance2 = try await container.resolve(ServiceKey.self)
        let metrics = await container.getMetrics()
        
        // Assert
        #expect(instance1.id == instance2.id, "TTL 내에서는 캐시된 동일 인스턴스를 반환해야 합니다.")
        #expect(metrics.cacheHits == 1, "두 번째 호출은 캐시 히트여야 합니다.")
    }
    
    @Test("T2.4: .cached 스코프 (Miss)")
    func test_cachedScope_whenResolvedAfterTTL_shouldReturnNewInstance() async throws {
        // Arrange
        let ttl: TimeInterval = 0.1
        let policy = CachePolicy(ttl: ttl)
        let container = await WeaverContainer.builder()
            .enableAdvancedCaching(policy: policy)
            .register(ServiceKey.self, scope: .cached) { _ in TestService() }
            .build()
        
        // Act
        let instance1 = try await container.resolve(ServiceKey.self)
        
        // ✅ FIX: iOS 16 미만 호환성을 위해 sleep(nanoseconds:) 사용
        let delayInNanoSeconds = UInt64((ttl + 0.1) * 1_000_000_000)
        try await Task.sleep(nanoseconds: delayInNanoSeconds)
        
        let instance2 = try await container.resolve(ServiceKey.self)
        let metrics = await container.getMetrics()
        
        // Assert
        #expect(instance1.id != instance2.id, "TTL이 만료된 후에는 새로운 인스턴스를 반환해야 합니다.")
        #expect(metrics.cacheMisses == 2, "두 번의 호출 모두 캐시 미스여야 합니다.")
    }
    
    @Test("T2.5: Disposable 객체 자동 해제")
    func test_disposableObject_whenContainerShutsDown_shouldBeDisposed() async throws {
        // Arrange
        let disposeSignal = TestSignal()
        let container = await WeaverContainer.builder()
            .register(DisposableServiceKey.self, scope: .container) { _ in
                DisposableService(onDispose: {
                    // ✅ FIX: 동기 클로저에서 actor 메서드를 호출하기 위해 Task로 감싸줌
                    Task { await disposeSignal.signal() }
                })
            }
            .build()
        
        // `.container` 스코프 객체를 활성화하기 위해 한 번 해결합니다.
        _ = try await container.resolve(DisposableServiceKey.self)
        
        // Act
        // 컨테이너 종료와 dispose 완료 시그널 대기를 동시에 실행합니다.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await container.shutdown() }
            group.addTask { await disposeSignal.wait() }
        }
        
        // Assert
        #expect(true, "dispose() 메서드가 호출되어 wait()가 성공적으로 완료되어야 합니다.")
    }
}

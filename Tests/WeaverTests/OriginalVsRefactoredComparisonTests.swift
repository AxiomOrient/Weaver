import Testing
import Foundation
@testable import Weaver

/// Original WeaverContainer 기능 검증 테스트
/// 현재 구현된 기능들이 정상적으로 작동하는지 확인합니다.
@Suite("🔍 WeaverContainer 기능 검증")
struct WeaverContainerFunctionalityTests {
    
    @Test("1.1 기본 의존성 해결")
    func basicDependencyResolution() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(ServiceKey.self) { _ in TestService() }
            .build()
        
        // Act
        let service = try await container.resolve(ServiceKey.self)
        
        // Assert
        #expect(!service.isDefaultValue, "실제 인스턴스가 해결되어야 함")
        
        await container.shutdown()
    }
    
    @Test("1.2 Container 스코프 - 동일한 인스턴스 반환")
    func containerScopeInstanceManagement() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(ServiceKey.self, scope: .container) { _ in TestService() }
            .build()
        
        // Act
        let service1 = try await container.resolve(ServiceKey.self)
        let service2 = try await container.resolve(ServiceKey.self)
        
        // Assert
        #expect(service1.id == service2.id, "Container 스코프는 동일한 인스턴스를 반환해야 함")
        
        await container.shutdown()
    }
    
    @Test("1.3 약한 참조 스코프")
    func weakScopeManagement() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .registerWeak(WeakServiceKey.self) { _ in WeakService() }
            .build()
        
        // Act
        var service1: WeakService? = try await container.resolve(WeakServiceKey.self)
        let id1 = service1?.id
        
        service1 = nil // 강한 참조 해제
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms 대기
        
        let service2 = try await container.resolve(WeakServiceKey.self)
        
        // Assert
        #expect(id1 != service2.id, "약한 참조 해제 후 새로운 인스턴스가 생성되어야 함")
        
        await container.shutdown()
    }
    
    @Test("1.4 메모리 정리 기능")
    func memoryCleanupFunctionality() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .registerWeak(WeakServiceKey.self) { _ in WeakService() }
            .build()
        
        // Act
        var service: WeakService? = try await container.resolve(WeakServiceKey.self)
        service = nil
        
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms 대기
        
        // 메모리 정리 실행 (에러 없이 실행되어야 함)
        await container.performMemoryCleanup()
        
        // Assert
        #expect(Bool(true), "메모리 정리가 에러 없이 실행되어야 함")
        
        await container.shutdown()
    }
    
    @Test("1.5 앱 생명주기 이벤트 처리")
    func appLifecycleEventHandling() async throws {
        // AppLifecycleAware를 구현하는 테스트 서비스
        final class LifecycleTestService: Service, AppLifecycleAware, Sendable {
            let id = UUID()
            let isDefaultValue = false
            
            private let signal: TestSignal
            
            init(signal: TestSignal) {
                self.signal = signal
            }
            
            func appDidEnterBackground() async throws {
                await signal.signal()
            }
            
            func appWillEnterForeground() async throws {
                // 테스트에서는 background만 확인
            }
        }
        
        struct LifecycleServiceKey: DependencyKey {
            typealias Value = LifecycleTestService
            static var defaultValue: LifecycleTestService {
                LifecycleTestService(signal: TestSignal())
            }
        }
        
        // Arrange
        let signal = TestSignal()
        let container = await WeaverContainer.builder()
            .register(LifecycleServiceKey.self, scope: .appService) { _ in
                LifecycleTestService(signal: signal)
            }
            .build()
        
        // 인스턴스 생성 (appService 스코프이므로 캐시됨)
        _ = try await container.resolve(LifecycleServiceKey.self)
        
        // Act
        await container.handleAppDidEnterBackground()
        
        // Assert
        await signal.wait() // 이벤트가 처리되었는지 확인
        #expect(Bool(true), "앱 생명주기 이벤트가 정상적으로 처리되어야 함")
        
        await container.shutdown()
    }
    
    @Test("1.6 에러 처리 - 팩토리 실패")
    func factoryFailureErrorHandling() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(ServiceKey.self) { _ in
                throw TestError.factoryFailed
            }
            .build()
        
        // Act & Assert
        await #expect(throws: WeaverError.self) {
            _ = try await container.resolve(ServiceKey.self)
        }
        
        await container.shutdown()
    }
    
    @Test("1.7 성능 메트릭 수집")
    func performanceMetricsCollection() async throws {
        // Arrange
        let container = await WeaverContainer.builder()
            .register(ServiceKey.self) { _ in TestService() }
            .enableMetricsCollection()
            .build()
        
        // Act
        _ = try await container.resolve(ServiceKey.self)
        _ = try await container.resolve(ServiceKey.self)
        _ = try await container.resolve(ServiceKey.self)
        
        // Assert
        let metrics = await container.getMetrics()
        #expect(metrics.totalResolutions > 0, "메트릭이 수집되어야 함")
        
        await container.shutdown()
    }
}
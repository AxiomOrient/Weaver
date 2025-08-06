// Tests/WeaverTests/WeaverKernelTests.swift

import Testing
import Foundation
@testable import Weaver

/// `WeaverKernel` (LifecycleManager + SafeResolver)의 통합 테스트 스위트입니다.
/// DevPrinciples Article 11에 따라 커널의 핵심 기능을 체계적으로 검증합니다.
@Suite("WeaverKernel Integration Tests")
struct WeaverKernelTests {
    
    // MARK: - Test Dependencies
    
    struct TestModule: Module {
        func configure(_ builder: WeaverBuilder) async {
            await builder.register(ServiceKey.self) { _ in
                TestService(isDefaultValue: false)
            }
        }
    }
    
    struct FailingModule: Module {
        func configure(_ builder: WeaverBuilder) async {
            await builder.register(ServiceKey.self) { _ in
                throw TestError.factoryFailed
            }
        }
    }
    
    // MARK: - Lifecycle Management Tests
    
    @Test("커널 생명주기 - idle → configuring → warmingUp → ready")
    func kernelLifecycleProgression() async throws {
        // Arrange
        let kernel = DefaultWeaverKernel(modules: [TestModule()])
        var receivedStates: [LifecycleState] = []
        
        // Act: 상태 스트림 구독
        let streamTask = Task {
            for await state in await kernel.stateStream {
                receivedStates.append(state)
                if case .ready = state {
                    break
                }
            }
        }
        
        await kernel.build()
        await streamTask.value
        
        // Assert: 상태 전환 순서 검증
        #expect(receivedStates.count >= 2)
        #expect(receivedStates[0] == .idle)
        #expect(receivedStates[1] == .configuring)
        
        let lastState = receivedStates.last!
        if case .ready = lastState {
            // 성공
        } else {
            Issue.record("최종 상태가 ready가 아님: \(lastState)")
        }
        
        await kernel.shutdown()
    }
    
    @Test("build() 메서드 멱등성 - 중복 호출해도 한 번만 실행")
    func buildIdempotency() async throws {
        // Arrange
        let kernel = DefaultWeaverKernel(modules: [TestModule()])
        
        // Act: 동시에 여러 번 build 호출
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    await kernel.build()
                }
            }
        }
        
        // Assert: 빌드 완료 확인
        let currentState = await kernel.currentState
        if case .ready = currentState {
            // 성공
        } else if case .warmingUp(let progress) = currentState, progress >= 1.0 {
            // warmingUp 완료 상태도 허용
        } else {
            Issue.record("빌드 후 예상하지 못한 상태: \(currentState)")
        }
        
        await kernel.shutdown()
    }
    
    @Test("shutdown() - 리소스 해제 및 상태 전환")
    func shutdownCleansUpResources() async throws {
        // Arrange
        let kernel = DefaultWeaverKernel(modules: [TestModule()])
        await kernel.build()
        _ = try await kernel.waitForReady(timeout: 1.0)
        
        // Act
        await kernel.shutdown()
        
        // Assert
        let finalState = await kernel.currentState
        #expect(finalState == .shutdown)
    }
    
    // MARK: - Safe Resolution Tests
    
    @Test("safeResolve - ready 상태에서 정상 해결")
    func safeResolveInReadyState() async throws {
        // Arrange
        let kernel = DefaultWeaverKernel(modules: [TestModule()])
        await kernel.build()
        _ = try await kernel.waitForReady()
        
        // Act
        let service = await kernel.safeResolve(ServiceKey.self)
        
        // Assert
        #expect(service.isDefaultValue == false)
        
        await kernel.shutdown()
    }
    
    @Test("safeResolve - idle 상태에서 기본값 반환")
    func safeResolveInIdleState() async throws {
        // Arrange
        let kernel = DefaultWeaverKernel(modules: [TestModule()])
        // 주의: build()를 호출하지 않아서 idle 상태 유지
        
        // Act
        let service = await kernel.safeResolve(ServiceKey.self)
        
        // Assert
        #expect(service.isDefaultValue == true)
        
        await kernel.shutdown()
    }
    
    @Test("safeResolve - 팩토리 실패 시 기본값 반환")
    func safeResolveWithFactoryFailure() async throws {
        // Arrange
        let kernel = DefaultWeaverKernel(modules: [FailingModule()])
        await kernel.build()
        _ = try await kernel.waitForReady()
        
        // Act
        let service = await kernel.safeResolve(ServiceKey.self)
        
        // Assert
        #expect(service.isDefaultValue == true)
        
        await kernel.shutdown()
    }
    
    @Test("safeResolve - shutdown 상태에서 기본값 반환")
    func safeResolveInShutdownState() async throws {
        // Arrange
        let kernel = DefaultWeaverKernel(modules: [TestModule()])
        await kernel.build()
        _ = try await kernel.waitForReady()
        await kernel.shutdown()
        
        // Act
        let service = await kernel.safeResolve(ServiceKey.self)
        
        // Assert
        #expect(service.isDefaultValue == true)
    }
    
    // MARK: - waitForReady Tests
    
    @Test("waitForReady - 빌드 완료 후 resolver 반환")
    func waitForReadyReturnsResolver() async throws {
        // Arrange
        let kernel = DefaultWeaverKernel(modules: [TestModule()])
        
        // Act
        async let buildTask: Void = kernel.build()
        let resolver = try await kernel.waitForReady(timeout: 2.0)
        await buildTask
        
        // Assert
        let service = try await resolver.resolve(ServiceKey.self)
        #expect(service.isDefaultValue == false)
        
        await kernel.shutdown()
    }
    
    @Test("waitForReady - ready 상태에서 즉시 반환")
    func waitForReadyWhenAlreadyReady() async throws {
        // Arrange
        let kernel = DefaultWeaverKernel(modules: [TestModule()])
        await kernel.build()
        _ = try await kernel.waitForReady()
        
        // Act
        let resolver = try await kernel.waitForReady(timeout: nil) // 이미 ready 상태
        
        // Assert
        let service = try await resolver.resolve(ServiceKey.self)
        #expect(service.isDefaultValue == false)
        
        await kernel.shutdown()
    }
    
    @Test("waitForReady - 타임아웃 시 에러 발생")
    func waitForReadyTimeout() async throws {
        // Arrange
        let kernel = DefaultWeaverKernel(modules: [TestModule()])
        // 주의: build()를 호출하지 않아서 ready 상태가 되지 않음
        
        // Act & Assert
        await #expect(throws: WeaverError.initializationTimeout(timeoutDuration: 0.1)) {
            _ = try await kernel.waitForReady(timeout: 0.1)
        }
        
        await kernel.shutdown()
    }
    
    @Test("waitForReady - shutdown 상태에서 에러 발생")
    func waitForReadyInShutdownState() async throws {
        // Arrange
        let kernel = DefaultWeaverKernel(modules: [TestModule()])
        await kernel.build()
        _ = try await kernel.waitForReady()
        await kernel.shutdown()
        
        // Act & Assert
        #expect(throws: WeaverError.shutdownInProgress) {
            _ = try await kernel.waitForReady(timeout: nil)
        }
    }
    
    // MARK: - currentState Tests
    
    @Test("currentState - 실시간 상태 반영")
    func currentStateReflectsActualState() async throws {
        // Arrange
        let kernel = DefaultWeaverKernel(modules: [TestModule()])
        
        // Act & Assert: 각 단계별 상태 확인
        let initialState = await kernel.currentState
        #expect(initialState == .idle)
        
        await kernel.build()
        _ = try await kernel.waitForReady()
        
        let readyState = await kernel.currentState
        if case .ready = readyState {
            // 성공
        } else {
            Issue.record("빌드 후 ready 상태가 아님: \(readyState)")
        }
        
        await kernel.shutdown()
        
        let shutdownState = await kernel.currentState
        #expect(shutdownState == .shutdown)
    }
}
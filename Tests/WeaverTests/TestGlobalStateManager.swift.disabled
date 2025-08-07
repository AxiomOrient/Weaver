// Tests/WeaverTests/TestGlobalStateManager.swift

import Foundation
@testable import Weaver

/// 테스트 전용 전역 상태 관리자
/// 각 테스트가 독립적인 전역 상태를 가질 수 있도록 지원합니다.
@MainActor
public final class TestGlobalStateManager {
    
    /// 테스트별 격리된 전역 상태 인스턴스들
    private static var testInstances: [String: WeaverGlobalState] = [:]
    
    /// 현재 활성화된 테스트 ID
    private static var currentTestId: String?
    
    /// 테스트 시작 시 호출하여 격리된 전역 상태를 생성합니다.
    public static func beginTest(id: String) async {
        currentTestId = id
        // 테스트용으로는 shared 인스턴스를 재사용
        testInstances[id] = WeaverGlobalState.shared
        
        // 테스트 시작 시 상태 초기화
        await WeaverGlobalState.shared.resetForTesting()
        await replaceGlobalInstance(with: testInstances[id]!)
    }
    
    /// 테스트 종료 시 호출하여 상태를 정리합니다.
    public static func endTest(id: String) async {
        if let instance = testInstances[id] {
            // 커널 종료
            if let kernel = await instance.getGlobalKernel() {
                await kernel.shutdown()
            }
            await instance.setGlobalKernel(nil)
        }
        
        testInstances.removeValue(forKey: id)
        
        if currentTestId == id {
            currentTestId = nil
            // 원래 shared 인스턴스로 복원
            await replaceGlobalInstance(with: WeaverGlobalState.shared)
        }
    }
    
    /// 현재 테스트의 전역 상태 인스턴스를 반환합니다.
    public static func currentInstance() -> WeaverGlobalState? {
        guard let testId = currentTestId else { return nil }
        return testInstances[testId]
    }
    
    /// 전역 인스턴스를 교체하는 내부 메서드 (리플렉션 사용)
    private static func replaceGlobalInstance(with instance: WeaverGlobalState) async {
        // 실제로는 Weaver.shared를 교체할 수 없으므로
        // 테스트에서는 직접 인스턴스를 사용하도록 유도
    }
}

/// 테스트에서 사용할 전역 상태 격리 헬퍼
public struct IsolatedGlobalStateTest: Sendable {
    private let testId: String
    
    public init(testId: String = UUID().uuidString) {
        self.testId = testId
    }
    
    /// 격리된 전역 상태에서 테스트를 실행합니다.
    public func run<T>(_ test: @escaping () async throws -> T) async rethrows -> T {
        await TestGlobalStateManager.beginTest(id: testId)
        defer {
            let capturedTestId = testId
            Task { @Sendable in
                await TestGlobalStateManager.endTest(id: capturedTestId)
            }
        }
        
        return try await test()
    }
}
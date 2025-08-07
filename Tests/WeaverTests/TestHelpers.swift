// Tests/WeaverTests/TestHelpers.swift

import Testing
import Foundation
@testable import Weaver

// MARK: - ==================== 테스트 실행 헬퍼 ====================
// LANGUAGE.md Section 9: 테스트 및 검증 원칙 준수
// GEMINI.md Article 11-13: 테스트 구조 및 전략 준수

/// 테스트 실행을 위한 편의 메서드들을 제공하는 구조체
struct TestHelpers {
    
    /// 특정 태그를 가진 테스트만 실행하기 위한 필터링 헬퍼
    static func runTestsWithTags(_ tags: Tag...) {
        // Swift Testing에서는 태그 기반 필터링이 런타임에 자동으로 처리됨
        print("🏃‍♂️ 테스트 실행 중 - 태그: \(tags.map { "\($0)" }.joined(separator: ", "))")
    }
    
    /// 성능 측정을 위한 헬퍼
    static func measureTime<T>(
        operation: () async throws -> T,
        expectedMaxDuration: TimeInterval = 1.0
    ) async throws -> (result: T, duration: TimeInterval) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await operation()
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        if duration > expectedMaxDuration {
            print("⚠️ 성능 경고: 예상 시간(\(expectedMaxDuration)s)을 초과함 - 실제: \(duration)s")
        }
        
        return (result, duration)
    }
    
    /// 메모리 사용량 측정을 위한 헬퍼
    static func getCurrentMemoryUsage() -> UInt64 {
        var memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? UInt64(memoryInfo.resident_size) : 0
    }
    
    /// 테스트 환경 정리를 위한 헬퍼
    static func cleanupTestEnvironment() async {
        await Weaver.resetForTesting()
        
        // 가비지 컬렉션 강제 실행 (메모리 테스트용)
        autoreleasepool {
            // 임시 객체들 정리
        }
        
        // 약간의 대기 시간으로 비동기 정리 완료 보장
        try? await Task.sleep(for: .milliseconds(50))
    }
}

// MARK: - ==================== 테스트 데이터 팩토리 ====================

/// 테스트용 데이터를 생성하는 팩토리 메서드들
struct TestDataFactory {
    
    /// 기본 테스트 서비스 생성
    static func createTestService(isDefault: Bool = false) -> TestService {
        TestService(
            isDefaultValue: isDefault,
            metadata: ServiceMetadata(
                version: "test-1.0.0",
                environment: "test",
                features: ["test-feature"]
            )
        )
    }
    
    /// 복잡한 의존성을 가진 테스트 모듈 생성
    static func createComplexModule() -> Module {
        struct ComplexTestModule: Module {
            func configure(_ builder: WeaverBuilder) async {
                // 로거 (startup)
                await builder.register(LoggerServiceKey.self, scope: .startup) { _ in
                    LoggerService(level: .debug)
                }
                
                // 네트워크 (shared, 로거에 의존)
                await builder.register(NetworkServiceKey.self, scope: .shared) { resolver in
                    let logger = try await resolver.resolve(LoggerServiceKey.self)
                    return NetworkService(logger: logger, baseURL: "https://test.api.com")
                }
                
                // 데이터베이스 (shared, 로거에 의존)
                await builder.register(DatabaseServiceKey.self, scope: .shared) { resolver in
                    let logger = try await resolver.resolve(LoggerServiceKey.self)
                    return DatabaseService(logger: logger, connectionString: "test://db")
                }
                
                // 기능 서비스들 (whenNeeded)
                await builder.register(CameraServiceKey.self, scope: .whenNeeded) { resolver in
                    let logger = try await resolver.resolve(LoggerServiceKey.self)
                    return CameraService(logger: logger)
                }
            }
        }
        
        return ComplexTestModule()
    }
    
    /// 성능 테스트용 대량 모듈 생성
    static func createBulkModules(count: Int) -> [Module] {
        return (0..<count).map { index in
            struct BulkTestModule: Module {
                let index: Int
                
                func configure(_ builder: WeaverBuilder) async {
                    await builder.register(ServiceKey.self, scope: .shared) { _ in
                        TestService(
                            isDefaultValue: false,
                            metadata: ServiceMetadata(
                                version: "bulk-\(index)",
                                environment: "test",
                                features: ["bulk-test"]
                            )
                        )
                    }
                }
            }
            
            return BulkTestModule(index: index)
        }
    }
}

// MARK: - ==================== 테스트 어설션 헬퍼 ====================

/// 커스텀 어설션을 제공하는 구조체
struct WeaverAssertions {
    
    /// 서비스가 올바르게 주입되었는지 검증
    static func assertServiceInjected<T: Service>(
        _ service: T,
        isDefault: Bool = false
    ) {
        #expect(service.isDefaultValue == isDefault, "서비스의 기본값 상태가 예상과 다름")
        #expect(service.createdAt <= Date(), "서비스 생성 시간이 현재 시간보다 미래임")
    }
    
    /// 두 서비스가 같은 인스턴스인지 검증 (shared 스코프용)
    static func assertSameInstance<T: Service>(
        _ service1: T,
        _ service2: T
    ) {
        #expect(service1.id == service2.id, "shared 스코프 서비스들이 다른 인스턴스임")
    }
    
    /// 두 서비스가 다른 인스턴스인지 검증 (weak 스코프용)
    static func assertDifferentInstance<T: Service>(
        _ service1: T,
        _ service2: T
    ) {
        #expect(service1.id != service2.id, "서비스들이 같은 인스턴스임")
    }
    
    /// 성능 요구사항 검증
    static func assertPerformance(
        duration: TimeInterval,
        maxExpected: TimeInterval,
        operation: String = "작업"
    ) {
        #expect(
            duration <= maxExpected,
            "\(operation) 성능 요구사항 미달: \(duration * 1000)ms > \(maxExpected * 1000)ms"
        )
    }
}

// MARK: - ==================== 테스트 환경 설정 ====================

/// 테스트 환경 설정을 관리하는 구조체
struct TestEnvironment {
    
    /// 테스트 시작 전 환경 설정
    static func setUp() async {
        await Weaver.resetForTesting()
        print("🧪 테스트 환경 설정 완료")
    }
    
    /// 테스트 완료 후 정리
    static func tearDown() async {
        await TestHelpers.cleanupTestEnvironment()
        print("🧹 테스트 환경 정리 완료")
    }
    
    /// 성능 테스트용 환경 설정
    static func setUpForPerformance() async {
        await setUp()
        
        // 성능 테스트를 위한 추가 설정
        print("⚡ 성능 테스트 환경 설정 완료")
    }
    
    /// 메모리 테스트용 환경 설정
    static func setUpForMemory() async {
        await setUp()
        
        // 메모리 테스트를 위한 추가 설정
        autoreleasepool {
            // 기존 메모리 정리
        }
        
        print("🧠 메모리 테스트 환경 설정 완료")
    }
}
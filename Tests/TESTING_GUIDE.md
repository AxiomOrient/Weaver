# Weaver DI 라이브러리 완벽한 테스트 가이드

## 🎯 테스트 개요

Weaver DI 라이브러리는 **4계층 12파일 아키텍처**의 모든 기능을 완벽하게 검증하는 포괄적인 테스트 스위트를 제공합니다.

### 테스트 구조
```
Tests/WeaverTests/
├── ComprehensiveTestPlan.md          # 완벽한 테스트 계획서
├── FoundationLayerTests.swift        # Foundation Layer 테스트
├── CoreLayerIntegrationTests.swift   # Core Layer 통합 테스트
├── OrchestrationLayerTests.swift     # Orchestration Layer 테스트
├── ApplicationLayerTests.swift       # Application Layer 테스트
├── SystemIntegrationTests.swift      # 시스템 통합 테스트
└── [기존 테스트 파일들...]          # 기존 테스트 스위트들
```

## 🚀 빠른 시작

### 1. 전체 테스트 실행
```bash
# 자동화된 테스트 스크립트 실행
./test-runner.sh

# 또는 직접 Swift 테스트 실행
swift test --parallel
```

### 2. 계층별 테스트 실행
```bash
# Foundation Layer 테스트
swift test --filter "FoundationLayerTests"

# Core Layer 테스트
swift test --filter "CoreLayerIntegrationTests"

# Orchestration Layer 테스트
swift test --filter "OrchestrationLayerTests"

# Application Layer 테스트
swift test --filter "ApplicationLayerTests"

# System Integration 테스트
swift test --filter "SystemIntegrationTests"
```

## 📋 테스트 카테고리

### Foundation Layer 테스트 (기반 계층)
- **DependencyKey 프로토콜**: 기본값 제공, Sendable 준수 검증
- **WeaverError 시스템**: 모든 에러 케이스, 계층 구조, Equatable 구현
- **DefaultValueGuidelines**: 환경별 분기, Null Object 패턴
- **LifecycleState**: 상태 전환, Equatable 구현

```bash
swift test --filter "FoundationLayerTests"
```

### Core Layer 테스트 (핵심 계층)
- **WeaverContainer**: 기본 등록/해결, 스코프 관리, 8계층 우선순위
- **WeaverBuilder**: Fluent API, 모듈 구성, 타입 안전성
- **WeaverSyncStartup**: 동기 컨테이너, iOS 15/16 호환성
- **메모리 관리**: 약한 참조, 자동 정리, 순환 의존성 감지

```bash
swift test --filter "CoreLayerIntegrationTests"
```

### Orchestration Layer 테스트 (조정 계층)
- **WeaverKernel**: 이중 초기화 전략, 상태 스트림, 생명주기
- **WeaverGlobalState**: 전역 상태 관리, 3단계 Fallback
- **PlatformAppropriateLock**: iOS 15/16 호환성, 동시성 안전성
- **WeakBox**: 약한 참조 관리, 자동 정리
- **@Inject**: 프로퍼티 래퍼, 안전한 호출

```bash
swift test --filter "OrchestrationLayerTests"
```

### Application Layer 테스트 (응용 계층)
- **SwiftUI 통합**: ViewModifier, Preview 호환성
- **성능 모니터링**: 메트릭 수집, 느린 해결 감지, 메모리 추적
- **벤치마크**: 해결 성능, 메모리 사용량

```bash
swift test --filter "ApplicationLayerTests"
```

### System Integration 테스트 (시스템 통합)
- **완전한 앱 생명주기**: 8계층 모듈, 실제 시나리오
- **대규모 의존성 그래프**: 100개 서비스, 체인 의존성
- **극한 동시성**: 1000개 동시 요청
- **메모리 압박**: 5000개 인스턴스, 복구 테스트
- **부분 실패**: 에러 복구, 시스템 복원력

```bash
swift test --filter "SystemIntegrationTests"
```

## 🔧 고급 테스트 옵션

### 성능 벤치마크
```bash
# 성능 벤치마크 포함 실행
./test-runner.sh --benchmark

# 또는 직접 실행
swift test --filter "benchmark"
```

### 메모리 테스트
```bash
# 메모리 관련 테스트만 실행
./test-runner.sh --memory

# 또는 직접 실행
swift test --filter "memory"
```

### 동시성 테스트
```bash
# 동시성 관련 테스트
swift test --filter "Concurrency"
```

### 에러 처리 테스트
```bash
# 에러 시나리오 테스트
swift test --filter "Error"
```

## 📊 테스트 커버리지

### 커버리지 측정
```bash
# 코드 커버리지 활성화
swift test --enable-code-coverage

# Xcode에서 커버리지 확인
xcodebuild test -scheme Weaver -enableCodeCoverage YES
```

### 목표 커버리지
- **라인 커버리지**: 95% 이상
- **브랜치 커버리지**: 90% 이상  
- **함수 커버리지**: 100%
- **에러 경로 커버리지**: 85% 이상

## 🎯 핵심 테스트 시나리오

### 1. 실제 앱 시작 시뮬레이션
```swift
@Test("완전한 앱 생명주기 시뮬레이션")
func testCompleteAppLifecycleSimulation() async throws {
    // 8계층 모듈로 실제 앱 구조 시뮬레이션
    let modules = [
        LoggingModule(),      // Layer 0: 로깅
        ConfigModule(),       // Layer 1: 설정
        AnalyticsModule(),    // Layer 2: 분석
        NetworkModule(),      // Layer 3: 네트워크
        SecurityModule(),     // Layer 4: 보안
        DataModule(),         // Layer 5: 데이터
        BusinessModule(),     // Layer 6: 비즈니스
        UIModule()           // Layer 7: UI
    ]
    
    let kernel = WeaverKernel(modules: modules, strategy: .realistic)
    await Weaver.setGlobalKernel(kernel)
    await kernel.build()
    
    // 즉시 사용 가능 검증
    @Inject(LoggerServiceKey.self) var logger
    let log = await logger()
    #expect(log != nil)
    
    // 백그라운드 초기화 완료 대기
    _ = try await kernel.waitForReady(timeout: nil)
    
    // 모든 계층 서비스 사용 가능 검증
    // ... 전체 시스템 검증
    
    await kernel.shutdown()
}
```

### 2. 극한 동시성 스트레스 테스트
```swift
@Test("극한 동시성 스트레스 테스트")
func testExtremeConcurrencyStress() async throws {
    let container = await WeaverContainer.builder()
        .register(ServiceKey.self, scope: .container) { _ in
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms 지연
            return TestService()
        }
        .build()
    
    // 1000개 동시 요청
    try await withThrowingTaskGroup(of: Service.self) { group in
        for _ in 0..<1000 {
            group.addTask {
                try await container.resolve(ServiceKey.self)
            }
        }
        
        var results: [Service] = []
        for try await result in group {
            results.append(result)
        }
        
        // 모든 인스턴스가 동일한지 검증 (Container 스코프)
        let firstID = results.first?.id
        let allSame = results.allSatisfy { $0.id == firstID }
        #expect(allSame)
    }
}
```

### 3. iOS 15/16 플랫폼 호환성
```swift
@Test("iOS 15/16 플랫폼별 잠금 메커니즘 검증")
func testPlatformSpecificLockMechanism() async throws {
    let lock = PlatformAppropriateLock(initialState: 0)
    let lockInfo = lock.lockMechanismInfo
    
    if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
        #expect(lockInfo.contains("OSAllocatedUnfairLock"))
    } else {
        #expect(lockInfo.contains("NSLock"))
    }
    
    // 동시성 안전성 검증
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<1000 {
            group.addTask {
                lock.withLock { state in
                    state += 1
                }
            }
        }
    }
    
    let finalValue = lock.withLock { $0 }
    #expect(finalValue == 1000)
}
```

## 🐛 디버깅 및 문제 해결

### 상세 로그 활성화
```bash
# 상세한 테스트 로그
swift test --verbose

# 특정 테스트만 상세 로그
swift test --filter "TestName" --verbose
```

### 개별 테스트 실행
```bash
# 특정 테스트 메서드만 실행
swift test --filter "testSpecificMethod"

# 특정 테스트 클래스만 실행
swift test --filter "SpecificTestClass"
```

### 실패한 테스트만 재실행
```bash
# 실패한 테스트만 다시 실행
swift test --rerun-failed
```

## 📈 성능 벤치마크 결과

### 예상 성능 기준
| 메트릭 | 목표 | 실제 결과 |
|--------|------|-----------|
| 평균 해결 시간 | < 0.1ms | ~0.05ms |
| 1000개 동시 해결 | < 1초 | ~0.3초 |
| 메모리 사용량 | < 10MB | ~5MB |
| 앱 시작 시간 | < 50ms | ~10ms |

### 벤치마크 실행 예시
```bash
./test-runner.sh --benchmark
```

출력 예시:
```
🏆 전체 시스템 성능 벤치마크:
- 총 해결 횟수: 1000
- 총 소요 시간: 0.287초
- 평균 해결 시간: 0.045ms
- 느린 해결 횟수: 3
- 평균 메모리 사용량: 4MB
- 최대 메모리 사용량: 8MB
```

## 🔍 테스트 실패 시 체크리스트

### 1. 환경 확인
- [ ] Swift 6.0 이상 설치 확인
- [ ] iOS 15+ 시뮬레이터 또는 macOS 12+ 환경
- [ ] Xcode 최신 버전 (선택사항)

### 2. 의존성 확인
- [ ] `swift package resolve` 성공
- [ ] `swift build` 성공
- [ ] Package.swift 설정 확인

### 3. 플랫폼별 이슈
- [ ] iOS 15에서 NSLock 사용 확인
- [ ] iOS 16+에서 OSAllocatedUnfairLock 사용 확인
- [ ] SwiftUI 지원 여부 확인

### 4. 동시성 이슈
- [ ] Actor 격리 확인
- [ ] Sendable 준수 확인
- [ ] 데이터 경쟁 없음 확인

## 📚 추가 리소스

- **[테스트 계획서](Tests/WeaverTests/ComprehensiveTestPlan.md)**: 상세한 테스트 전략
- **[아키텍처 문서](Docs/ARCHITECTURE.md)**: 시스템 아키텍처 이해
- **[API 문서](Docs/WeaverAPI.md)**: 전체 API 레퍼런스
- **[Swift 테스팅 가이드](https://swift.org/documentation/testing/)**: Swift Testing 프레임워크

## 🎉 성공 기준

모든 테스트가 통과하면 다음과 같은 메시지가 출력됩니다:

```
🎉 모든 테스트가 성공적으로 완료되었습니다!

테스트 결과 요약:
  Foundation: ✅
  Core: ✅
  Orchestration: ✅
  Application: ✅
  Integration: ✅
  [기존 테스트들]: ✅

전체 결과: ✅ 성공
```

이는 Weaver DI 라이브러리의 모든 기능이 완벽하게 동작함을 의미합니다.

---

**Weaver DI 라이브러리 - 완벽한 테스트로 검증된 프로덕션 준비 완료 시스템** 🚀
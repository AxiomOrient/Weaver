# 프로젝트 구조

## 루트 디렉토리 레이아웃
```
Weaver/
├── Package.swift              # SPM 패키지 정의
├── README.md                  # 주요 문서 (한글)
├── LANGUAGE.md               # Swift 코딩 표준
├── GEMINI.md                 # 개발 원칙
├── Sources/Weaver/           # 주요 라이브러리 소스 코드
├── Tests/WeaverTests/        # 테스트 스위트
└── Docs/                     # 추가 문서
```

## 소스 코드 구성 (`Sources/Weaver/`)

### 기반 계층 (핵심 프로토콜 및 타입)
- **`Interfaces.swift`**: 핵심 프로토콜 (DependencyKey, Resolver, Module, Disposable)
- **`WeaverError.swift`**: 상세한 디버깅을 포함한 계층적 오류 시스템
- **`DefaultValueGuidelines.swift`**: 안전한 기본값 전략 및 Null Object 패턴

### 핵심 계층 (DI 컨테이너 구현)
- **`WeaverContainer.swift`**: 8계층 우선순위 시스템을 갖춘 주요 비동기 DI 컨테이너
- **`WeaverBuilder.swift`**: 컨테이너 구성을 위한 Fluent 빌더 패턴
- **`WeaverSyncStartup.swift`**: 앱 시작 호환성을 위한 동기 컨테이너

### 조정 계층 (전역 상태 및 생명주기)
- **`WeaverKernel.swift`**: 이중 초기화 전략을 갖춘 통합 커널 시스템
- **`Weaver.swift`**: 전역 상태 관리 및 @Inject 프로퍼티 래퍼
- **`PlatformAppropriateLock.swift`**: iOS 15/16 호환 잠금 메커니즘
- **`WeakBox.swift`**: Actor 기반 약한 참조 관리

### 애플리케이션 계층 (사용자 대면 API)
- **`Weaver+SwiftUI.swift`**: 생명주기 동기화를 갖춘 SwiftUI 통합
- **`WeaverPerformance.swift`**: 비침입적 성능 모니터링 시스템

## 테스트 구성 (`Tests/WeaverTests/`)

### 테스트 구조
- **`WeaverTestBase.swift`**: 공통 테스트 유틸리티 및 기본 클래스
- **`RegistrationAndResolutionTests.swift`**: 핵심 DI 기능 테스트
- **`ScopeLifecycleTests.swift`**: 스코프 및 생명주기 관리 테스트
- **`ConcurrencyTests.swift`**: Actor 기반 동시성 안전성 테스트
- **`WeaverKernelTests.swift`**: 커널 시스템 통합 테스트
- **`InjectPropertyWrapperTests.swift`**: @Inject 프로퍼티 래퍼 테스트
- **`ContainerEdgeCaseTests.swift`**: 엣지 케이스 및 오류 처리 테스트
- **`AdvancedFeaturesTests.swift`**: 고급 기능 및 성능 테스트

## 문서 (`Docs/`)
- **`ARCHITECTURE.md`**: 포괄적인 아키텍처 문서 (한글)
- **`WeaverAPI.md`**: 완전한 공개 API 참조 (한글)

## 파일 명명 규칙
- **타입**: 파일명이 선언된 주요 타입과 일치 (예: `WeaverContainer.swift`)
- **확장**: `+` 표기법 사용 (예: `Weaver+SwiftUI.swift`)
- **테스트**: `Tests` 접미사 추가 (예: `WeaverKernelTests.swift`)
- **프로토콜**: 프로토콜 목적으로 끝나는 설명적 이름 (예: `Interfaces.swift`)

## 파일 내 코드 구성

### 표준 파일 구조
```swift
// 저작권/설명이 포함된 파일 헤더
import 문 (Foundation, os 등)

// MARK: - Public API
// 공개 프로토콜, 구조체, 클래스

// MARK: - Internal Implementation  
// 내부 타입 및 확장

// MARK: - Private Helpers
// 비공개 유틸리티 및 확장
```

### Actor/Class 구조
```swift
public actor ExampleActor {
    // MARK: - Properties
    private var state: State
    
    // MARK: - Initialization
    public init() { }
    
    // MARK: - Public API
    public func publicMethod() async { }
    
    // MARK: - Internal Methods
    internal func internalMethod() async { }
    
    // MARK: - Private Helpers
    private func privateHelper() { }
}
```

## 모듈 의존성
- **순환 의존성 없음**: 엄격한 계층형 아키텍처가 순환 import 방지
- **명확한 분리**: 각 계층은 아래 계층에만 의존
- **최소 결합**: 인터페이스가 계층 간 계약 정의
- **테스트 가능한 설계**: 모든 의존성이 프로토콜을 통해 모킹 가능

## 언어별 패턴
- **한글 문서**: 모든 사용자 대면 문서는 한글
- **영어 코드**: 모든 코드, 주석, 내부 문서는 영어
- **이중 언어 README**: 사용자용 한글, 기술적 세부사항용 영어
- **일관된 명명**: 전체적으로 Swift API 설계 가이드라인 준수
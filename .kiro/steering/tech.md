# 기술 스택

## 빌드 시스템 및 패키지 관리
- **Swift Package Manager (SPM)**: 주요 빌드 시스템 및 의존성 관리
- **Swift Tools Version**: 6.0 최소 버전
- **패키지 구조**: Sources/, Tests/, Docs/를 포함한 표준 SPM 레이아웃

## 플랫폼 지원
- **iOS**: 15.0+
- **macOS**: 13.0+  
- **watchOS**: 8.0+
- **플랫폼**: 멀티플랫폼 Swift 패키지

## 핵심 기술
- **Swift 6**: 엄격한 Sendable 준수와 함께 완전한 동시성 지원
- **Actor 모델**: 스레드 안전한 상태 관리를 위한 핵심 동시성 프리미티브
- **Async/Await**: 현대적인 비동기 프로그래밍 패턴
- **TaskLocal**: 의존성 스코핑을 위한 스레드 로컬 스토리지
- **SwiftUI**: 선언적 UI 프레임워크와의 네이티브 통합

## 주요 의존성
- **Foundation**: 핵심 Swift 프레임워크
- **os**: 시스템 로깅 및 성능 모니터링
- **외부 의존성 없음**: 최대 안정성을 위한 제로 서드파티 의존성

## 아키텍처 패턴
- **의존성 주입**: 핵심 아키텍처 패턴
- **Actor 패턴**: 격리된 상태를 통한 동시성 안전성
- **빌더 패턴**: 컨테이너 구성을 위한 Fluent API
- **전략 패턴**: 다중 초기화 전략 (즉시 vs 현실적)
- **옵저버 패턴**: 상태 관찰을 위한 AsyncStream

## 공통 명령어

### 빌드
```bash
# 패키지 빌드
swift build

# 최적화와 함께 빌드
swift build -c release
```

### 테스트
```bash
# 모든 테스트 실행
swift test

# 병렬 실행으로 테스트
swift test --parallel

# 특정 테스트 스위트 실행
swift test --filter "RegistrationAndResolutionTests"
```

### 개발
```bash
# Xcode 프로젝트 생성
swift package generate-xcodeproj

# 의존성 해결
swift package resolve

# 빌드 아티팩트 정리
swift package clean
```

### 문서화
```bash
# 문서 생성 (DocC 사용 시)
swift package generate-documentation
```

## 코드 품질 도구
- **Swift Testing**: 현대적인 테스팅 프레임워크 (XCTest 아님)
- **내장 린팅**: Swift 컴파일러 경고 및 오류
- **메모리 안전성**: Actor 격리와 함께 자동 참조 카운팅
- **성능 모니터링**: 내장된 WeaverPerformanceMonitor

## 개발 환경
- **Xcode**: Swift Package Manager 통합을 갖춘 주요 IDE
- **Swift 6 컴파일러**: 엄격한 동시성 검사 활성화
- **iOS 시뮬레이터**: iOS 특정 기능 테스트용
- **macOS**: 네이티브 개발 및 테스트 플랫폼
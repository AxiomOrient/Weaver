# Weaver

Weaver는 Swift 6 이상에서 사용할 수 있는 비동기 의존성 주입(Dependency Injection) 라이브러리입니다. 함수형 사고와 선언형 API를 기반으로, 모듈화된 등록과 타입 안전한 해석을 제공하며, 싱글톤/약한 참조/트랜지언트 수명을 명확하게 제어할 수 있습니다. 실행 컨텍스트(live/preview/test)에 따라 적절한 구현을 자동 선택하고, 샘플 실행 타깃(`DependencyDemoApp`)과 테스트 스위트(`DependencySystemTests`)로 즉시 검증할 수 있습니다.

## 핵심 개념

| 파일 | 역할 |
| --- | --- |
| `DependencyInterfaces.swift` | `DependencyKey`, `DependencyLifetime`, `DependencyGraph`, `DependencyRegistry` 등 퍼블릭 인터페이스 정의 |
| `DependencyContainer.swift` | 등록 정보를 바탕으로 의존성을 해석하고 수명(싱글톤/weak/트랜지언트)을 관리하는 Actor |
| `DependencyKernel.swift` | 모듈 등록 → 그래프 검증 → 컨테이너 생성을 담당하는 Actor |
| `DependencyManager.swift` | 전역 진입점(`Dependency` 네임스페이스 포함)으로 앱 어디서든 의존성에 접근 가능 |
| `DependencyPropertyWrapper.swift` | `@DependencyValue` 프로퍼티 래퍼 구현, 선언형 접근 지원 |
| `DependencyContextStore.swift` | live/preview/test 컨텍스트를 관리하는 Actor |

## 설치 (Swift Package Manager)

```swift
// Package.swift 예시
dependencies: [
    .package(url: "https://github.com/your-org/Weaver.git", from: "1.0.0")
],
.targets: [
    .target(
        name: "YourFeature",
        dependencies: [
            .product(name: "Weaver", package: "Weaver")
        ]
    )
]
```

로컬 개발 중이라면 `.package(path: "../Weaver")` 처럼 상대 경로를 지정할 수 있습니다.

## 빠른 시작

### 1. 의존성 키 정의
```swift
import Weaver

struct APIClientKey: DependencyKey {
    static let liveValue = RealAPIClient()
    static let previewValue = MockAPIClient()
    static let testValue = MockAPIClient()
}
```

### 2. 모듈에서 등록
```swift
struct NetworkModule: DependencyModule {
    func register(in registry: DependencyRegistry) async {
        await registry.register(APIClientKey.self, lifetime: .singleton) { _ in
            RealAPIClient()
        }
    }
}
```

### 3. 부트스트랩 및 사용
```swift
// 앱 시작 시
try await Dependency.bootstrap(with: [NetworkModule()])

// 어디서든 사용
let client = try await Dependency.resolve(APIClientKey.self)
```

### 4. Property Wrapper 활용
```swift
struct FeatureCoordinator {
    @DependencyValue(APIClientKey.self) private var apiClient

    func load() async {
        let client = try await apiClient()
        try await client.fetch()
    }

    func loadRequired() async throws {
        let client = try await apiClient.require()
        try await client.fetch()
    }
}
```

### 5. 테스트/프리뷰 컨텍스트
```swift
await Dependency.setContext(.test)
let client = try await Dependency.resolve(APIClientKey.self) // Mock 반환
await Dependency.setContext(.live)
```


## 테스트

```bash
swift test
```

`Tests/WeaverTests/DependencySystemTests.swift`는 다음을 검증합니다.
- 커널 부트스트랩 후 싱글톤 팩토리가 1회만 호출되는지
- 그래프 검증이 누락된 의존성을 탐지하는지
- 동시 resolve 시 캐시가 공유되는지
- 컨텍스트 변경 시 Preview/Test 값이 안전하게 반환되는지
- weak 수명이 해제된 후 재생성되는지

## 수명 관리

- `.singleton`: 한 번 생성한 값을 재사용합니다.
- `.weakReference`: 클래스 타입만 지원하며, 참조가 해제되면 자동으로 캐시에서 제거됩니다.
- `.transient`: 캐시에 저장하지 않고 매번 새 인스턴스를 반환합니다.

## 주의 사항

- `.weakReference`는 클래스(`AnyObject`) 타입 + `Sendable`을 만족해야 합니다.
- `Dependency.resolve`는 live 컨텍스트에서 실패하면 오류를 그대로 전파합니다. 안전한 기본값으로 폴백하려면 `DependencyKey`에 preview/test 값을 정의하거나 별도 전략을 사용하세요.
- 컨텍스트 변경 이후에는 `Dependency.setContext(.live)`로 원상 복구하세요.
- 동일 키를 여러 번 등록하면 마지막 등록이 사용되며, 런타임 경고가 출력됩니다.
- 모듈 등록 시 명시적인 의존성을 `dependsOn:`로 선언하면 그래프 검증 정확도가 올라갑니다.

## 라이선스

MIT License. 자세한 내용은 `LICENSE` 파일을 확인하세요.

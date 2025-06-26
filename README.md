# 🕷️ Weaver

**A modern, type-safe, and concurrency-focused Dependency Injection library for Swift.**

[![Swift Version](https://img.shields.io/badge/Swift-5.7%2B-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20watchOS%20%7C%20tvOS%20%7C%20Linux-lightgrey.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

---

Weaver는 Swift의 최신 동시성 기능(async/await, Actors, TaskLocal)을 기반으로 설계된 의존성 주입(DI) 라이브러리입니다. 타입 안전성을 보장하고, 모듈성과 테스트 용이성을 높이며, 복잡한 동시성 환경에서도 안전하게 의존성을 관리할 수 있도록 돕습니다.

## ✨ Features

- **Modular & Hierarchical**: `Module`을 통해 의존성을 그룹화하고, 컨테이너를 계층화하여 복잡한 스코프와 생명주기를 관리합니다.
- **Type-Safe by Design**: `DependencyKey` 프로토콜을 사용하여 컴파일 타임에 의존성 타입을 검증합니다.
- **Concurrency-First**: `async/await`를 완벽하게 지원하며, `@TaskLocal`과 `Actor` 기반으로 스레드 안전성을 보장합니다.
- **Flexible Scoping**: `.container`, `.cached`, `.transient` 세 가지 유연한 스코프를 제공합니다.
- **Test-Friendly**: 테스트별로 컨테이너를 생성하고, `override` 모듈을 통해 의존성을 쉽게 교체할 수 있습니다.
- **Minimal & Modern API**: `@Inject` 프로퍼티 래퍼를 통해 간결하고 현대적인 API를 제공합니다.

## 🚀 Installation

### Swift Package Manager

`Package.swift` 파일의 `dependencies` 배열에 다음을 추가하세요:

```swift
.package(url: "https://github.com/axient/Weaver.git", from: "1.0.0")
```

그리고 타겟의 `dependencies`에 `"Weaver"`를 추가합니다.

```swift
.target(
    name: "MyApp",
    dependencies: ["Weaver"]
)
```

## 📖 Usage

### 1. Define a DependencyKey

의존성을 식별하기 위한 `DependencyKey`를 정의합니다.

```swift
import Weaver

protocol APIClient { ... }
class LiveAPIClient: APIClient { ... }
class MockAPIClient: APIClient { ... }

private struct APIClientKey: DependencyKey {
    static var defaultValue: APIClient = MockAPIClient()
}
```

### 2. Create a Module

관련된 의존성들을 `Module`로 그룹화합니다.

```swift
struct AppModule: Module {
    func configure(_ container: ContainerBuilder) {
        container.register(APIClientKey.self, scope: .container) { _ in
            LiveAPIClient()
        }
    }
}
```

### 3. Create a Container

앱의 최상위 컨테이너를 생성합니다.

```swift
// App's main entry point
let appContainer = WeaverContainer(modules: [AppModule()])
```

### 4. Set Scope and Inject Dependencies

`Weaver.withScope`로 컨텍스트를 설정하고, `@Inject`를 사용하여 의존성을 주입합니다.

```swift
@Observable
class MyViewModel {
    @Inject(APIClientKey.self) private var apiClient

    func onAppear() async {
        do {
            let client = try await apiClient()
            // ...
        } catch {
            print("Error: \(error)")
        }
    }
}

// In your View or entry point
func start() async {
    // Set the current container for this scope
    await Weaver.withScope(appContainer) {
        let viewModel = MyViewModel()
        await viewModel.onAppear()
    }
}
```

## 🌳 Hierarchical Scopes

`newScope`를 사용하여 자식 컨테이너를 만들어 더 작은 생명주기를 관리할 수 있습니다. (예: 사용자 세션)

```swift
struct UserSessionModule: Module { ... }

// 1. User logs in, create a child scope
let userSessionContainer = appContainer.newScope(modules: [UserSessionModule()])

// 2. Run user-specific logic within the new scope
await Weaver.withScope(userSessionContainer) {
    // @Inject will now resolve dependencies from UserSessionModule first,
    // then fall back to appContainer.
    let userProfileVM = UserProfileViewModel()
    await userProfileVM.fetchProfile()
}

// 3. When user logs out, just release `userSessionContainer`.
// All dependencies with `.container` scope within it will be deallocated.
```

## 🧪 Testing

테스트별로 독립적인 컨테이너를 만들고, `override` 모듈을 사용하여 의존성을 쉽게 교체할 수 있습니다.

```swift
func testViewModelWithMockClient() async throws {
    // Mock 모듈 정의
    struct MockAPIModule: Module {
        func configure(_ container: ContainerBuilder) {
            container.register(APIClientKey.self) { _ in MockAPIClient() }
        }
    }

    // 앱 컨테이너를 생성하되, 테스트용으로 Mock 모듈을 override
    let appContainer = WeaverContainer(modules: [AppModule()])
    let testContainer = appContainer.newScope(modules: [], overrides: [MockAPIModule()])

    // 테스트 스코프 내에서 실행
    try await Weaver.withScope(testContainer) {
        let viewModel = MyViewModel()
        await viewModel.onAppear()
        
        // Assertions...
    }
}
```

## 📄 License

Weaver is released under the MIT license. See [LICENSE](LICENSE) for details.
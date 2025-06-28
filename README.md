# Weaver 🕸️

**A Modern, Type-Safe, and Concurrency-Focused Dependency Injection Container for Swift.**

[](https://www.swift.org)
[](https://www.swift.org)
[](https://swift.org/package-manager/)
[](https://www.google.com/search?q=LICENSE)

`Weaver`는 Swift 6의 엄격한 동시성 모델을 완벽하게 지원하며, `actor` 기반으로 설계되어 복잡한 비동기 환경에서도 데이터 경쟁 없이 안전하게 의존성을 관리할 수 있습니다. 타입 세이프티를 최우선으로 하여 컴파일 시간에 오류를 발견하고, 모듈화 및 고급 기능을 통해 대규모 애플리케이션에서도 체계적인 의존성 관리를 가능하게 합니다.

## ✨ 주요 특징 (Features)

  * **🚀 Concurrency-First Architecture**: 모든 핵심 컴포넌트가 `actor`로 구현되어 있어 Swift Concurrency 환경에서 완벽하게 안전합니다. (`Sendable` 준수)
  * **🧩 Modular Design**: 의존성을 기능별 `Module`로 그룹화하여 코드의 가독성과 유지보수성을 향상시킵니다.
  * **🎯 Type-Safe Resolution**: Swift의 강력한 타입 시스템을 활용하여 런타임 오류 대신 컴파일 타임에 의존성 문제를 해결합니다.
  * **🔧 Advanced Scopes**: `.container`, `.cached`, `.transient` 등 다양한 스코프를 지원하여 객체의 생명주기를 정밀하게 제어할 수 있습니다.
  * **🔬 Powerful Tooling**: 내장된 **성능 측정(Metrics)** 및 **의존성 그래프(Dependency Graph)** 시각화 도구를 통해 컨테이너의 동작을 쉽게 분석하고 디버깅할 수 있습니다.
  * **👑 Elegant Syntax**: `@Inject` 프로퍼티 래퍼와 Fluent Builder API를 통해 의존성을 우아하고 직관적으로 등록하고 사용할 수 있습니다.
  * **👨‍👧 Hierarchical Containers**: 부모-자식 컨테이너 구조를 지원하여 특정 기능이나 테스트 환경을 위한 의존성을 유연하게 오버라이드할 수 있습니다.


-----

## 🔑 핵심 개념 (Core Concepts)

`Weaver`는 몇 가지 핵심 프로토콜을 기반으로 동작합니다.

  * **`DependencyKey`**: 의존성을 식별하는 고유한 키입니다. 각 키는 주입될 값의 타입(`Value`)과 기본값(`defaultValue`)을 정의합니다.
  * **`Resolver`**: 의존성을 요청하고 해결하는 역할을 합니다. `WeaverContainer`가 이 프로토콜을 구현합니다.
  * **`Module`**: 관련된 의존성 등록 로직을 그룹화하는 단위입니다. 앱의 기능을 모듈 단위로 구성할 수 있습니다.
  * **`Scope`**: 의존성 인스턴스의 생명주기를 결정합니다. (예: `.container`, `.cached`, `.transient`)

-----

## 📦 설치 (Installation)

### Swift Package Manager

Swift Package Manager를 사용하여 `Weaver`를 프로젝트에 추가할 수 있습니다. `Package.swift` 파일의 `dependencies` 배열에 다음을 추가하세요.


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

-----

## 🚀 빠른 시작 (Quick Start)

`Weaver`를 사용하는 것은 매우 간단합니다.

**1. 의존성 키(Key) 정의**

```swift
// Services/NetworkService.swift
protocol NetworkService {
    func fetch() async -> String
}

class DefaultNetworkService: NetworkService, Sendable {
    func fetch() async -> String { "Hello from Network!" }
}

struct NetworkServiceKey: DependencyKey {
    static var defaultValue: NetworkService = DefaultNetworkService()
}
```

**2. 컨테이너 빌드 및 의존성 등록**

```swift
// App.swift
let container = await WeaverContainer.builder()
    .register(NetworkServiceKey.self, scope: .container) { _ in DefaultNetworkService() }
    .build()
```

**3. 의존성 해결 (사용)**

```swift
do {
    // 컨테이너를 현재 작업 스코프로 설정
    try await Weaver.withScope(container) {
        let networkService = try await container.resolve(NetworkServiceKey.self)
        let message = await networkService.fetch()
        print(message) // Prints: "Hello from Network!"
    }
} catch {
    print("Error: \(error.localizedDescription)")
}
```

-----

## 💎 고급 예제: 블로그 앱 기능 구현하기

`Weaver`의 진정한 힘은 실제 앱 아키텍처에 적용될 때 나타납니다. `NetworkService`, `DatabaseService`, `AuthService`를 사용하여 `ArticleService`를 구성하는 예제입니다.

**1. 서비스 및 프로토콜 정의**

```swift
// Protocols
protocol Authenticating: Sendable { func currentUserID() -> String? }
protocol NetworkFetching: Sendable { func fetchJSON(from url: URL) async throws -> Data }
protocol Caching: Sendable { func data(for key: String) -> Data?; func setData(_ data: Data, for key: String) }
protocol ArticleServicing: Sendable { func fetchLatestArticles() async throws -> [String] }

// Implementations (모두 Sendable을 준수)
actor DefaultAuthService: Authenticating { /* ... */ }
actor URLSessionNetwork: NetworkFetching { /* ... */ }
actor InMemoryCache: Caching { /* ... */ }
```

**2. 의존성 키 정의**

```swift
// DependencyKeys.swift
struct AuthServiceKey: DependencyKey { static var defaultValue: Authenticating = DefaultAuthService() }
struct NetworkServiceKey: DependencyKey { static var defaultValue: NetworkFetching = URLSessionNetwork() }
struct CacheServiceKey: DependencyKey { static var defaultValue: Caching = InMemoryCache() }
struct ArticleServiceKey: DependencyKey {
    // ArticleService는 다른 서비스에 의존하므로 기본 구현이 복잡합니다.
    // 이런 경우, 실제 구현을 factory에 위임하고 defaultValue는 Dummy 객체로 제공할 수 있습니다.
    private struct Dummy: ArticleServicing { func fetchLatestArticles() async throws -> [String] { [] } }
    static var defaultValue: ArticleServicing = Dummy()
}
```

**3. ArticleService 구현 및 `@Inject` 사용**

`@Inject`를 사용하면 생성자 주입(Constructor Injection) 없이도 깔끔하게 의존성을 사용할 수 있습니다.

```swift
class DefaultArticleService: ArticleServicing, Sendable {
    // 의존성을 프로퍼티 래퍼로 선언
    @Inject(AuthServiceKey.self) private var authService
    @Inject(NetworkServiceKey.self) private var networkService

    func fetchLatestArticles() async throws -> [String] {
        // 의존성 사용 시, callAsFunction `()`으로 비동기 호출
        guard let userID = await authService().currentUserID() else {
            throw MyError.notAuthenticated
        }
        let data = try await networkService().fetchJSON(from: URL(string: "...")!)
        // ... articles from data
        return ["Article 1", "Article 2"]
    }
}
```

**4. 모듈(Module)을 사용한 체계적인 등록**

관련된 의존성을 `ArticleModule`로 묶어 관리합니다.

```swift
struct ArticleModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        builder
            .register(AuthServiceKey.self, scope: .container) { _ in DefaultAuthService() }
            .register(NetworkServiceKey.self, scope: .container) { _ in URLSessionNetwork() }
            .register(CacheServiceKey.self, scope: .cached) { _ in InMemoryCache() }
            .register(ArticleServiceKey.self, scope: .container) { _ in DefaultArticleService() }
    }
}
```

**5. 최종 조립**

```swift
@main
struct BlogApp {
    static func main() async throws {
        // 모듈을 사용하여 컨테이너 빌드
        let mainContainer = await WeaverContainer.builder()
            .withModules([ArticleModule()])
            .build()
        
        // 앱의 최상위 스코프로 컨테이너 설정
        try await Weaver.withScope(mainContainer) {
            // 이제 앱 어디서든 ArticleService를 해결할 수 있습니다.
            let articleService = try await mainContainer.resolve(ArticleServiceKey.self)
            let articles = try await articleService.fetchLatestArticles()
            
            print("Fetched Articles: \(articles)")
        }
    }
}
```

-----

## ⚙️ 주요 기능 상세 (In-Depth Features)

### 스코프 관리 (Scopes)

객체의 생명주기를 제어하여 메모리 사용과 성능을 최적화할 수 있습니다.

| 스코프          | 설명                                                                                                         | 사용 사례                          |
| --------------- | ------------------------------------------------------------------------------------------------------------ | ---------------------------------- |
| **`.container`** | 컨테이너 내에서 유일한 인스턴스를 생성하고 공유합니다. (싱글턴과 유사)                                       | `NetworkService`, `Database` 등    |
| **`.cached`** | 인스턴스를 생성 후 내부 캐시에 저장합니다. TTL, LRU/FIFO 정책에 따라 자동으로 제거될 수 있습니다.               | 사용자 프로필, 설정 등 자주 바뀌는 데이터 |
| **`.transient`** | 의존성을 해결할 때마다 새로운 인스턴스를 생성합니다.                                                         | `ViewModel`, `Presenter` 등        |

### 모듈 시스템 (Modules)

`Module`을 사용하면 앱의 기능을 중심으로 의존성을 구성할 수 있어 프로젝트가 커져도 관리가 용이합니다.

```swift
struct SettingsModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        builder.register(...) // 설정 관련 의존성들
    }
}

let container = await WeaverContainer.builder()
    .withModules([ArticleModule(), SettingsModule()])
    .build()
```

### `@Inject` 프로퍼티 래퍼

`@Inject`를 사용하면 의존성 해결 로직을 실제 사용처에서 분리하여 코드를 더욱 깔끔하게 만들 수 있습니다.

```swift
class MyViewModel {
    @Inject(MyServiceKey.self) private var myService

    func doSomething() async {
        // myService()는 async throws이므로 try await과 함께 사용 가능
        try? await myService().performAction()
    }
}
```

`callAsFunction` `()`을 호출하면 현재 `Weaver.scope`에 설정된 컨테이너에서 의존성을 자동으로 해결합니다.

### 부모-자식 컨테이너 (Hierarchical Containers)

테스트나 특정 기능 분기를 위해 기존 의존성을 쉽게 교체할 수 있습니다.

```swift
// 1. 실제 네트워크 클라이언트를 사용하는 메인 컨테이너
let mainContainer = await WeaverContainer.builder()
    .register(NetworkServiceKey.self) { _ in RealNetworkClient() }
    .build()

// 2. 테스트를 위해 Mock 네트워크 클라이언트를 사용하도록 오버라이드하는 자식 컨테이너
let testContainer = await WeaverContainer.builder()
    .withParent(mainContainer) // 부모 컨테이너 설정
    .register(NetworkServiceKey.self) { _ in MockNetworkClient() } // 의존성 오버라이드
    .build()

// testContainer에서 NetworkService를 해결하면 MockNetworkClient가 반환됩니다.
let client = try await testContainer.resolve(NetworkServiceKey.self) // client is a MockNetworkClient
```

### 도구 활용 (Tooling)

`Weaver`는 강력한 디버깅 및 분석 도구를 제공합니다.

  * **성능 측정 (Metrics)**

    컨테이너의 의존성 해결 성능을 분석할 수 있습니다.

    ```swift
    let metrics = await container.getMetrics()
    print(metrics)
    ```

    **출력 예시:**

    ```
    Resolution Metrics:
    - Total Resolutions: 152
    - Success Rate: 99.3%
    - Failed Resolutions: 1
    - Cache Hit Rate: 85.0% (Hits: 85, Misses: 15)
    - Avg. Resolution Time: 0.0241ms
    ```

  * **의존성 그래프 (Dependency Graph)**

    등록된 의존성들의 관계를 시각화할 수 있습니다.

    ```swift
    let dotGraph = container.getDependencyGraph().generateDotGraph()
    print(dotGraph)
    ```

    **출력 예시 (DOT Format):**

    ```dot
    digraph Dependencies {
      rankdir=TB;
      node [shape=box, style=rounded];
      "AuthServiceKey" [fillcolor=lightgreen, style=filled];
      "NetworkServiceKey" [fillcolor=lightgreen, style=filled];
      "CacheServiceKey" [fillcolor=khaki, style=filled];
      "ArticleServiceKey" [fillcolor=lightgreen, style=filled];
    }
    ```

    이 텍스트를 Graphviz 뷰어에 붙여넣으면 의존성 그래프를 이미지로 볼 수 있습니다.

-----

## License

`Weaver` is released under the MIT license. See [LICENSE](https://www.google.com/search?q=LICENSE) for details.

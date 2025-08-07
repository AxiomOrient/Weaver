# Weaver: 완전한 API 레퍼런스

> 🚀 **Swift 6 완전 호환** | **절대 크래시하지 않는 안전한 DI** | **프로덕션 검증 완료**

`Weaver`는 최신 Swift Concurrency(`async/await`, `actor`)를 기반으로 설계된 차세대 의존성 주입 라이브러리입니다. **절대 크래시하지 않는** 안전한 설계와 **iOS 15+ 완벽 호환성**으로 실제 프로덕션 환경에서 검증되었습니다.

이 문서는 `Weaver`의 모든 Public API와 실용적인 사용 예제를 포함한 완전한 레퍼런스입니다.

## 🎯 API 설계 철학

### 1. 안전성 우선 (Safety First)
```swift
// ❌ 다른 라이브러리들의 일반적인 문제
let service = container.resolve(UserService.self)! // 💥 크래시 위험

// ✅ Weaver의 해결책
@Inject(UserServiceKey.self) private var userService
let service = await userService() // ✨ 절대 크래시하지 않음
```

### 2. 타입 안전성 (Type Safety)
```swift
// 컴파일 타임에 모든 타입 검증
struct UserServiceKey: DependencyKey {
    typealias Value = UserService // 타입 명시
    static var defaultValue: UserService { MockUserService() } // 안전한 기본값
}
```

### 3. 현대적 동시성 (Modern Concurrency)
```swift
// Swift 6 Actor 기반 동시성 완전 지원
public actor WeaverContainer: Resolver {
    // 모든 상태가 Actor로 보호됨
}
```

---

## 📚 목차

1.  [**핵심 개념 (Core Concepts)**](#1-핵심-개념-core-concepts)
    *   [스코프 시스템 (Scope System)](#스코프-시스템-scope-system)
2.  [**시작하기 (Getting Started)**](#2-시작하기-getting-started)
3.  [**API 레퍼런스 (API Reference)**](#3-api-레퍼런스-api-reference)
    *   [전역 인터페이스: `Weaver`](#전역-인터페이스-weaver)
    *   [의존성 주입: `@Inject`](#의존성-주입-inject)
    *   [컨테이너 설정: `WeaverBuilder`](#컨테이너-설정-weaverbuilder)
    *   [모듈화: `Module`](#모듈화-module)
    *   [커널과 생명주기: `WeaverKernel`](#커널과-생명주기-weaverkernel)
    *   [핵심 프로토콜](#핵심-프로토콜)
    *   [SwiftUI 통합](#swiftui-통합)
    *   [에러 처리](#에러-처리)
4.  [**고급 주제 (Advanced Topics)**](#4-고급-주제-advanced-topics)
    *   [서비스 초기화 순서 제어](#서비스-초기화-순서-제어)
    *   [성능 모니터링](#성능-모니터링)
5.  [**유틸리티 (Utilities)**](#5-유틸리티-utilities)

---

## 1. 핵심 개념 (Core Concepts)

`Weaver`를 효과적으로 사용하기 위해 알아야 할 핵심 개념입니다.

### 스코프 시스템 (Scope System)

`Weaver`는 의존성의 생명주기를 관리하기 위해 4가지의 명확한 **스코프(Scope)**를 제공합니다. 스코프는 의존성을 등록할 때 지정하며, 인스턴스가 언제 생성되고, 얼마나 오래 유지되며, 어떻게 공유될지를 결정합니다.

| 스코프         | 설명                                                              | 사용 예시                               |
| :------------- | :---------------------------------------------------------------- | :-------------------------------------- |
| **`.startup`** | **앱 시작 시 즉시 로딩**되는 필수 서비스입니다.                     | 로깅, 크래시 리포팅, 기본 설정 등       |
| **`.shared`**  | **앱 전체에서 단일 인스턴스를 공유**합니다 (싱글톤).                | 데이터베이스 연결, 네트워크 클라이언트  |
| **`.whenNeeded`** | **실제 사용될 때만 로딩**되는 지연(lazy) 초기화 서비스입니다.     | 카메라, 결제 모듈, 위치 서비스 등       |
| **`.weak`**    | **약한 참조(weak reference)**로 관리되어 메모리 누수를 방지합니다. | 캐시, 델리게이트, 콜백 클로저를 갖는 객체 |

> 💡 **참고**: 과거 `InitializationTiming`은 스코프 시스템에 통합되어 더 이상 사용되지 않습니다. 스코프를 지정하면 최적의 초기화 시점이 자동으로 결정됩니다.

---

## 2. 빠른 시작 가이드 (Quick Start)

### 🚀 3단계로 시작하기

#### 1단계: 의존성 키 정의 (30초)

```swift
import Weaver

// 1️⃣ 서비스 프로토콜 정의
protocol UserService: Sendable {
    func getCurrentUser() async throws -> User?
    func updateProfile(_ user: User) async throws
}

// 2️⃣ 실제 구현체
final class APIUserService: UserService {
    private let networkClient: NetworkClient
    
    init(networkClient: NetworkClient) {
        self.networkClient = networkClient
    }
    
    func getCurrentUser() async throws -> User? {
        return try await networkClient.get("/user/me")
    }
    
    func updateProfile(_ user: User) async throws {
        try await networkClient.put("/user/profile", body: user)
    }
}

// 3️⃣ 의존성 키 정의 (타입 안전성의 핵심!)
struct UserServiceKey: DependencyKey {
    typealias Value = UserService
    
    // 🎯 크래시 방지를 위한 안전한 기본값
    static var defaultValue: UserService { 
        MockUserService() // Preview나 테스트에서 사용
    }
}

// 4️⃣ Mock 구현체 (테스트/Preview용)
final class MockUserService: UserService {
    func getCurrentUser() async throws -> User? {
        return User(id: "mock", name: "Test User", email: "test@example.com")
    }
    
    func updateProfile(_ user: User) async throws {
        print("Mock: Profile updated for \(user.name)")
    }
}
```

**💡 Pro Tip**: `defaultValue`는 절대 `fatalError()`를 사용하지 마세요! SwiftUI Preview에서 크래시가 발생합니다.

#### 2단계: 모듈로 의존성 그룹화 (1분)

```swift
// 사용자 관련 서비스들을 하나의 모듈로 그룹화
struct UserModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        // 네트워크 클라이언트 (공유 인스턴스)
        await builder.register(NetworkClientKey.self, scope: .shared) { _ in
            URLSessionNetworkClient(baseURL: "https://api.myapp.com")
        }
        
        // 사용자 서비스 (네트워크 클라이언트에 의존)
        await builder.register(UserServiceKey.self, scope: .shared) { resolver in
            let networkClient = try await resolver.resolve(NetworkClientKey.self)
            return APIUserService(networkClient: networkClient)
        }
        
        // 사용자 캐시 (약한 참조로 메모리 효율적 관리)
        await builder.registerWeak(UserCacheKey.self) { _ in
            UserCache()
        }
    }
}
```

#### 3단계: 앱에서 사용하기 (30초)

```swift
// App.swift - 앱 초기화
@main
struct MyApp: App {
    init() {
        Task {
            try await Weaver.setup(modules: [
                CoreModule(),      // 로깅, 설정 등
                NetworkModule(),   // 네트워크 관련
                UserModule(),      // 사용자 관련
                FeatureModule()    // 기능별 서비스
            ])
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// SwiftUI View에서 사용
struct UserProfileView: View {
    @Inject(UserServiceKey.self) private var userService
    @State private var user: User?
    
    var body: some View {
        VStack {
            if let user = user {
                Text("안녕하세요, \(user.name)님!")
            } else {
                ProgressView("로딩 중...")
            }
        }
        .task {
            // 🎯 절대 크래시하지 않는 안전한 접근
            let service = await userService()
            user = try? await service.getCurrentUser()
        }
    }
}

// SwiftUI Preview에서 Mock 사용
#Preview {
    UserProfileView()
        .weaver(modules: PreviewWeaverContainer.previewModules(
            .register(UserServiceKey.self, mockValue: MockUserService())
        ))
}
```

**🎉 완성!** 이제 앱 어디서든 `@Inject`로 안전하게 의존성을 사용할 수 있습니다.

**2. 모듈(Module) 정의**

관련된 의존성들을 `Module`로 그룹화하여 등록 로직을 구성합니다.

```swift
// AppServicesModule.swift
import Weaver

struct AppServicesModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        // LoggerKey를 ProductionLogger 구현체와 연결
        // .startup 스코프로 지정하여 앱 시작 시 즉시 로딩
        await builder.register(LoggerKey.self, scope: .startup) { _ in
            ProductionLogger()
        }

        // 다른 서비스들도 등록...
    }
}
```

**3. 앱 시작점(Entry Point)에서 `Weaver` 설정**

앱이 시작될 때 `Weaver.setup`을 호출하여 DI 커널을 초기화합니다.

```swift
// MyApp.swift
import SwiftUI
import Weaver

@main
struct MyApp: App {
    init() {
        // 앱이 시작될 때 모듈을 전달하여 Weaver 설정
        Task {
            do {
                try await Weaver.setup(modules: [AppServicesModule()])
                print("✅ Weaver DI 시스템이 성공적으로 초기화되었습니다.")
            } catch {
                fatalError("🚨 Weaver 초기화 실패: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**4. `@Inject`로 의존성 사용**

이제 앱의 어느 곳에서든 `@Inject` 프로퍼티 래퍼를 사용하여 의존성을 주입받을 수 있습니다.

```swift
// MyViewModel.swift
import Weaver

class MyViewModel: ObservableObject {
    // 1. @Inject로 의존성 선언
    @Inject(LoggerKey.self) private var logger

    func performSomeAction() async {
        // 2. 함수처럼 호출하여 안전하게 의존성 사용
        let log = await logger()
        log.info("사용자 작업이 수행되었습니다.")
    }
}
```

---

## 3. API 레퍼런스 (API Reference)

### 전역 인터페이스: `Weaver`

`Weaver`는 DI 시스템의 전역 상태와 상호작용하기 위한 정적(static) API를 제공하는 네임스페이스입니다.

```swift
public enum Weaver {
    /// 현재 작업 범위(TaskLocal)에 활성화된 `WeaverContainer`입니다.
    public static var current: WeaverContainer? { get async }

    /// 현재 전역 커널의 생명주기 상태를 반환합니다.
    public static var currentKernelState: LifecycleState { get async }

    /// 전역 커널을 설정합니다. 앱 초기화 시 `setup` 메서드를 통해 자동으로 호출됩니다.
    public static func setGlobalKernel(_ kernel: (any WeaverKernelProtocol)?) async

    /// 전역 커널 인스턴스를 반환합니다.
    public static func getGlobalKernel() async -> (any WeaverKernelProtocol)?

    /// **(권장)** 어떤 상황에서도 크래시하지 않고 안전하게 의존성을 해결합니다.
    /// 실패 시 `DependencyKey`의 `defaultValue`를 반환합니다.
    public static func safeResolve<Key: DependencyKey>(_ keyType: Key.Type) async -> Key.Value

    /// 커널이 의존성을 해결할 수 있는 준비 상태가 될 때까지 기다립니다.
    public static func waitForReady() async throws -> any Resolver

    /// 특정 컨테이너를 현재 작업 범위로 설정하고 주어진 작업을 실행합니다.
    /// SwiftUI View의 생명주기나 특정 로직 흐름에 맞춰 DI 범위를 지정할 때 유용합니다.
    public static func withScope<R: Sendable>(
        _ container: WeaverContainer,
        operation: @Sendable () async throws -> R
    ) async rethrows -> R

    /// 앱 생명주기 이벤트를 전역 커널에 전파합니다.
    public static func handleAppLifecycleEvent(_ event: AppLifecycleEvent) async

    /// **(앱 초기화)** 앱 시작 시 의존성 시스템을 초기화하는 표준 메서드입니다.
    public static func setup(modules: [Module]) async throws

    /// **(테스트용)** 테스트 간 상태 격리를 위해 모든 전역 상태를 초기화합니다.
    public static func resetForTesting() async
}
```

### 의존성 주입: `@Inject`

클래스나 구조체 내에서 의존성을 선언하고 주입받기 위한 프로퍼티 래퍼입니다.

```swift
@propertyWrapper
public struct Inject<Key: DependencyKey>: Sendable {
    /// 주입받을 의존성의 `DependencyKey` 타입을 지정하여 초기화합니다.
    public init(_ keyType: Key.Type)

    // --- 사용 방법 ---

    /// **1. 안전한 해결 (기본)**
    /// `myService()`처럼 함수로 호출하여 의존성을 가져옵니다.
    /// 해결에 실패해도 크래시하지 않고 `defaultValue`를 반환하여 안정성을 보장합니다.
    public func callAsFunction() async -> Key.Value

    /// **2. 명시적 에러 처리**
    /// `$myService`처럼 `$` 접두사로 접근하여 `resolve()` 메서드를 호출합니다.
    /// 의존성 해결에 실패하면 에러를 던져(throw) 명시적인 처리를 강제합니다.
    public var projectedValue: InjectProjection<Key> { get }
}

public struct InjectProjection<Key: DependencyKey>: Sendable {
    /// 의존성을 해결하고, 실패 시 `WeaverError`를 던집니다.
    public func resolve() async throws -> Key.Value
}
```

**사용 예시:**

```swift
class MyRepository {
    @Inject(LoggerKey.self) private var logger

    func fetchData() async {
        // 1. 안전한 사용 (권장)
        let log = await logger()
        log.info("데이터를 가져옵니다.")

        // 2. 명시적 에러 처리
        do {
            let network = try await $networkService.resolve()
            // ...
        } catch {
            log.info("네트워크 서비스 해결 실패: \(error)")
        }
    }
}
```

### 컨테이너 설정: `WeaverBuilder`

플루언트(fluent) 인터페이스를 통해 `WeaverContainer`를 설정하고 생성하는 `actor`입니다.

```swift
public actor WeaverBuilder {
    public init()

    /// 의존성을 등록합니다.
    @discardableResult
    public func register<Key: DependencyKey>(
        _ keyType: Key.Type,
        scope: Scope = .shared,
        factory: @escaping @Sendable (Resolver) async throws -> Key.Value
    ) -> Self

    /// 약한 참조(.weak) 스코프 의존성을 등록합니다.
    /// `Key.Value`가 클래스(AnyObject) 타입이어야 함을 컴파일 시점에 보장합니다.
    @discardableResult
    public func registerWeak<Key: DependencyKey>(
        _ keyType: Key.Type,
        factory: @escaping @Sendable (Resolver) async throws -> Key.Value
    ) -> Self where Key.Value: AnyObject

    /// 등록할 모듈들을 추가합니다.
    @discardableResult
    public func withModules(_ modules: [Module]) -> Self

    /// 서비스 초기화 순서를 제어할 커스텀 로직을 제공합니다.
    @discardableResult
    public func withPriorityProvider(_ provider: ServicePriorityProvider) -> Self

    /// (테스트용) 기존 등록 정보를 다른 구현으로 덮어씁니다.
    @discardableResult
    public func override<Key: DependencyKey>(
        _ keyType: Key.Type,
        scope: Scope = .shared,
        factory: @escaping @Sendable (Resolver) async throws -> Key.Value
    ) -> Self

    /// 설정된 내용으로 `WeaverContainer`를 생성합니다.
    public func build() async -> WeaverContainer
}
```

### 모듈화: `Module`

관련된 의존성 등록 로직을 그룹화하기 위한 프로토콜입니다. 앱의 기능 단위나 계층별로 모듈을 작성하여 DI 설정을 체계적으로 관리할 수 있습니다.

```swift
public protocol Module: Sendable {
    /// `WeaverBuilder`를 사용하여 의존성을 등록하는 로직을 구현합니다.
    func configure(_ builder: WeaverBuilder) async
}
```

**사용 예시:**

```swift
struct DataLayerModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(NetworkServiceKey.self, scope: .shared) { _ in
            URLSessionNetworkService()
        }
        await builder.register(DatabaseServiceKey.self, scope: .shared) { _ in
            CoreDataDatabaseService()
        }
    }
}
```

### 커널과 생명주기: `WeaverKernel`

`WeaverKernel`은 스코프 기반의 점진적 로딩을 지원하는 DI 시스템의 핵심 `actor`입니다. 앱의 생명주기와 DI 시스템의 상태를 동기화합니다.

```swift
public actor WeaverKernel: WeaverKernelProtocol, Resolver {
    /// 스코프 기반 커널을 생성합니다.
    public static func scoped(modules: [Module], logger: WeaverLogger = DefaultLogger()) -> WeaverKernel

    /// 커널의 현재 상태를 방출하는 비동기 스트림입니다.
    public var stateStream: AsyncStream<LifecycleState> { get }

    /// 등록된 모듈을 기반으로 커널을 빌드하고 `startup` 스코프를 활성화합니다.
    public func build() async

    /// 활성화된 모든 컨테이너를 안전하게 종료하고 리소스를 해제합니다.
    public func shutdown() async
}
```

`LifecycleState`는 커널의 현재 상태를 나타내는 열거형입니다.

```swift
public enum LifecycleState: Sendable, Equatable {
    case idle       // 초기 상태
    case configuring// 구성 중
    case warmingUp(progress: Double) // Eager-scope 의존성 초기화 중
    case ready(Resolver) // 의존성 해결 가능 상태
    case failed(any Error & Sendable) // 빌드 또는 초기화 실패
    case shutdown   // 모든 리소스 해제됨
}
```

### 핵심 프로토콜

`Weaver`의 아키텍처를 구성하는 핵심 프로토콜입니다.

-   `DependencyKey`: 의존성의 타입과 기본값을 정의합니다. (시작하기 섹션 참고)
-   `Resolver`: `resolve` 메서드를 통해 의존성을 해결하는 기능을 정의합니다. `WeaverContainer`와 `WeaverKernel`이 이를 준수합니다.
-   `Disposable`: 컨테이너가 종료될 때(`shutdown`) 정리(`dispose`) 작업이 필요한 객체가 채택합니다. 네트워크 연결 종료, 파일 핸들러 닫기 등에 사용됩니다.

    ```swift
    protocol Disposable: Sendable {
        func dispose() async throws
    }
    ```

### SwiftUI 통합

#### `.weaver` View Modifier

SwiftUI View에 `Weaver` DI 컨테이너를 손쉽게 통합합니다.

```swift
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public extension View {
    /// View의 생명주기에 맞춰 DI 컨테이너를 설정합니다.
    func weaver(
        modules: [Module],
        setAsGlobal: Bool = true, // 전역 커널로 설정할지 여부
        @ViewBuilder loadingView: @escaping () -> some View // 의존성 준비 중 표시할 뷰
    ) -> some View
}
```

**사용 예시:**

```swift
struct MyRootView: View {
    var body: some View {
        NavigationView {
            MyFeatureView()
        }
        .weaver(modules: [MyFeatureModule()])
    }
}
```

#### `PreviewWeaverContainer`

SwiftUI Preview에서 타입 안전하게 Mock 의존성을 주입하기 위한 헬퍼입니다.

```swift
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct PreviewWeaverContainer {
    /// 여러 Preview용 의존성을 선언적으로 등록하여 모듈 배열을 생성합니다.
    public static func previewModules(_ registrations: PreviewRegistration...) -> [Module]

    /// 타입 안전한 Preview 등록을 위한 헬퍼 구조체
    public struct PreviewRegistration: Sendable {
        /// 값 기반 Mock 객체 등록
        public static func register<Key: DependencyKey>(
            _ keyType: Key.Type,
            mockValue: Key.Value,
            scope: Scope = .shared
        ) -> PreviewRegistration

        /// 팩토리 기반 Mock 객체 등록
        public static func register<Key: DependencyKey>(
            _ keyType: Key.Type,
            scope: Scope = .shared,
            factory: @escaping @Sendable (Resolver) async throws -> Key.Value
        ) -> PreviewRegistration
    }
}
```

**사용 예시:**

```swift
struct MyFeatureView_Previews: PreviewProvider {
    static var previews: some View {
        MyFeatureView()
            .weaver(modules: PreviewWeaverContainer.previewModules(
                .register(LoggerKey.self, mockValue: ConsoleLogger()),
                .register(NetworkServiceKey.self, mockValue: MockNetworkService(data: "성공"))
            ))
    }
}
```

### 에러 처리

`Weaver`는 명확하고 구조화된 에러 타입을 제공하여 문제 해결을 돕습니다.

-   `WeaverError`: 라이브러리에서 발생하는 최상위 에러 타입입니다.
    -   `.containerNotFound`: 활성화된 컨테이너를 찾을 수 없음.
    -   `.containerNotReady`: 컨테이너가 아직 준비되지 않음.
    -   `.resolutionFailed`: 의존성 해결 실패 (자세한 원인은 `ResolutionError`에 포함).
-   `ResolutionError`: 의존성 해결 과정에서 발생하는 구체적인 에러 타입입니다.
    -   `.circularDependency`: 순환 참조 감지.
    -   `.factoryFailed`: 인스턴스 생성(factory) 클로저에서 에러 발생.
    -   `.typeMismatch`: 예상 타입과 실제 타입이 일치하지 않음.
    -   `.keyNotFound`: 등록되지 않은 키를 해결하려고 시도함.

---

## 4. 고급 주제 (Advanced Topics)

### 서비스 초기화 순서 제어

복잡한 앱에서는 서비스 간의 초기화 순서가 중요할 수 있습니다. `Weaver`는 `ServicePriorityProvider` 프로토콜을 통해 이 순서를 제어할 수 있는 확장 포인트를 제공합니다.

```swift
public protocol ServicePriorityProvider: Sendable {
    /// 서비스의 우선순위 값을 반환합니다. (값이 낮을수록 먼저 초기화)
    func getPriority(for key: AnyDependencyKey, registration: DependencyRegistration) async -> Int
}
```

**사용법:**

1.  `ServicePriorityProvider`를 준수하는 커스텀 제공자를 만듭니다.
2.  `WeaverBuilder`의 `withPriorityProvider` 메서드를 사용하여 커스텀 제공자를 등록합니다.

```swift
// 1. 커스텀 우선순위 제공자 정의
struct MyPriorityProvider: ServicePriorityProvider {
    func getPriority(for key: AnyDependencyKey, ...) async -> Int {
        if key.description == "CriticalCrashReporterKey" {
            return -100 // 최우선 순위
        }
        // ... 기타 로직
        return await DefaultServicePriorityProvider().getPriority(for: key, ...)
    }
}

// 2. 빌더에 등록
let builder = WeaverContainer.builder()
    .withModules([AppModule()])
    .withPriorityProvider(MyPriorityProvider())
```

### 성능 모니터링

`WeaverPerformanceMonitor`를 사용하여 DI 시스템의 성능을 측정하고 병목 현상을 분석할 수 있습니다.

```swift
public actor WeaverPerformanceMonitor {
    /// 모니터링 활성화 여부를 지정하여 초기화합니다. (기본값: DEBUG 빌드에서만 활성화)
    public init(enabled: Bool = WeaverEnvironment.isDevelopment, ...)

    /// 주어진 작업의 실행 시간을 측정합니다.
    public func measureResolution<T: Sendable>(keyName: String, operation: ...) async rethrows -> T

    /// 현재 메모리 사용량을 기록합니다.
    public func recordMemoryUsage() async

    /// 수집된 데이터를 바탕으로 성능 보고서를 생성합니다.
    public func generatePerformanceReport() async -> PerformanceReport
}
```

---

## 5. 실전 사용 패턴 (Real-World Patterns)

### 📱 완전한 앱 개발 시나리오

#### 패턴 1: 네트워크 + 캐시 + 에러 처리

```swift
// 1️⃣ 네트워크 에러 정의
enum NetworkError: Error, LocalizedError {
    case noInternet
    case serverError(Int)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .noInternet: return "인터넷 연결을 확인해주세요"
        case .serverError(let code): return "서버 오류 (코드: \(code))"
        case .invalidResponse: return "잘못된 응답입니다"
        }
    }
}

// 2️⃣ 캐시된 네트워크 서비스
final class CachedNetworkService: Sendable {
    private let networkClient: NetworkClient
    private let cache: ResponseCache
    
    init(networkClient: NetworkClient, cache: ResponseCache) {
        self.networkClient = networkClient
        self.cache = cache
    }
    
    func getCachedData<T: Codable>(_ endpoint: String, type: T.Type) async throws -> T {
        let cacheKey = "cached_\(endpoint)"
        
        // 캐시에서 먼저 확인
        if let cachedData = cache.get(cacheKey, type: T.self) {
            return cachedData
        }
        
        // 캐시 미스 시 네트워크 요청
        let data: T = try await networkClient.get(endpoint)
        cache.set(cacheKey, value: data)
        return data
    }
}

// 3️⃣ 모듈 구성
struct NetworkModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(NetworkClientKey.self, scope: .shared) { _ in
            URLSessionNetworkClient(baseURL: "https://api.myapp.com")
        }
        
        await builder.registerWeak(ResponseCacheKey.self) { _ in
            ResponseCache(maxSize: 100)
        }
        
        await builder.register(CachedNetworkServiceKey.self, scope: .shared) { resolver in
            let networkClient = try await resolver.resolve(NetworkClientKey.self)
            let cache = try await resolver.resolve(ResponseCacheKey.self)
            return CachedNetworkService(networkClient: networkClient, cache: cache)
        }
    }
}

// 4️⃣ SwiftUI에서 사용
struct UserListView: View {
    @Inject(CachedNetworkServiceKey.self) private var networkService
    @State private var users: [User] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("사용자 목록 로딩 중...")
                } else if users.isEmpty && errorMessage == nil {
                    Text("사용자가 없습니다")
                        .foregroundColor(.secondary)
                } else {
                    List(users) { user in
                        UserRowView(user: user)
                    }
                }
            }
            .navigationTitle("사용자 목록")
            .alert("오류", isPresented: .constant(errorMessage != nil)) {
                Button("확인") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .task { await loadUsers() }
        .refreshable { await loadUsers() }
    }
    
    private func loadUsers() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let service = await networkService()
            users = try await service.getCachedData("/users", type: [User].self)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

#### 패턴 2: 인증 + 토큰 자동 갱신

```swift
// 1️⃣ 인증 토큰 모델
struct AuthToken: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    
    var isExpired: Bool { Date() >= expiresAt }
    var willExpireSoon: Bool { Date().addingTimeInterval(300) >= expiresAt }
}

// 2️⃣ 인증 서비스
final class APIAuthService: AuthService {
    private let networkClient: NetworkClient
    private let secureStorage: SecureStorage
    
    init(networkClient: NetworkClient, secureStorage: SecureStorage) {
        self.networkClient = networkClient
        self.secureStorage = secureStorage
    }
    
    func getCurrentToken() async throws -> AuthToken? {
        guard let token = try await secureStorage.retrieve() else {
            return nil
        }
        
        // 토큰이 곧 만료되면 자동 갱신
        if token.willExpireSoon && !token.isExpired {
            return try await refreshToken()
        }
        
        return token.isExpired ? nil : token
    }
    
    private func refreshToken() async throws -> AuthToken {
        // 토큰 갱신 로직...
        // 실제 구현에서는 동시 갱신 방지를 위한 락 필요
    }
}

// 3️⃣ 인증이 필요한 네트워크 클라이언트
final class AuthenticatedNetworkClient: NetworkClient {
    private let baseClient: NetworkClient
    private let authService: AuthService
    
    init(baseClient: NetworkClient, authService: AuthService) {
        self.baseClient = baseClient
        self.authService = authService
    }
    
    func get<T: Codable>(_ endpoint: String) async throws -> T {
        guard let token = try await authService.getCurrentToken() else {
            throw AuthError.notAuthenticated
        }
        
        // Authorization 헤더 추가하여 요청
        return try await baseClient.get(endpoint)
    }
}
```

#### 패턴 3: A/B 테스트 시스템

```swift
// 1️⃣ A/B 테스트 매니저
protocol ABTestManager: Sendable {
    func getVariant(for experiment: String, userId: String) async -> String
    func isFeatureEnabled(_ feature: String, userId: String) async -> Bool
}

final class RemoteABTestManager: ABTestManager {
    private let networkClient: NetworkClient
    private let cache: ResponseCache
    
    init(networkClient: NetworkClient, cache: ResponseCache) {
        self.networkClient = networkClient
        self.cache = cache
    }
    
    func getVariant(for experiment: String, userId: String) async -> String {
        // 캐시 확인 → 서버 요청 → 결과 캐싱
        let cacheKey = "experiment_\(experiment)_\(userId)"
        
        if let cachedVariant = cache.get(cacheKey, type: String.self) {
            return cachedVariant
        }
        
        do {
            let variant: String = try await networkClient.get("/experiments/\(experiment)?userId=\(userId)")
            cache.set(cacheKey, value: variant)
            return variant
        } catch {
            return "control" // 에러 시 기본 변형
        }
    }
}

// 2️⃣ 조건부 서비스 생성
struct ABTestModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(ABTestManagerKey.self, scope: .shared) { resolver in
            let networkClient = try await resolver.resolve(NetworkClientKey.self)
            let cache = try await resolver.resolve(ResponseCacheKey.self)
            return RemoteABTestManager(networkClient: networkClient, cache: cache)
        }
        
        // 실험에 따른 동적 서비스 생성
        await builder.register(RecommendationServiceKey.self, scope: .whenNeeded) { resolver in
            let abTestManager = try await resolver.resolve(ABTestManagerKey.self)
            let userSession = try await resolver.resolve(UserSessionKey.self)
            let networkClient = try await resolver.resolve(NetworkClientKey.self)
            
            let variant = await abTestManager.getVariant(
                for: "recommendation_algorithm", 
                userId: userSession.currentUserId
            )
            
            switch variant {
            case "ml_enhanced":
                return MLRecommendationService(networkClient: networkClient)
            case "collaborative":
                return CollaborativeRecommendationService(networkClient: networkClient)
            default:
                return BasicRecommendationService(networkClient: networkClient)
            }
        }
    }
}
```

### 🔧 고급 패턴

#### 성능 최적화 패턴

```swift
// 1️⃣ 배치 의존성 해결
extension WeaverContainer {
    func resolveBatch<T1: DependencyKey, T2: DependencyKey, T3: DependencyKey>(
        _ key1: T1.Type, _ key2: T2.Type, _ key3: T3.Type
    ) async throws -> (T1.Value, T2.Value, T3.Value) {
        // 병렬로 해결하여 성능 최적화
        async let service1 = resolve(key1)
        async let service2 = resolve(key2)
        async let service3 = resolve(key3)
        
        return try await (service1, service2, service3)
    }
}

// 2️⃣ 조건부 지연 로딩
struct ConditionalModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        // 프리미엄 사용자만 전체 기능 로딩
        await builder.register(PremiumServiceKey.self, scope: .whenNeeded) { resolver in
            let userSession = try await resolver.resolve(UserSessionKey.self)
            
            guard userSession.isPremiumUser else {
                return LimitedPremiumService()
            }
            
            let networkClient = try await resolver.resolve(NetworkClientKey.self)
            return FullPremiumService(networkClient: networkClient)
        }
    }
}

// 3️⃣ 메모리 압박 시 자동 정리
class MemoryManager {
    @Inject(WeaverContainerKey.self) private var container
    
    init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { await self.handleMemoryWarning() }
        }
    }
    
    private func handleMemoryWarning() async {
        let weaverContainer = await container()
        await weaverContainer.performMemoryCleanup(forced: true)
    }
}
```

## 6. 유틸리티 및 헬퍼 (Utilities)

### 환경 감지
```swift
public enum WeaverEnvironment {
    /// SwiftUI Preview 환경 감지
    public static var isPreview: Bool
    
    /// 개발 환경 감지 (DEBUG 빌드)
    public static var isDevelopment: Bool
    
    /// 테스트 환경 감지
    public static var isTesting: Bool
}
```

### 안전한 기본값 헬퍼
```swift
public enum DefaultValueGuidelines {
    /// 환경별 기본값 제공
    static func safeDefault<T>(
        production: @autoclosure () -> T,
        preview: @autoclosure () -> T
    ) -> T
    
    /// 디버그/릴리즈 분기
    static func debugDefault<T>(
        debug: @autoclosure () -> T,
        release: @autoclosure () -> T
    ) -> T
}
```

### 플랫폼 호환성
```swift
/// iOS 15/16 호환 잠금 메커니즘
public struct PlatformAppropriateLock<State: Sendable>: Sendable {
    public init(initialState: State)
    public func withLock<R>(_ body: (inout State) throws -> R) rethrows -> R
    public var lockMechanismInfo: String { get } // 디버깅용
}
```

### 약한 참조 관리
```swift
/// Actor 기반 약한 참조 컨테이너
public actor WeakBox<T: AnyObject & Sendable>: Sendable {
    public init(_ value: T)
    public var isAlive: Bool { get }
    public func getValue() -> T?
    public var age: TimeInterval { get }
}
```
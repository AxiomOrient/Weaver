# Weaver 🕸️

**Weaver**는 Swift의 최신 동시성 모델(`async/await`, `actor`)을 기반으로 설계된, **타입-세이프(Type-Safe)하고 강력한 의존성 주입(Dependency Injection) 프레임워크**입니다. 데이터 경쟁(Data Race)으로부터 원천적으로 안전하며, 모든 Swift 환경(서버, UIKit, SwiftUI 등)에서 일관된 방식으로 동작합니다.

## ✨ 주요 특징

- **동시성 안전 설계 (Concurrency Safety)**: 핵심 컴포넌트인 `WeaverContainer`가 `actor`로 구현되어, 복잡한 락(lock) 없이도 스레드로부터 안전한 의존성 관리 및 해결을 보장합니다.
- **명확한 생명주기 관리 (Explicit Lifecycle)**: `WeaverKernel`을 통해 DI 컨테이너의 생성, 준비, 종료 등 전체 생명주기를 명시적으로 제어하고 관찰할 수 있습니다.
- **강력한 스코프 (Powerful Scopes)**:
    - `.container`: 최초 요청 시 한 번만 생성되는 **Lazy Singleton** 스코프.
    - `.eagerContainer`: 컨테이너 빌드 시점에 즉시 생성되는 **Eager Singleton** 스코프로, 비동기 초기화 문제를 우아하게 해결합니다.
    - `.weak`: 의존성을 **약한 참조(Weak Reference)**로 관리하여 순환 참조를 방지하고 메모리 관리를 돕습니다.
    - `.cached`: TTL, 개수 제한, LRU/FIFO 퇴출 정책을 지원하는 **고급 캐시** 스코프.
- **모듈화 및 재구성 (Modularity & Reconfiguration)**: 의존성 등록 로직을 `Module` 단위로 그룹화하여 코드를 체계적으로 관리할 수 있으며, `reconfigure`를 통해 실행 중에도 안전하게 컨테이너의 구성을 변경할 수 있습니다.
- **고급 기능 및 확장성 (Advanced Features & Extensibility)**:
    - **의존성 그래프 시각화**: 등록된 의존성 간의 관계를 시각적으로 파악할 수 있는 **그래프 생성 기능**을 제공하여 디버깅 및 아키텍처 분석을 돕습니다.
    - **사용자 정의 확장**: `WeaverLogger`, `CacheManaging` 등 프로토콜을 통해 로깅, 캐시 관리 등 핵심 동작을 직접 구현하여 교체할 수 있습니다.

---

## 🚀 시작하기: 기본 사용법

이 가이드는 **"초기화에 오래 걸리는 서비스를 앱 시작 시점에 안전하게 준비시키는 과정"**을 통해 `Weaver`의 핵심 기능을 단계별로 설명합니다.

### 1. 서비스 및 DependencyKey 정의

먼저, 앱에서 사용할 서비스와 각 서비스를 고유하게 식별할 `DependencyKey`를 정의합니다. `DependencyKey`는 의존성의 타입과 기본값을 정의하는 프로토콜입니다.

```swift
import Foundation
import Weaver

// --- 서비스 프로토콜 ---
protocol LoggerService: Sendable {
    func log(_ message: String)
}

protocol AuthenticationService: Sendable {
    var userID: String { get }
    func login()
}

// --- 서비스 구현체 ---
final class ProductionLogger: LoggerService {
    func log(_ message: String) { print("🪵 [Logger]: \(message)") }
}

// ⚠️ 초기화에 2초가 걸리는 무거운 서비스
final class FirebaseAuthService: AuthenticationService {
    let userID: String

    init(logger: LoggerService) async {
        logger.log("🔥 인증 서비스 초기화 시작... (2초 소요)")
        try? await Task.sleep(for: .seconds(2)) // 실제 앱에서는 비동기 네트워크 요청
        self.userID = "user_12345"
        logger.log("✅ 인증 서비스 초기화 완료!")
    }

    func login() {
        print("🎉 [Auth]: \(userID)님, 성공적으로 로그인되었습니다!")
    }
}

// --- DependencyKey 정의 ---
struct LoggerServiceKey: DependencyKey {
    // `defaultValue`는 컨테이너가 준비되지 않았을 때 사용될 안전한 기본값입니다.
    static var defaultValue: any LoggerService { ProductionLogger() }
}

struct AuthenticationServiceKey: DependencyKey {
    // 이 서비스는 반드시 컨테이너를 통해 생성되어야 하므로,
    // 기본값은 의도적으로 fatalError를 발생시켜 설정 오류를 빠르게 파악하도록 합니다.
    static var defaultValue: any AuthenticationService {
        fatalError("AuthenticationService는 반드시 컨테이너를 통해 주입되어야 합니다.")
    }
}
```

### 2. 모듈(Module) 정의 및 스코프 선택

관련된 의존성들을 `Module` 단위로 그룹화하여 등록 로직을 체계적으로 관리합니다. 각 서비스의 특성에 맞는 **스코프**를 지정하는 것이 중요합니다.

- **`scope: .container`**: `LoggerService`처럼 가볍고, 필요할 때 만들어도 되는 서비스에 적합합니다.
- **`scope: .eagerContainer`**: `AuthenticationService`처럼 무겁고 앱 시작에 필수적인 서비스에 사용합니다. 이것이 바로 `Weaver`가 비동기 초기화 문제를 해결하는 핵심입니다.

```swift
import Weaver

struct ServiceModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        // ✅ Logger는 가벼우므로, 필요할 때 생성 (.container)
        builder.register(LoggerServiceKey.self, scope: .container) { _ in
            ProductionLogger()
        }

        // ✅ 인증 서비스는 무겁고 필수적이므로, 즉시 생성 (.eagerContainer)
        builder.register(AuthenticationServiceKey.self, scope: .eagerContainer) { resolver in
            // 다른 서비스(logger)에 의존할 수 있습니다.
            let logger = try await resolver.resolve(LoggerServiceKey.self)
            return await FirebaseAuthService(logger: logger)
        }
    }
}
```

### 3. 커널(Kernel) 생성 및 생명주기 관리

`WeaverKernel`은 DI 컨테이너의 생명주기를 관리하는 핵심 컨트롤 타워입니다. 커널을 생성하고, 상태 변화를 관찰하며, 빌드를 시작합니다.

```swift
import Foundation

@main
struct Main {
    static func main() async {
        // 1. 모듈을 사용하여 커널을 생성합니다.
        let kernel = DefaultWeaverKernel(modules: [ServiceModule()])

        // 2. (선택) 커널의 상태 스트림을 구독하여 생명주기 변화를 관찰합니다.
        let stateObservationTask = Task {
            for await state in kernel.stateStream {
                switch state {
                case .idle: print("Kernel is idle.")
                case .configuring: print("Kernel is configuring modules...")
                case .warmingUp(let progress): print(String(format: "Warming up... %.0f%%", progress * 100))
                case .ready(let resolver):
                    print("✅ Kernel is ready! Starting application...")
                    await startApplication(with: resolver)
                case .failed(let error): print("❌ Kernel failed to build: \(error)")
                case .shutdown: print("Kernel has shut down.")
                }
            }
        }

        // 3. 컨테이너 빌드를 시작합니다. 이 과정은 비동기적으로 수행됩니다.
        await kernel.build()

        // 작업이 끝나면 커널을 종료합니다.
        await kernel.shutdown()
        stateObservationTask.cancel()
    }

    static func startApplication(with resolver: Resolver) async {
        print("--- App Started ---")
        // 이 시점에는 2초가 걸리는 인증 서비스가 이미 준비되어 있습니다.
        do {
            let authService = try await resolver.resolve(AuthenticationServiceKey.self)
            authService.login()
        } catch {
            print("Error resolving service: \(error)")
        }
        print("--- App Finished ---")
    }
}
```

### 4. 의존성 사용하기: @Inject

`@Inject` 프로퍼티 래퍼를 사용하면 어떤 객체에서든 간결하게 의존성을 주입받을 수 있습니다.

```swift
class UserManager {
    // 전역 컨테이너(`Weaver.current`)를 통해 의존성을 주입받습니다.
    @Inject(AuthenticationServiceKey.self)
    private var authService

    func performLogin() async {
        // `await authService()`: non-throwing API, 실패 시 defaultValue 반환
        await authService().login()
    }

    func forceLogin() async throws {
        // `try await $authService.resolved`: throwing API, 실패 시 에러 발생
        let service = try await $authService.resolved
        service.login()
    }
}

// `Weaver.withScope`를 사용하여 특정 작업 범위에 컨테이너를 설정해주어야 합니다.
// `WeaverHost` 또는 `.weaver()`를 사용하면 SwiftUI 환경에서는 자동으로 처리됩니다.
// await Weaver.withScope(resolver) {
//     let userManager = UserManager()
//     await userManager.performLogin()
// }
```

### 실행 결과 🎬

1.  **앱 시작**: `Kernel is idle.` 출력 후 `Kernel is configuring modules...`가 출력됩니다.
2.  **백그라운드 준비**: `Warming up... 0%` 부터 `Warming up... 100%` 까지 출력되며, 백그라운드에서 `FirebaseAuthService`가 초기화됩니다. (2초 소요)
3.  **준비 완료**: `✅ Kernel is ready! Starting application...` 메시지가 출력됩니다.
4.  **애플리케이션 로직 실행**: `startApplication` 함수가 호출되고, **아무런 딜레이 없이** 즉시 인증 서비스의 `login()` 메서드가 실행됩니다.

이것이 바로 `Weaver`가 비싼 초기화 비용을 앱의 주요 로직 실행 전에 미리 처리하여, 사용자에게 항상 완벽하게 준비된 상태의 앱을 제공하는 방식입니다.

---

## 🔬 고급 기능

### 약한 참조(Weak) 스코프

`.weak` 스코프는 의존성을 약한 참조로 관리하여 순환 참조 문제를 방지합니다. 의존성 객체가 클래스여야 하며, 더 이상 다른 곳에서 참조되지 않으면 컨테이너에서도 자동으로 메모리가 해제됩니다.

```swift
// 부모-자식 관계처럼 순환 참조가 발생할 수 있는 경우
builder.register(ChildServiceKey.self, scope: .weak) { resolver in
    let parent = try await resolver.resolve(ParentServiceKey.self)
    return ChildService(parent: parent)
}
```

### 특정 Resolver로 의존성 주입

테스트나 특정 자식 컨테이너의 `Resolver`를 명시적으로 사용하고 싶을 때, `projectedValue`(`$`)의 `from(_:)` 메서드를 사용할 수 있습니다.

```swift
// 테스트 코드 예시
func testUserManager() async {
    // 테스트용 Mock Resolver 생성
    let mockResolver = await WeaverContainer.builder()
        .override(AuthenticationServiceKey.self) { _ in MockAuthService() }
        .build()

    let userManager = UserManager()

    // 이제 userManager는 MockAuthService를 사용합니다.
    await userManager.performLogin(from: mockResolver)
}

class UserManager {
    @Inject(AuthenticationServiceKey.self)
    private var authService

    // 기본: 전역 Weaver.current 사용
    func performLogin() async {
        await authService().login()
    }

    // 고급: 특정 Resolver를 지정하여 사용
    func performLogin(from resolver: Resolver) async {
        do {
            // `$authService.from(resolver)`를 통해 특정 리졸버에서 의존성을 해결합니다.
            let service = try await $authService.from(resolver)
            service.login()
        } catch {
            print("Error: \(error)")
        }
    }
}
```

## 📜 라이선스

Weaver는 MIT 라이선스에 따라 제공됩니다.
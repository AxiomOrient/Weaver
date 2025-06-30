# Weaver 라이브러리 분석 정보

> 이 문서는 Weaver DI 라이브러리의 내부 아키텍처, 핵심 개념, 설계 원칙을 설명하여 개발자가 코드베이스를 직접 분석하지 않고도 라이브러리를 깊이 있게 이해하고 활용할 수 있도록 돕는 것을 목표로 합니다.

## 1. 개요 (Overview)

**Weaver**는 Swift의 최신 동시성(Concurrency) 모델을 기반으로 설계된 타입-세이프(Type-Safe) 의존성 주입(Dependency Injection) 라이브러리입니다. `actor`와 `Sendable`을 적극적으로 활용하여 데이터 경쟁(Data Race)으로부터 안전하며, 비동기 환경에서 의존성을 해결하는 데 최적화되어 있습니다.

### 주요 특징 (Key Features)

- **타입-세이프 의존성 해결**: `DependencyKey` 프로토콜을 통해 컴파일 타임에 의존성의 타입을 검증합니다.
- **동시성 안전 (Concurrency-Safe)**: `actor` 기반의 컨테이너와 관리자를 통해 스레드로부터 안전한 의존성 관리 및 해결을 보장합니다.
- **플루언트 빌더 API (Fluent Builder API)**: 체이닝(Chaining) 방식의 빌더를 제공하여 `WeaverContainer`를 직관적이고 가독성 높게 구성할 수 있습니다.
- **`@Inject` 프로퍼티 래퍼**: 의존성 주입을 위한 간결하고 현대적인 API를 제공합니다.
- **다양한 스코프 지원**: `.container`(싱글턴) 및 `.cached`(캐시) 스코프를 지원하여 의존성의 생명주기를 관리합니다.
- **고급 캐싱 시스템**: TTL(Time-To-Live), LRU/FIFO 퇴출 정책, 메모리 압박 감지 등 정교한 캐시 전략을 지원합니다.
- **메트릭 수집**: 의존성 해결 시간, 캐시 히트율 등 성능 분석을 위한 메트릭을 수집하고 조회할 수 있습니다.
- **계층적 컨테이너**: 부모-자식 관계의 컨테이너를 구성하여 의존성 검색 범위를 확장하고 오버라이드할 수 있습니다.
- **순환 참조 감지**: `@TaskLocal`을 활용하여 런타임에 순환 참조를 감지하고 오류를 발생시킵니다.
- **의존성 그래프 시각화**: 등록된 의존성 관계를 Graphviz(DOT) 형식으로 시각화하여 디버깅을 지원합니다.

---

## 2. 핵심 아키텍처 및 구성 요소

Weaver는 명확한 역할 분리를 통해 유연하고 확장 가능한 구조를 가집니다.

 graph TD
    subgraph "1. 설정 (Configuration Phase)"
        direction LR
        UserBuilder["사용자 코드"] -- "WeaverContainer.builder()" --> Builder(WeaverBuilder);
        Builder -- ".register(Service.self, ...)" --> Registrations{의존성 등록 정보};
        Builder -- ".withModules(...)" --> Module(Module);
        Module -- ".configure(builder)" --> Builder;
        Builder -- ".enableAdvancedCaching()" --> Builder;
        Builder -- ".build()" --> Container(WeaverContainer);
    end

    subgraph "2. 해결 (Resolution Phase)"
        direction TD
        UserInject["사용자 코드 (@Inject)"] -- "await service()" --> WeaverScope(Weaver Scope);
        WeaverScope -- "@TaskLocal로 현재 컨테이너 제공" --> Container;
        UserInject -- "container.resolve()" --> Container;
        Container -- "스코프 확인" --> ScopeDecision{Scope?};
        ScopeDecision -- ".container" --> ContainerCache["컨테이너 내부 캐시"];
        ScopeDecision -- ".cached" --> CacheManager(CacheManaging);
        ContainerCache --> Instance([Instance]);
        CacheManager --> Instance;
        Instance --> UserInject;
    end

    subgraph "주요 구성 요소 및 원칙"
        style KeyAbstractions fill:#f0f8ff,stroke:#a4c1d7
        Container -- "구현" --> Resolver(Resolver);
        Container -- "활용" --> CycleDetector["@TaskLocal 순환 참조 감지"];
        CacheManager -- "구현" --> DefaultCacheManager(DefaultCacheManager);
        DefaultCacheManager -- "활용" --> DataStructures["- DoublyLinkedList (LRU/FIFO)\n- PriorityQueue (TTL)"];
    end

    classDef actor fill:#f9f,stroke:#333,stroke-width:2px;
    class Builder,Container,CacheManager,DefaultCacheManager actor;


### 2.1. `WeaverContainer` (Actor)
- **역할**: 의존성을 저장, 관리, 해결하는 핵심 DI 컨테이너입니다.
- **구현**: `actor`로 구현되어 여러 스레드에서 동시에 `resolve`를 호출해도 내부 상태(`containerCache`, `ongoingCreations` 등)를 안전하게 관리합니다.
- **주요 로직**:
  - **순환 참조 감지**: `@TaskLocal` 변수인 `resolutionStack`을 사용하여 현재 비동기 작업(Task) 내의 의존성 해결 경로를 추적합니다. 동일한 키가 스택에 다시 등장하면 순환 참조로 판단하고 `WeaverError.circularDependency` 오류를 발생시킵니다.
  - **스코프 처리**: `resolve` 요청 시 등록된 `Scope`에 따라 `.container`는 내부 캐시를, `.cached`는 `CacheManaging` 프로토콜을 준수하는 캐시 관리자에게 처리를 위임합니다.
  - **리소스 관리**: `shutdown()` 메서드를 통해 `Disposable` 인스턴스 정리, 캐시 비우기 등 컨테이너의 생명주기 종료를 안전하게 처리합니다.

### 2.2. `WeaverBuilder` (Actor)
- **역할**: `WeaverContainer`의 생성 및 설정을 담당하는 빌더입니다.
- **구현**: 플루언트 인터페이스(`register(...)`, `withModules(...)` 등)를 제공하며, `actor`로 구현되어 여러 설정이 비동기적으로 호출되어도 안전합니다.
- **특징**:
  - **관심사 분리**: 컨테이너의 생성 로직과 사용 로직을 분리합니다.
  - **유연한 확장**: `enableAdvancedCaching()`, `enableMetricsCollection()`과 같은 메서드를 통해 고급 기능을 선택적으로 활성화할 수 있습니다. 내부적으로는 팩토리 클로저(`cacheManagerFactory`, `metricsCollectorFactory`)를 교체하는 방식으로 동작합니다.

### 2.3. `@Inject` (Property Wrapper)
- **역할**: 사용자가 의존성을 선언하고 주입받는 주된 창구입니다.
- **구현**: 내부에 `ValueStorage`라는 private `actor`를 두어, 각 프로퍼티 래퍼 인스턴스별로 의존성 해결 결과를 한 번만 수행하고 캐시합니다. 이로써 동일 의존성에 대한 반복적인 `resolve` 호출을 방지합니다.
- **API**:
  - **안전 모드 (Safe Mode)**: `await service()` - 의존성 해결 실패 시 `DependencyKey.defaultValue`를 반환하고 로그를 남깁니다.
  - **엄격 모드 (Strict Mode)**: `try await $service.resolved` - 의존성 해결 실패 시 `WeaverError`를 던져 명시적인 에러 처리를 강제합니다.

### 2.4. `DependencyKey` (Protocol)
- **역할**: 각 의존성을 고유하게 식별하는 키 역할을 합니다.
- **특징**:
  - `associatedtype Value`: 해결될 의존성의 타입을 정의합니다.
  - `static var defaultValue`: 의존성 해결 실패 시 반환될 기본값을 정의하여 안정성을 높입니다.
  - 타입 자체를 키로 사용하므로 문자열 기반 키보다 타입-세이프합니다.

### 2.5. `Scope` (Enum)
- **역할**: 의존성 인스턴스의 생명주기를 정의합니다.
- **종류**:
  - `.container`: 컨테이너 내에서 유일한 인스턴스를 보장합니다 (싱글턴). 컨테이너가 살아있는 동안 동일한 인스턴스가 반환됩니다.
  - `.cached`: `CachePolicy`에 따라 인스턴스가 캐시됩니다. TTL이 만료되거나, 캐시 크기 제한을 초과하거나, 시스템 메모리 압박이 발생하면 캐시에서 제거될 수 있습니다.

---

## 3. 파일별 상세 분석

### `/Sources/Weaver/Interfaces.swift`
- **목적**: 라이브러리의 모든 핵심 프로토콜을 정의하여 API 계약을 명확히 합니다.
- **주요 프로토콜**:
  - `DependencyKey`, `Resolver`, `Module`: 라이브러리의 기본 구조를 형성합니다.
  - `Disposable`: 컨테이너 종료 시 정리 작업이 필요한 객체를 위한 프로토콜입니다.
  - `CacheManaging`, `MetricsCollecting`: 캐싱과 메트릭 수집 로직을 추상화하여 `WeaverContainer`가 구체적인 구현에 의존하지 않도록 합니다. 모든 프로토콜과 연관 타입은 `Sendable`을 준수하여 동시성 안전을 보장합니다.

### `/Sources/Weaver/Weaver.swift`
- **목적**: `@Inject` 프로퍼티 래퍼와 핵심 `WeaverContainer` 액터를 구현합니다.
- **핵심 구현**:
  - **`Weaver` (enum)**: `@MainActor`로 격리된 전역 네임스페이스입니다. `TaskLocal`을 사용하여 현재 활성화된 컨테이너(`Weaver.current`)를 안전하게 전파합니다.
  - **`WeaverContainer` (actor)**: 의존성 해결의 모든 과정을 총괄합니다. 부모 컨테이너 조회, 순환 참조 검사, 스코프에 따른 위임, 메트릭 기록 등의 책임이 있습니다.

### `/Sources/Weaver/WeaverBuilder.swift`
- **목적**: `WeaverContainer`를 생성하는 빌더를 구현합니다.
- **설계 패턴**: 빌더 패턴(Builder Pattern)과 플루언트 인터페이스(Fluent Interface)를 적용하여 사용자가 컨테이너를 쉽게 구성할 수 있도록 합니다.

### `/Sources/Weaver/Weaver+Addons.swift`
- **목적**: 고급 캐싱, 메트릭, 의존성 그래프 등 부가 기능을 모듈화하여 제공합니다.
- **`DefaultCacheManager` (actor)**:
  - **자료구조**: LRU/FIFO 정책의 O(1) 시간 복잡도를 위해 `DoublyLinkedList`를, TTL 기반 만료 처리를 위해 `PriorityQueue`(최소 힙)를 직접 구현하여 사용합니다. 이는 외부 의존성을 줄이고 성능을 최적화합니다.
  - **`MemoryMonitor`**: `DispatchSource`를 사용하여 시스템 메모리 압박 이벤트를 감지하고, 캐시의 일부를 선제적으로 제거하여 앱의 안정성을 높입니다.
- **`DependencyGraph`**: 등록 정보를 순회하여 Graphviz의 DOT 언어 형식 문자열을 생성합니다. 이를 통해 의존성 관계를 시각적으로 분석할 수 있습니다.

---

## 4. 동시성 모델 (Concurrency Model)

Weaver는 Swift Concurrency를 핵심 설계 원칙으로 삼습니다.

- **Actor 격리**: 상태를 가지는 모든 주요 객체(`WeaverContainer`, `WeaverBuilder`, `DefaultCacheManager` 등)는 `actor`로 구현되어 내부 상태에 대한 접근을 직렬화하고 데이터 경쟁을 원천적으로 방지합니다.
- **`Sendable` 준수**: 모든 공개 API의 데이터 모델과 프로토콜은 `Sendable`을 준수하여 `actor` 경계를 넘어 안전하게 전달될 수 있도록 보장합니다.
- **`@TaskLocal` 활용**:
  - **범위 관리 (Scope Management)**: `Weaver.withScope`는 `@TaskLocal` 변수를 사용하여 특정 비동기 작업 흐름에 컨테이너를 바인딩합니다. 이는 명시적인 컨테이너 전달 없이 `@Inject`가 현재 컨텍스트에 맞는 컨테이너를 찾을 수 있게 해줍니다.
  - **순환 참조 감지**: `resolve`가 호출될 때마다 의존성 키를 `@TaskLocal` 배열에 추가합니다. 이를 통해 중첩된 `resolve` 호출 과정에서 동일한 키가 다시 나타나는지 확인하여 순환 참조를 효과적으로 감지합니다.

---

## 5. 기본 사용 예제

```swift
import Weaver

// 1. 의존성 키 정의
struct ServiceKey: DependencyKey {
    static var defaultValue: MyServiceProtocol { MyServiceMock() }
}

protocol MyServiceProtocol: Sendable {
    func doSomething()
}

final class MyServiceImpl: MyServiceProtocol, Sendable {
    func doSomething() { print("Hello from MyServiceImpl!") }
}

// 2. 의존성 소비자 정의
actor ServiceConsumer {
    @Inject(ServiceKey.self)
    var myService

    func run() async {
        await myService.doSomething()
    }
}

// 3. 컨테이너 빌드 및 스코프 지정
@main
struct MyApp {
    static func main() async {
        let container = await WeaverContainer.builder()
            .register(ServiceKey.self) { _ in MyServiceImpl() }
            .build()

        let consumer = ServiceConsumer()

        // 4. 특정 컨테이너 스코프 내에서 코드 실행
        try! await Weaver.withScope(container) {
            await consumer.run() // 출력: "Hello from MyServiceImpl!"
        }
    }
}
```
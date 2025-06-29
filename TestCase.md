## 🕸️ Weaver DI 컨테이너 핵심 기능 테스트 플랜

이 테스트 계획은 **Weaver** 라이브러리의 정확성, 안정성, 성능을 보장하기 위해 핵심 기능 전반을 검증합니다. 특히 리팩토링된 `@Inject`의 다양한 동작 모드와 Swift Concurrency 환경에서의 안정성을 집중적으로 테스트합니다.

**테스트 범위:**

  * **포함:** 의존성 등록/해결, 스코프별 생명주기, 계층 구조, `@Inject` 동작, 오류 처리, 동시성 안정성.
  * **제외:** `WeaverLogger`의 출력 내용, `ResolutionMetrics`의 정확한 값, `DependencyGraph`의 출력 내용. (해당 기능의 실행 자체는 테스트하되, 결과물의 상세 내용은 검증하지 않음)

-----

### **1. 등록 및 해결 (Registration & Resolution)**

가장 기본적인 DI 기능과 새로워진 `@Inject`의 핵심 동작을 검증합니다.

| ID | 테스트 항목 | 실행 절차 | 예상 결과 |
| :--- | :--- | :--- | :--- |
| **T1.1** | **기본 등록 및 해결** | 1. `WeaverBuilder`로 특정 의존성을 등록하고 컨테이너를 빌드.\<br\>2. 등록한 `Key`로 `container.resolve()`를 호출. | 오류 없이 해결에 성공하며, 팩토리에서 생성한 인스턴스가 정상 반환된다. |
| **T1.2** | **미등록 의존성 해결** | 1. 비어있는 컨테이너를 빌드.\<br\>2. 임의의 `Key`로 `container.resolve()`를 호출. | `WeaverError.resolutionFailed(.keyNotFound)` 오류가 발생한다. |
| **T1.3** | **의존성 오버라이드** | 1. 동일한 `Key`로 서로 다른 두 개의 의존성을 순차적으로 등록.\<br\>2. 해당 `Key`로 `resolve()` 호출. | **나중에 등록된** 의존성이 정상적으로 반환된다. (오버라이드 동작 확인) |
| **T1.4** | **`@Inject` 엄격 모드 (`.resolved`)** | 1. 의존성을 등록한 컨테이너 스코프 내에서 `@Inject` 객체 생성.\<br\>2. `try await service.resolved`를 통해 의존성에 접근. | 오류 없이 의존성이 해결되고, 정상적인 인스턴스가 반환된다. |
| **T1.5** | **`@Inject` 안전 모드 (`.value`)** | 1. 의존성을 등록한 컨테이너 스코프 내에서 `@Inject` 객체 생성.\<br\>2. `await service.value`를 통해 의존성에 접근. | 오류 없이 의존성이 해결되고, 정상적인 인스턴스가 반환된다. |
| **T1.6** | **`@Inject` 안전 모드 실패 시** | 1. **미등록** 의존성에 대해 `@Inject` 객체 생성.\<br\>2. `await service.value`를 통해 접근. | 오류가 발생하지 않으며, `DependencyKey.defaultValue`에 정의된 기본값이 반환된다. |
| **T1.7** | **`@Inject` 엄격 모드 실패 시** | 1. **미등록** 의존성에 대해 `@Inject(strategy: .throwError)` 객체 생성.\<br\>2. `try await service.resolved`를 통해 접근. | `WeaverError.resolutionFailed(.keyNotFound)` 오류가 발생한다. |
| **T1.8** | **`@Inject` 스코프 외부 접근** | `Weaver.withScope` 블록 외부에서 `@Inject` 프로퍼티(`.value` 또는 `.resolved`)에 접근. | `WeaverError.containerNotFound` 오류가 발생한다. (단, `strategy: .returnDefault`인 경우 `.value`는 기본값을 반환) |
| **T1.9** | **`@Inject` 내부 캐시 동작** | 1. `@Inject`로 선언된 프로퍼티에 대해 `.value` 또는 `.resolved`를 **반복해서** 접근.\<br\>2. 팩토리 내부에 카운터를 두어 호출 횟수 측정. | 팩토리는 **단 한 번만** 호출된다. (두 번째 접근부터는 `@Inject` 내부 캐시 값 사용) |

-----

### **2. 스코프별 생명주기 (Scope Lifecycle)**

각 스코프가 의도된 대로 인스턴스의 생명주기를 관리하는지 검증합니다.

| ID | 테스트 항목 | 실행 절차 | 예상 결과 |
| :--- | :--- | :--- | :--- |
| **T2.1** | **`.transient` 스코프** | 1. 의존성을 `.transient`로 등록.\<br\>2. 동일 `Key`를 두 번 `resolve`. | 두 인스턴스의 객체 식별자(ObjectIdentifier)가 **서로 다르다.** |
| **T2.2** | **`.container` 스코프** | 1. 의존성을 `.container`로 등록.\<br\>2. 동일 `Key`를 두 번 `resolve`. | 두 인스턴스의 객체 식별자가 **서로 같다.** |
| **T2.3** | **`.cached` 스코프 (Hit)** | 1. 의존성을 `.cached`로 등록 (TTL 5초).\<br\>2. TTL 내에 동일 `Key`를 두 번 `resolve`. | 두 인스턴스의 객체 식별자가 **서로 같다.** |
| **T2.4** | **`.cached` 스코프 (Miss)** | 1. 의존성을 `.cached`로 등록 (TTL 0.1초).\<br\>2. 첫 번째 `resolve` 후 0.2초 대기.\<br\>3. 다시 `resolve`. | 두 인스턴스의 객체 식별자가 **서로 다르다.** |
| **T2.5** | **`Disposable` 객체 자동 해제** | 1. `Disposable` 객체를 `.container`로 등록하고 `resolve`.\<br\>2. 컨테이너의 `shutdown()` 호출.\<br\>3. `dispose()` 메서드 호출 여부를 `XCTestExpectation`으로 확인. | `dispose()` 메서드가 **정확히 한 번** 호출된다. |

-----

### **3. 계층적 컨테이너 (Hierarchical Containers)**

부모-자식 컨테이너 관계의 의존성 탐색 및 오버라이드를 검증합니다.

| ID | 테스트 항목 | 실행 절차 | 예상 결과 |
| :--- | :--- | :--- | :--- |
| **T3.1** | **부모 의존성 참조** | 1. 부모 컨테이너에만 의존성 A를 등록.\<br\>2. 부모를 참조하는 자식 컨테이너 생성.\<br\>3. 자식 컨테이너에서 A를 `resolve`. | 자식 컨테이너가 부모의 의존성 A를 성공적으로 해결한다. |
| **T3.2** | **자식 의존성 오버라이드** | 1. 부모와 자식에 동일 `Key`로 각각 다른 인스턴스(A, B)를 등록.\<br\>2. 자식 컨테이너에서 해당 `Key`를 `resolve`. | 자식에 등록된 인스턴스 B가 반환된다. |

-----

### **4. 오류 처리 및 엣지 케이스 (Error Handling & Edge Cases)**

예상 가능한 오류 및 경계 조건에서 시스템이 안정적으로 동작하는지 검증합니다.

| ID | 테스트 항목 | 실행 절차 | 예상 결과 |
| :--- | :--- | :--- | :--- |
| **T4.1** | **순환 참조** | 1. 서비스 A는 B를, 서비스 B는 다시 A를 의존하도록 등록.\<br\>2. A 또는 B를 `resolve`. | `WeaverError.resolutionFailed(.circularDependency)` 오류가 발생한다. |
| **T4.2** | **팩토리 실패** | 1. 팩토리 클로저 내부에서 의도적으로 에러를 `throw` 하도록 등록.\<br\>2. 해당 `Key`를 `resolve`. | `WeaverError.resolutionFailed(.factoryFailed)` 오류가 발생한다. |
| **T4.3** | **타입 불일치** | 1. `DependencyKey.Value`가 `ServiceA`인데, 팩토리에서 `ServiceB` 인스턴스를 반환하도록 등록.\<br\>2. 해당 `Key`를 `resolve`. | `WeaverError.resolutionFailed(.typeMismatch)` 오류가 발생한다. |
| **T4.4** | **종료된 컨테이너 접근** | 1. 컨테이너의 `shutdown()`을 호출.\<br\>2. `shutdown` 이후 `resolve`를 시도. | `WeaverError.shutdownInProgress` 오류가 발생한다. |

-----

### **5. 동시성 및 안정성 (Concurrency & Safety)**

`TaskGroup` 등을 사용하여 여러 비동기 작업이 동시에 컨테이너에 접근할 때의 안정성을 검증합니다.

| ID | 테스트 항목 | 실행 절차 | 예상 결과 |
| :--- | :--- | :--- | :--- |
| **T5.1** | **동일 의존성 동시 해결** | 1. `.container` 스코프 의존성을 등록.\<br\>2. `TaskGroup`을 사용하여 10개의 동시 태스크에서 동일 `Key`를 `resolve`.\<br\>3. 반환된 모든 인스턴스의 객체 식별자를 비교. | 1. 모든 태스크가 **동일한 객체 식별자**를 가진 인스턴스를 받는다.\<br\>2. 의존성 팩토리는 **단 한 번만** 호출된다. |
| **T5.2** | **다른 의존성 동시 해결** | 1. 10개의 서로 다른 의존성을 등록.\<br\>2. `TaskGroup`을 사용하여 각 태스크가 서로 다른 `Key`를 `resolve`. | 모든 의존성이 데드락이나 크래시 없이 성공적으로 해결된다. |

좋아, “사용자는 쉽고, 내부는 복잡해도 된다”를 목표로 디프리케이트/마이그레이션 없이 바로 갈아끼우는 리팩토링 계획을 딱 정리해 줄게.
핵심은 공개 API를 극도로 단순화하고, 내부에서 복잡도를 흡수·은닉하는 거야.

⸻

목표(요약)
    •    Public API = 4가지면 끝
    1.    Module { register(Key.self, scope: .startup) { ... } }
    2.    Weaver.bootstrap(modules: [...], progress: { ... })
    3.    @Use(default: ...) var foo (즉시 렌더)
    4.    UseStream.updates(Foo.self) (업그레이드 반영)
    •    절대 원칙
    •    앱 시작은 동기, DI는 비동기 업그레이드.
    •    진행률 콜백은 **동기(@Sendable (Double) -> Void)**로 통일.
    •    전역 가변 상태 레이스 제거(메인 액터/액터 격리).
    •    에러는 명시적 throw(런타임 fatalError/as! 금지).

⸻

공개 API 설계(최종 형태)

// 1) 키·기본값
struct Config: Sendable { let baseURL: URL }
enum ConfigKey: DependencyKey {
  static let liveValue   = Config(baseURL: URL(string:"https://api.example.com")!)
  static let previewValue = Config(baseURL: URL(string:"https://staging.example.com")!)
  static let testValue    = Config(baseURL: URL(string:"http://localhost")!)
}

// 2) 모듈
let CoreModule = Module {
  register(Config.self, scope: .startup) {
    // 네트워크/디스크 I/O로 실제 구성 생성 (비동기 내부는 컨테이너가 처리)
  }
}

// 3) 부트스트랩
Weaver.bootstrap(modules: [CoreModule]) { progress in
  // 0.0 ~ 1.0 진행률
}

// 4) 주입 & 업그레이드
@Use(default: ConfigKey.liveValue) var config

@MainActor
final class VM: ObservableObject {
  @Published private(set) var cfg = ConfigKey.liveValue
  private var task: Task<Void, Never>?
  func bind() {
    task = Task {
      for await v in await UseStream.updates(Config.self) { self.cfg = v }
    }
  }
  deinit { task?.cancel() }
}

사용자 입장: “키 정의 → 모듈 등록 → 부트스트랩 → @Use/업데이트 스트림” 4스텝이면 끝.

⸻

리팩토링 단계별 계획

P1 — 정책 일관화 & 안전성 (바로 적용)

1) 진행률 콜백 동기 통일
    •    변경 대상
    •    WeaverBuilder.build(onAppServiceProgress: @Sendable (Double) -> Void)
    •    WeaverContainer.initializeAppServiceDependencies(onProgress: @Sendable (Double) -> Void)
    •    내부 await onProgress(...) 호출 제거(동기 호출).
    •    Acceptance
    •    컴파일 경고/에러 0, 앱 부팅/초기화 완료 시 progress가 0→1.0 단조 증가로 기록.

2) 전역 컨텍스트 레이스 제거 (외형 유지)
    •    현재: Interfaces.swift의 DependencyEnv.current 가 nonisolated(unsafe)
    •    변경: @MainActor 격리 변수로 교체. DependencyValues.currentContext는 동일 노출(내부 위임).
    •    Acceptance
    •    Thread Sanitizer 켠 상태에서 데이터 레이스 0.

3) 런타임 크래시원 제거
    •    WeaverContainer.swift의 as! (AnyObject & Sendable) → guard let ... as? + 명시적 에러 throw.
    •    TypeBasedDependencyKey의 fatalError 제거 →
@available(*, unavailable, message: "...")로 사용 자체 컴파일 차단.
    •    Acceptance
    •    잘못된 사용 시 컴파일 에러, 런타임 크래시 없음.

⸻

P2 — 사용성 극대화(내부 복잡도 은닉)

4) 대형 컨테이너 분해(내부 구조만 변경, API 불변)
    •    WeaverContainer.swift를 역할별 확장 파일로 분리:
    •    WeaverContainer+Resolution.swift (해결/캐시/약참조)
    •    WeaverContainer+AppServices.swift (앱 서비스 초기화/우선순위)
    •    WeaverContainer+Lifecycle.swift (앱 라이프사이클)
    •    WeaverContainer+Metrics.swift (메트릭/로그)
    •    Acceptance
    •    퍼블릭 심볼 변화 없음(public API 동일), 테스트 전부 통과.

5) 시간 계측을 ContinuousClock/Duration으로 통일
    •    대상: StartupCoordinator, WeaverContainer, WeakBox
    •    이유: 단조 증가 시계로 정확·안전, 플랫폼 일관성.
    •    Acceptance
    •    로그/메트릭 값이 마이크로단위까지 정확하고, 슬립/시간대 변경 영향 無.

6) SwiftUI 글루 최소 세트 제공 (선택적)
    •    WeaverSwiftUI 모듈(내부 복잡도 은닉):
    •    DependencyObserver<T>: ObservableObject로 UseStream.updates(T.self) 구독을 캡슐화.
    •    View.weaverProgress(_:) modifier: 진행률 바인딩 헬퍼(선택).
    •    Acceptance
    •    샘플 앱에서 @StateObject var cfg = DependencyObserver<Config>() 한 줄로 연동.

7) 프리셋 모듈 & 키 가이드
    •    SystemModule(기본 로거/메트릭/디폴트 인코더 등) 제공.
    •    각 Key에 동기/비동기/스코프 표기 템플릿 도입:
    •    예) Config → sync default, .startup async upgrade, scope: .startup
    •    Acceptance
    •    새로 합류한 개발자도 10분 내 “키→모듈→부트스트랩→주입” 경로 이해.

⸻

파일별 구체 작업 목록
    •    Interfaces.swift
    •    DependencyEnv.current → @MainActor public static var current
    •    TypeBasedDependencyKey: live/preview/test/default → @available(*, unavailable, ...)
    •    주석에 “Public API 표면”만 남기고 내부 구현 상세는 숨김.
    •    DependencyValues.swift
    •    AnySendableBox는 그대로(필요 시 주석 보강: “컨테이너 내부 사용, 교차 액터 접근 금지”)
    •    Dependency.swift
    •    스코프→캐시 정책 매핑을 함수로 고정하고 단위 테스트 추가.
    •    WeaverError.swift
    •    ResolutionError.typeMismatch(expected:actual:key:) 등 기존 에러 사용 일관화.
    •    WeakBox.swift
    •    CFAbsoluteTimeGetCurrent() → ContinuousClock 기반 age: Duration.
    •    Use.swift
    •    현행 유지. UseStream의 백프레셔/취소 동작을 문서에 명시.
    •    Weaver.swift
    •    공개 진입점 최소화:
    •    Weaver.bootstrap(modules: [Module], progress: @Sendable (Double) -> Void = { _ in })
    •    Weaver.shared.resolve(_:)/updates(_:)만 노출(필요 최소).
    •    내부 상태는 액터 보호.
    •    WeaverBuilder.swift
    •    build(onAppServiceProgress: @Sendable (Double) -> Void)로 고정.
    •    문서 주석: “동기 콜백, 비동기 작업은 내부에서 안전 처리”
    •    WeaverContainer.swift (+Extensions)
    •    파일 분리(내부 전용), as! 제거, 시간 계측 교체.
    •    initializeAppServiceDependencies(onProgress: ...)에서 절대값 진행률 보장.
    •    StartupCoordinator.swift
    •    모든 진행률 호출 경로 onProgress(...) 래퍼로 통일.
    •    시간 계측 교체.

⸻

테스트 계획(짧고 강력하게)
    1.    Public API 스냅샷 테스트
    •    Weaver.bootstrap/Module.register/@Use/UseStream 공개 시그니처 불변 확인.
    2.    진행률 단조성 테스트
    •    0.0 → 1.0 이며 내림/건너뜀 없음. 마지막 값은 반드시 1.0.
    3.    스코프/캐시 테스트
    •    .permanent/.smart/.weak/.none 각각에 대한 인스턴스 재사용/해제 시맨틱 검증.
    4.    동시성 안전 테스트
    •    TSan 켜고 부트스트랩/E2E 수행 → 레이스 0.
    5.    실패 내성 테스트
    •    .startup 일부 실패 → 폴백 유지 & 크래시 없음 & 에러 로그/메트릭 기록.

⸻

문서 & 샘플(사용자 친화)
    •    Quickstart(1페이지): 위 “공개 API 4단계”만.
    •    Key Guide(표 1장): 동기/비동기/스코프 예시.
    •    샘플 앱: App.swift 15줄, VM 20줄, Module 10줄 수준.
    •    FAQ: “왜 진행률 콜백이 동기인가?”, “언제 .startup에 넣나?”

⸻

완료 기준(Definition of Done)
    •    퍼블릭 API 표면: Module / Weaver.bootstrap / @Use / UseStream 이외 추가 없이 사용 가능.
    •    DI 실패 시 크래시 0. (모두 명시적 에러 & 폴백)
    •    멀티스레드 환경에서 레이스 0.
    •    SwiftUI 샘플에서 런치 블로킹 0(첫 화면 즉시 렌더 + 업그레이드 반영).
    •    문서 3종(Quickstart/Key Guide/FAQ) 포함.

⸻

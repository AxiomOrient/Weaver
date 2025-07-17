# Weaver 아키텍처 분석 및 개선 방안

## 1. 프로젝트 개요

Weaver는 Swift 6의 엄격한 동시성 모델을 완벽하게 지원하는 현대적인 의존성 주입(DI) 컨테이너 라이브러리입니다. 주요 특징으로는 actor 기반 설계, 타입 안전성, 모듈화된 구조, 그리고 다양한 스코프 지원 등이 있습니다.

### 핵심 기능
- **동시성 중심 설계**: actor 기반으로 구현되어 Swift 6의 엄격한 동시성 모델에서 안전하게 동작
- **타입 안전성**: 컴파일 타임에 의존성 문제를 해결
- **모듈화된 구조**: 기능별로 의존성을 그룹화하여 코드 가독성과 유지보수성 향상
- **다양한 스코프**: `.container`, `.cached`, `.transient`, `.weak` 등 다양한 생명주기 지원
- **계층적 컨테이너**: 부모-자식 관계를 통한 유연한 의존성 오버라이드
- **SwiftUI 통합**: SwiftUI 환경에서 쉽게 사용할 수 있는 인터페이스 제공

## 2. 아키텍처 분석

### 2.1 핵심 컴포넌트

#### 프로토콜 계층
- **DependencyKey**: 의존성을 식별하는 키 정의
- **Resolver**: 의존성 해결 기능 정의
- **Module**: 관련 의존성 등록 로직 그룹화
- **Disposable**: 리소스 해제가 필요한 인스턴스 관리
- **WeaverKernel**: 컨테이너 생명주기 관리

#### 구현 클래스
- **WeaverContainer**: 의존성 관리 및 해결을 담당하는 핵심 actor
- **WeaverBuilder**: 컨테이너 구성을 위한 fluent API 제공
- **DefaultWeaverKernel**: 컨테이너 생명주기 관리 구현
- **@Inject**: 의존성 주입을 위한 프로퍼티 래퍼

#### 지원 컴포넌트
- **WeakReferenceTracker**: 약한 참조 관리
- **DisposableManager**: 리소스 해제 관리
- **CacheManaging**: 캐시 전략 구현
- **MetricsCollecting**: 성능 측정 기능

### 2.2 설계 패턴

1. **빌더 패턴**: `WeaverBuilder`를 통한 컨테이너 구성
2. **프로토콜 지향 설계**: 핵심 기능을 프로토콜로 정의하여 확장성 확보
3. **액터 모델**: 동시성 안전성을 위한 actor 기반 설계
4. **의존성 주입**: 객체 생성과 사용의 분리
5. **전략 패턴**: 다양한 스코프와 캐시 전략 구현
6. **어댑터 패턴**: SwiftUI 환경과의 통합을 위한 `WeaverSwiftUIAdapter`

### 2.3 동시성 모델

- **Actor 기반 설계**: 핵심 컴포넌트가 actor로 구현되어 데이터 경쟁 방지
- **TaskLocal 활용**: 현재 실행 컨텍스트에 맞는 DI 컨테이너 관리
- **AsyncStream**: 컨테이너 상태 변화를 비동기적으로 전파
- **Sendable 준수**: 모든 공유 타입이 `Sendable` 프로토콜을 준수하여 동시성 안전성 보장

## 3. 강점 및 약점 분석

### 3.1 강점

1. **동시성 안전성**: actor 기반 설계로 데이터 경쟁 없이 안전한 의존성 관리
2. **타입 안전성**: 컴파일 타임에 의존성 문제 발견
3. **유연한 스코프**: 다양한 생명주기 옵션 제공
4. **모듈화**: 기능별 의존성 그룹화로 코드 구조화
5. **SwiftUI 통합**: SwiftUI 환경에서 쉽게 사용 가능
6. **성능 측정**: 내장된 메트릭 수집 기능
7. **순환 참조 감지**: 의존성 해결 시 순환 참조 자동 감지

### 3.2 약점

1. **문서화 부족**: 일부 고급 기능에 대한 문서화 미흡
2. **테스트 커버리지**: 일부 엣지 케이스에 대한 테스트 부족
3. **에러 처리 일관성**: 일부 에러 메시지가 한글로만 제공됨
4. **성능 최적화**: 대규모 의존성 그래프에서의 성능 최적화 필요
5. **디버깅 도구**: 의존성 그래프 시각화 도구의 기능 제한
6. **비동기 초기화 복잡성**: 비동기 초기화 과정이 복잡하여 사용자 경험 저하 가능성

## 4. 개선 방안

### 4.1 코드 품질 개선

1. **다국어 지원 강화**
   - 에러 메시지를 다국어로 제공하는 국제화 시스템 도입
   - 현재 한글로만 제공되는 에러 메시지를 영어 버전도 함께 제공

```swift
public enum WeaverError: Error, LocalizedError, Sendable {
    case containerNotFound
    case resolutionFailed(ResolutionError)
    case shutdownInProgress
    
    public var errorDescription: String? {
        switch self {
        case .containerNotFound:
            return NSLocalizedString(
                "활성화된 WeaverContainer를 찾을 수 없습니다.",
                comment: "No active WeaverContainer found"
            )
        case .resolutionFailed(let error):
            return error.localizedDescription
        case .shutdownInProgress:
            return NSLocalizedString(
                "컨테이너가 종료 처리 중입니다.",
                comment: "Container is shutting down"
            )
        }
    }
}
```

2. **테스트 커버리지 향상**
   - 엣지 케이스에 대한 테스트 추가
   - 성능 테스트 및 벤치마크 추가
   - 동시성 관련 테스트 강화

3. **코드 중복 제거**
   - `WeaverContainer.swift`와 `Weaver.swift`에 중복된 코드 통합
   - 공통 로직을 별도 유틸리티 클래스로 추출

### 4.2 기능 개선

1. **의존성 그래프 시각화 강화**
   - 현재 DOT 형식만 지원하는 그래프 시각화를 JSON, SVG 등 다양한 형식으로 확장
   - 의존성 간의 관계를 더 명확하게 표현하는 메타데이터 추가

```swift
public struct DependencyGraph: Sendable {
    // 기존 코드...
    
    /// JSON 형식의 그래프 정의 문자열을 생성합니다.
    public func generateJsonGraph() -> String {
        var nodes: [[String: Any]] = []
        var edges: [[String: Any]] = []
        
        // 노드 정보 구성
        registrations.forEach { key, registration in
            let node: [String: Any] = [
                "id": key.description,
                "type": String(describing: registration.scope),
                "metadata": [
                    "scope": registration.scope.rawValue,
                    "keyName": registration.keyName
                ]
            ]
            nodes.append(node)
            
            // 엣지 정보 구성
            registration.dependencies.forEach { dependency in
                let edge: [String: Any] = [
                    "source": key.description,
                    "target": dependency
                ]
                edges.append(edge)
            }
        }
        
        let graph: [String: Any] = [
            "nodes": nodes,
            "edges": edges
        ]
        
        return try! JSONSerialization.data(withJSONObject: graph, options: .prettyPrinted).toString()
    }
    
    /// SVG 형식의 그래프 시각화를 생성합니다.
    public func generateSvgGraph() -> String {
        // SVG 생성 로직 구현
        // ...
    }
}
```

2. **성능 최적화**
   - 대규모 의존성 그래프에서의 해결 성능 개선
   - 메모리 사용량 최적화
   - 지연 로딩(Lazy Loading) 전략 강화

```swift
// 의존성 해결 성능 최적화를 위한 캐시 전략 개선
public actor OptimizedCacheManager: CacheManaging {
    private var cache: [AnyDependencyKey: CacheEntry] = [:]
    private let policy: CachePolicy
    private var hits: Int = 0
    private var misses: Int = 0
    
    // LRU 캐시 구현을 위한 접근 시간 추적
    private struct CacheEntry: Sendable {
        let value: any Sendable
        let expiresAt: CFAbsoluteTime
        var lastAccessed: CFAbsoluteTime
    }
    
    // 캐시 정리를 위한 백그라운드 작업
    private var cleanupTask: Task<Void, Never>?
    
    init(policy: CachePolicy, logger: WeaverLogger?) {
        self.policy = policy
        
        // 주기적인 캐시 정리 작업 시작
        self.cleanupTask = Task {
            while !Task.isCancelled {
                await cleanExpiredEntries()
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30초마다 실행
            }
        }
    }
    
    // 캐시 엔트리 정리 로직
    private func cleanExpiredEntries() async {
        let now = CFAbsoluteTimeGetCurrent()
        
        // 만료된 항목 제거
        cache = cache.filter { _, entry in
            entry.expiresAt > now
        }
        
        // 캐시 크기가 최대 크기를 초과하면 LRU 전략으로 정리
        if cache.count > policy.maxSize {
            let sortedEntries = cache.sorted { $0.value.lastAccessed < $1.value.lastAccessed }
            let entriesToRemove = sortedEntries.prefix(cache.count - policy.maxSize)
            for (key, _) in entriesToRemove {
                cache.removeValue(forKey: key)
            }
        }
    }
    
    // 나머지 구현...
}
```

3. **디버깅 경험 개선**
   - 의존성 해결 과정을 추적하는 디버깅 도구 추가
   - 로깅 시스템 강화
   - Xcode 통합 개선

```swift
public actor EnhancedLogger: WeaverLogger {
    private let logger: Logger
    private let logLevel: OSLogType
    private let isDebugMode: Bool
    
    public init(subsystem: String = "com.weaver.di", category: String = "Weaver", logLevel: OSLogType = .default, isDebugMode: Bool = false) {
        self.logger = Logger(subsystem: subsystem, category: category)
        self.logLevel = logLevel
        self.isDebugMode = isDebugMode
    }
    
    public func log(message: String, level: OSLogType) {
        // 설정된 로그 레벨보다 낮은 레벨의 로그는 무시
        guard level.rawValue >= logLevel.rawValue else { return }
        
        logger.log(level: level, "\(message)")
        
        // 디버그 모드에서는 콘솔에도 출력
        if isDebugMode {
            let prefix: String
            switch level {
            case .debug: prefix = "🔍 DEBUG"
            case .info: prefix = "ℹ️ INFO"
            case .error: prefix = "❌ ERROR"
            case .fault: prefix = "💥 FAULT"
            default: prefix = "📝 LOG"
            }
            print("\(prefix): \(message)")
        }
    }
    
    // 의존성 해결 과정 추적을 위한 메서드
    public func traceResolution(key: AnyDependencyKey, duration: TimeInterval, result: Result<Any, Error>) {
        let status = switch result {
        case .success: "✅ Success"
        case .failure: "❌ Failed"
        }
        
        let durationMs = String(format: "%.2fms", duration * 1000)
        log(message: "[\(status)] Resolved \(key.description) in \(durationMs)", level: .debug)
    }
}
```

### 4.3 사용자 경험 개선

1. **문서화 강화**
   - 상세한 API 문서 제공
   - 사용 예제 및 튜토리얼 추가
   - 모범 사례 가이드 작성

2. **오류 메시지 개선**
   - 더 명확하고 실행 가능한 오류 메시지 제공
   - 문제 해결 방법 제안

```swift
public enum ResolutionError: Error, LocalizedError, Sendable {
    case circularDependency(path: String)
    case factoryFailed(keyName: String, underlying: any Error & Sendable)
    case typeMismatch(expected: String, actual: String, keyName: String)
    case keyNotFound(keyName: String)
    
    public var errorDescription: String? {
        switch self {
        case .circularDependency(let path):
            return """
            순환 참조가 감지되었습니다: \(path)
            해결 방법: 의존성 그래프를 재구성하거나, 프로토콜을 사용하여 의존성 방향을 변경하세요.
            """
        case .factoryFailed(let keyName, let underlying):
            return """
            '\(keyName)' 의존성 생성(factory)에 실패했습니다: \(underlying.localizedDescription)
            해결 방법: 팩토리 클로저 내부의 오류를 확인하고 필요한 리소스가 올바르게 초기화되었는지 확인하세요.
            """
        case .typeMismatch(let expected, let actual, let keyName):
            return """
            '\(keyName)' 의존성의 타입이 일치하지 않습니다.
            예상: \(expected), 실제: \(actual)
            해결 방법: 팩토리가 올바른 타입의 인스턴스를 반환하는지 확인하세요.
            """
        case .keyNotFound(let keyName):
            return """
            '\(keyName)' 키에 대한 등록 정보를 찾을 수 없습니다.
            해결 방법:
            1. 해당 키가 컨테이너에 등록되었는지 확인하세요.
            2. 부모 컨테이너가 있는 경우, 부모 컨테이너에 등록되었는지 확인하세요.
            3. 모듈이 올바르게 구성되었는지 확인하세요.
            """
        }
    }
}
```

3. **초기화 경험 개선**
   - 비동기 초기화 과정을 단순화
   - 진행 상황 표시 개선
   - 초기화 실패 시 더 명확한 피드백 제공

```swift
public struct WeaverProgressView<Content: View>: View {
    @StateObject private var adapter: WeaverSwiftUIAdapter
    private let content: (any Resolver) -> Content
    
    public init(modules: [Module], @ViewBuilder content: @escaping (any Resolver) -> Content) {
        let kernel = DefaultWeaverKernel(modules: modules)
        _adapter = StateObject(wrappedValue: WeaverSwiftUIAdapter(kernel: kernel))
        self.content = content
    }
    
    public var body: some View {
        ZStack {
            content(adapter.resolver)
                .environment(\.weaverResolver, adapter.resolver)
            
            if adapter.isLoading {
                VStack(spacing: 16) {
                    ProgressView(value: adapter.progress)
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                    
                    Text("의존성 초기화 중... \(Int(adapter.progress * 100))%")
                        .font(.caption)
                }
                .padding()
                .background(.thinMaterial)
                .cornerRadius(12)
            } else if let error = adapter.error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    
                    Text("초기화 실패")
                        .font(.headline)
                    
                    Text(error.localizedDescription)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("다시 시도") {
                        Task {
                            await adapter.restart()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                .padding()
                .background(.thinMaterial)
                .cornerRadius(12)
                .padding()
            }
        }
        .task {
            await adapter.start()
        }
    }
}
```

## 5. 결론

Weaver는 Swift 6의 엄격한 동시성 모델을 완벽하게 지원하는 현대적인 의존성 주입 프레임워크로, actor 기반 설계와 타입 안전성을 통해 안정적인 의존성 관리를 제공합니다. 다양한 스코프 옵션과 모듈화된 구조는 유연하고 확장 가능한 아키텍처를 구축하는 데 도움이 됩니다.

제안된 개선 사항을 통해 Weaver는 더 나은 사용자 경험, 향상된 성능, 그리고 더 강력한 디버깅 도구를 제공할 수 있을 것입니다. 특히 다국어 지원 강화, 의존성 그래프 시각화 개선, 그리고 문서화 강화는 라이브러리의 접근성과 사용성을 크게 향상시킬 것입니다.

이러한 개선을 통해 Weaver는 Swift 생태계에서 더욱 강력하고 신뢰할 수 있는 의존성 주입 솔루션으로 자리매김할 수 있을 것입니다.
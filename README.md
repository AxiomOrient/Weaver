# Weaver DI 🧵

[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![iOS 15.0+](https://img.shields.io/badge/iOS-15.0+-blue.svg)](https://developer.apple.com/ios/)
[![macOS 13.0+](https://img.shields.io/badge/macOS-13.0+-blue.svg)](https://developer.apple.com/macos/)
[![watchOS 8.0+](https://img.shields.io/badge/watchOS-8.0+-blue.svg)](https://developer.apple.com/watchos/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **Swift 6 호환** | **Actor 기반 동시성** | **스코프 기반 점진적 로딩**

Weaver는 Swift 6의 동시성 모델과 통합된 타입 안전한 의존성 주입 프레임워크입니다. 안전한 설계와 스코프 기반 점진적 로딩으로 앱 시작 성능을 최적화합니다.

## 핵심 특징

- **크래시 방지**: `@Inject`의 `callAsFunction()`은 항상 안전한 값 반환
- **점진적 로딩**: 앱 시작 시 필수 서비스만 로딩, 나머지는 사용 시점에 로딩
- **Actor 기반 동시성**: Swift 6 호환으로 데이터 경쟁 방지
- **메모리 안전**: WeakBox 패턴과 자동 생명주기 관리
- **테스트 친화적**: 격리된 테스트 환경과 타입 안전한 Mock 주입
- **SwiftUI 통합**: View 생명주기와 동기화된 `@Inject` 프로퍼티 래퍼
- **5가지 스코프**: `.startup`, `.shared`, `.whenNeeded`, `.weak`, `.transient`
- **성능 모니터링**: WeaverPerformanceMonitor로 성능 분석
- **빌드 타임 검증**: DependencyGraph로 순환 참조와 누락된 의존성 감지
- **SwiftUI Preview 지원**: PreviewWeaverContainer로 타입 안전한 Mock 등록
- **우선순위 제어**: ServicePriorityProvider로 초기화 순서 제어
- **iOS 15+ 호환**

## 📦 설치

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/AxiomOrient/Weaver.git", from: "1.0.0")
]
```

### Xcode

1. **File** → **Add Package Dependencies**
2. URL 입력: `https://github.com/AxiomOrient/Weaver.git`
3. **Add Package** 클릭

## 🚀 5분만에 시작하기

### 단계별 실습 가이드

#### 1️⃣ 서비스와 키 정의 (2분)

```swift
import Weaver

// 1. 서비스 프로토콜 정의
protocol UserService: Sendable {
    func getCurrentUser() async throws -> User?
    func updateProfile(_ user: User) async throws
}

// 2. 실제 구현체
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

// 3. 의존성 키 정의 (타입 안전성의 핵심!)
struct UserServiceKey: DependencyKey {
    typealias Value = UserService
    
    // 안전한 기본값
    static var defaultValue: UserService { 
        MockUserService() // Preview나 테스트에서 사용
    }
}

// 4. Mock 구현체 (테스트/Preview용)
final class MockUserService: UserService {
    func getCurrentUser() async throws -> User? {
        return User(id: "mock", name: "Test User", email: "test@example.com")
    }
    
    func updateProfile(_ user: User) async throws {
        print("Mock: Profile updated for \(user.name)")
    }
}
```

**참고**: `DependencyKey`의 `defaultValue`는 `fatalError()` 대신 안전한 기본값을 사용하세요. SwiftUI Preview에서 크래시를 방지할 수 있습니다.

#### 2️⃣ 모듈로 의존성 그룹화 (1분)

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

// 모듈의 장점:
// - 관련 의존성들을 논리적으로 그룹화
// - 테스트 시 모듈 단위로 Mock 교체 가능
// - 기능별 팀이 독립적으로 개발 가능
// - 빌드 타임에 의존성 그래프 자동 검증
```

#### 3️⃣ 앱에서 사용하기 (2분)

```swift
// SwiftUI에서 사용
struct UserProfileView: View {
    @Inject(UserServiceKey.self) private var userService
    @State private var user: User?
    @State private var isLoading = false
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("사용자 정보 로딩 중...")
            } else if let user = user {
                VStack(alignment: .leading, spacing: 8) {
                    Text(user.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(user.email)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("사용자 정보를 불러올 수 없습니다")
                    .foregroundColor(.red)
            }
        }
        .task {
            await loadUser()
        }
    }
    
    private func loadUser() async {
        isLoading = true
        defer { isLoading = false }
        
        // 안전한 접근
        let service = await userService()
        
        do {
            user = try await service.getCurrentUser()
        } catch {
            print("사용자 정보 로딩 실패: \(error)")
            // 에러가 발생해도 앱이 크래시하지 않음
        }
    }
}

// UIKit에서 사용
class UserViewController: UIViewController {
    @Inject(UserServiceKey.self) private var userService
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        Task {
            let service = await userService()
            let user = try? await service.getCurrentUser()
            
            await MainActor.run {
                // UI 업데이트
                updateUI(with: user)
            }
        }
    }
}
```

#### 4️⃣ 앱 초기화 (30초)

```swift
// App.swift
@main
struct MyApp: App {
    init() {
        // 스코프 기반 점진적 로딩으로 앱 시작 성능 최적화
        Task {
            try await Weaver.setup(modules: [
                CoreModule(),      // .startup 스코프 - 즉시 로딩
                NetworkModule(),   // .shared 스코프 - 사용 시 로딩
                UserModule(),      // .shared 스코프 - 사용 시 로딩
                FeatureModule()    // .whenNeeded 스코프 - 필요 시 로딩
            ])
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**완성!** 이제 앱 어디서든 `@Inject`로 안전한 의존성을 사용할 수 있습니다.

### 실전 팁

#### 에러 처리가 필요한 경우
```swift
@Inject(UserServiceKey.self) private var userService

func criticalOperation() async {
    do {
        // 명시적 에러 처리가 필요한 경우
        let service = try await $userService.resolve()
        try await service.updateProfile(newUser)
    } catch {
        // 의존성 해결 실패 또는 서비스 에러 처리
        showErrorAlert(error)
    }
}
```

#### Preview에서 다양한 상태 테스트
```swift
#Preview("로딩 상태") {
    UserProfileView()
        .weaver(modules: PreviewWeaverContainer.previewModules(
            .register(UserServiceKey.self) { _ in
                SlowMockUserService() // 의도적으로 느린 서비스
            }
        ))
}

#Preview("에러 상태") {
    UserProfileView()
        .weaver(modules: PreviewWeaverContainer.previewModules(
            .register(UserServiceKey.self) { _ in
                FailingMockUserService() // 항상 에러를 던지는 서비스
            }
        ))
}
```

#### 타입 기반 편의 API 사용
```swift
// DependencyKey 없이 간단한 의존성 등록
await builder.registerType(
    UserService.self,
    scope: .shared,
    defaultValue: MockUserService()  // 안전한 기본값 필수
) { _ in
    APIUserService()
}

// 타입 기반 주입
@InjectType(UserService.self) private var userService
```

### 5. 앱 초기화

```swift
@main
struct MyApp: App {
    init() {
        Task {
            // 스코프 기반 점진적 로딩으로 앱 시작 성능 최적화
            try await Weaver.setup(modules: [AppModule()])
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## 📚 고급 사용법

### 🎨 SwiftUI Preview 강화

타입 안전한 Preview 시스템으로 더 쉽고 안전하게 Mock을 등록할 수 있습니다:

```swift
#Preview {
    ContentView()
        .weaver(modules: PreviewWeaverContainer.previewModules(
            // 타입 안전한 Mock 등록
            .register(NetworkServiceKey.self, mockValue: MockNetworkService(baseURL: "https://preview.api.com")),
            .register(DatabaseServiceKey.self) { _ in
                MockDatabaseService(connectionString: "preview://memory")
            },
            .register(LoggerServiceKey.self, mockValue: MockLoggerService(level: .debug))
        ))
}

// 편의 메서드 사용
#Preview {
    ContentView()
        .weaver(modules: [
            PreviewWeaverContainer.mockNetworkService(baseURL: "https://preview.api.com"),
            PreviewWeaverContainer.mockDatabaseService(),
            PreviewWeaverContainer.mockLoggerService(level: .debug)
        ])
}
```

**장점:**
- 타입 안전: 컴파일 타임에 타입 검증
- 간편함: 한 줄로 Mock 등록
- 재사용: 공통 Mock을 여러 Preview에서 사용
- 격리: Preview별 독립적인 의존성 환경
- 크래시 방지: Preview 환경에서 안전하게 동작

### ⚙️ 확장 가능한 우선순위 시스템

복잡한 앱에서 서비스 초기화 순서를 세밀하게 제어할 수 있습니다:

```swift
// 기본 우선순위 시스템 (자동)
// LoggerService: 0 (startup) + 0 (logger) + 0 (의존성 없음) = 0
// NetworkService: 0 (startup) + 30 (network) + 1 (logger 의존) = 31
// DatabaseService: 0 (startup) + 40 (database) + 2 (logger, network 의존) = 42

// 커스텀 우선순위 제공자
let customProvider = DefaultServicePriorityProvider()

let container = await WeaverContainer.builder()
    .withPriorityProvider(customProvider)
    .register(...)
    .build()
```

**3단계 우선순위 시스템:**
1. **스코프 기반** (100단위): startup(0) → shared(100) → whenNeeded(200) → weak(300)
2. **서비스명 기반** (10단위): logger(0) → config(10) → network(30) → database(40)
3. **의존성 기반** (1단위): 의존성 개수만큼 추가

### 🎛️ 직관적인 5가지 스코프

Weaver는 복잡한 설정 없이 바로 이해할 수 있는 5가지 스코프를 제공합니다:

| 스코프 | 설명 | 로딩 시점 | 예시 |
|--------|------|-----------|------|
| **`.startup`** | 앱 시작 시 즉시 로딩되는 필수 서비스 | 앱 시작 시 | `Logger`, `CrashReporter`, `AppConfig` |
| **`.shared`** | 앱 전체에서 하나의 인스턴스 공유 | 첫 사용 시 | `DatabaseManager`, `HTTPClient` |
| **`.whenNeeded`** | 실제 사용할 때만 로딩되는 기능별 서비스 | 필요 시 | `CameraService`, `PaymentService` |
| **`.weak`** | 약한 참조로 관리되어 메모리 누수 방지 | 첫 사용 시 | `ImageCache`, `NotificationCenter` |
| **`.transient`** | 매번 새로운 인스턴스를 생성 (일회성) | 매번 | `DataProcessor`, `TaskWorker` |

```swift
// 🚀 앱 시작 시 즉시 로딩 (필수 서비스)
await builder.register(LoggerKey.self, scope: .startup) { _ in
    ProductionLogger()
}

// 🔄 공유 인스턴스 (첫 사용 시 로딩)
await builder.register(DatabaseKey.self, scope: .shared) { _ in
    CoreDataManager()
}

// 💤 필요할 때만 로딩 (성능 최적화)
await builder.register(CameraServiceKey.self, scope: .whenNeeded) { _ in
    CameraService()
}

// 🔄 매번 새로운 인스턴스 (일회성)
await builder.register(DataProcessorKey.self, scope: .transient) { _ in
    DataProcessor()
}

// 🧹 약한 참조 (메모리 효율)
await builder.registerWeak(ImageCacheKey.self) { _ in
    ImageCache()
}
```

**스코프의 장점:**
- 단순함: 5가지만 기억하면 됨
- 직관적: 이름만 봐도 언제 사용할지 명확
- 점진적 로딩: 앱 시작 성능 최적화
- 메모리 효율: 약한 참조와 자동 정리
- 생명주기 지원: 필수 서비스부터 일회성까지 모든 패턴 지원

### 조건부 등록

```swift
struct EnvironmentModule: Module {
    let isProduction: Bool
    
    func configure(_ builder: WeaverBuilder) async {
        if isProduction {
            await builder.register(AnalyticsKey.self) { _ in
                FirebaseAnalytics()
            }
        } else {
            await builder.register(AnalyticsKey.self) { _ in
                ConsoleAnalytics()
            }
        }
    }
}
```

### 의존성 체인

```swift
struct ServiceModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        // 기본 서비스들
        await builder.register(NetworkClientKey.self) { _ in
            URLSessionClient()
        }
        
        await builder.register(DatabaseKey.self) { _ in
            CoreDataManager()
        }
        
        // 의존성을 가진 서비스
        await builder.register(UserServiceKey.self) { resolver in
            let networkClient = try await resolver.resolve(NetworkClientKey.self)
            let database = try await resolver.resolve(DatabaseKey.self)
            return UserService(
                networkClient: networkClient,
                database: database
            )
        }
    }
}
```

## 🎨 편의 API (Convenience API)

### 타입 기반 간편 등록

DependencyKey를 직접 정의하지 않고도 타입만으로 의존성을 등록할 수 있습니다:

```swift
// ✨ 기존 방식 (완전한 타입 안전성)
struct UserServiceKey: DependencyKey {
    typealias Value = UserService
    static var defaultValue: UserService { MockUserService() }
}

await builder.register(UserServiceKey.self, scope: .shared) { _ in
    APIUserService()
}

// 🚀 편의 API (간단한 의존성용)
await builder.registerType(
    UserService.self,
    scope: .shared,
    defaultValue: MockUserService()  // 안전한 기본값 필수
) { _ in
    APIUserService()
}
```

### 타입 기반 주입

```swift
// 기존 방식
@Inject(UserServiceKey.self) private var userService

// 편의 API
@InjectType(UserService.self) private var userService

// 사용법은 동일
let service = await userService()
```

### 약한 참조 편의 API

```swift
// 클래스 타입만 지원 (컴파일 타임 검증)
await builder.registerTypeWeak(
    ImageCache.self,
    defaultValue: InMemoryImageCache()
) { _ in
    DiskImageCache()
}
```

### DefaultValue 가이드라인

```swift
// 환경별 안전한 기본값 제공
struct UserServiceKey: DependencyKey {
    typealias Value = UserService
    static var defaultValue: UserService {
        DefaultValueGuidelines.safeDefault(
            production: OfflineUserService(),
            preview: MockUserService()
        )
    }
}
```

**편의 API의 장점:**
- 간결함: DependencyKey 구조체 생략 가능
- 안전성: 기본값 제공 강제로 크래시 방지
- 호환성: 기존 DependencyKey 방식과 호환
- 선택권: 복잡한 의존성은 DependencyKey, 간단한 것은 편의 API

### 테스트 환경 설정

```swift
class UserServiceTests: XCTestCase {
    func testUserCreation() async throws {
        // 격리된 테스트 환경
        await Weaver.shared.withIsolatedTestEnvironment(modules: [TestModule()]) {
            @Inject(UserServiceKey.self) var userService
            let service = await userService()
            let user = try await service.getCurrentUser()
            XCTAssertEqual(user?.name, "Test User")
        }
    }
}

struct TestModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        // Mock 서비스 등록
        await builder.register(UserServiceKey.self) { _ in
            MockUserService()
        }
    }
}
```

## 🎯 실전 사용 사례 & 패턴

### 📱 실제 앱 개발 시나리오

#### 1. 🌐 네트워크 + 캐시 + 에러 처리 완전 가이드

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

// 2️⃣ 네트워크 클라이언트 구현
protocol NetworkClient: Sendable {
    func get<T: Codable>(_ endpoint: String) async throws -> T
    func post<T: Codable, U: Codable>(_ endpoint: String, body: T) async throws -> U
}

final class URLSessionNetworkClient: NetworkClient {
    private let baseURL: String
    private let session: URLSession
    
    init(baseURL: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }
    
    func get<T: Codable>(_ endpoint: String) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw NetworkError.invalidResponse
        }
        
        do {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                throw NetworkError.serverError(httpResponse.statusCode)
            }
            
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if error is DecodingError {
                throw NetworkError.invalidResponse
            }
            throw error
        }
    }
    
    func post<T: Codable, U: Codable>(_ endpoint: String, body: T) async throws -> U {
        // POST 구현...
        fatalError("구현 필요")
    }
}

// 3️⃣ 캐시 시스템
final class ResponseCache: Sendable {
    private let cache = NSCache<NSString, NSData>()
    
    init(maxSize: Int = 100) {
        cache.countLimit = maxSize
    }
    
    func get<T: Codable>(_ key: String, type: T.Type) -> T? {
        guard let data = cache.object(forKey: key as NSString) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data as Data)
    }
    
    func set<T: Codable>(_ key: String, value: T) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        cache.setObject(data as NSData, forKey: key as NSString)
    }
}

// 4️⃣ 캐시된 네트워크 서비스
final class CachedNetworkService: Sendable {
    private let networkClient: NetworkClient
    private let cache: ResponseCache
    private let cacheTimeout: TimeInterval = 300 // 5분
    
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

// 5️⃣ 모듈 구성
struct NetworkModule: Module {
    let environment: AppEnvironment
    
    func configure(_ builder: WeaverBuilder) async {
        // 환경별 베이스 URL
        let baseURL = environment == .production 
            ? "https://api.myapp.com" 
            : "https://staging-api.myapp.com"
        
        // HTTP 클라이언트 (공유 인스턴스)
        await builder.register(NetworkClientKey.self, scope: .shared) { _ in
            URLSessionNetworkClient(baseURL: baseURL)
        }
        
        // 응답 캐시 (약한 참조로 메모리 효율적 관리)
        await builder.registerWeak(ResponseCacheKey.self) { _ in
            ResponseCache(maxSize: 100)
        }
        
        // 캐시된 네트워크 서비스
        await builder.register(CachedNetworkServiceKey.self, scope: .shared) { resolver in
            let networkClient = try await resolver.resolve(NetworkClientKey.self)
            let cache = try await resolver.resolve(ResponseCacheKey.self)
            return CachedNetworkService(networkClient: networkClient, cache: cache)
        }
    }
}

// 6️⃣ SwiftUI에서 사용
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
        .task {
            await loadUsers()
        }
        .refreshable {
            await loadUsers()
        }
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

**이 패턴의 장점:**
- 네트워크 에러 처리 구현
- 캐시로 성능 최적화
- 환경별 설정 분리
- SwiftUI와 통합
- 메모리 효율적 관리

#### 2. 🔐 인증 + 토큰 관리 + 자동 갱신 시스템

```swift
// 1️⃣ 인증 토큰 모델
struct AuthToken: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    
    var isExpired: Bool {
        Date() >= expiresAt
    }
    
    var willExpireSoon: Bool {
        Date().addingTimeInterval(300) >= expiresAt // 5분 전
    }
}

// 2️⃣ 키체인 저장소
protocol SecureStorage: Sendable {
    func store(_ token: AuthToken) async throws
    func retrieve() async throws -> AuthToken?
    func delete() async throws
}

final class KeychainSecureStorage: SecureStorage {
    private let service = "com.myapp.auth"
    private let account = "user_token"
    
    func store(_ token: AuthToken) async throws {
        let data = try JSONEncoder().encode(token)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        
        // 기존 항목 삭제 후 새로 저장
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw AuthError.keychainError(status)
        }
    }
    
    func retrieve() async throws -> AuthToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        
        return try JSONDecoder().decode(AuthToken.self, from: data)
    }
    
    func delete() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthError.keychainError(status)
        }
    }
}

// 3️⃣ 인증 서비스
protocol AuthService: Sendable {
    func login(email: String, password: String) async throws -> AuthToken
    func refreshToken() async throws -> AuthToken
    func logout() async throws
    func getCurrentToken() async throws -> AuthToken?
    var isAuthenticated: Bool { get async }
}

final class APIAuthService: AuthService {
    private let networkClient: NetworkClient
    private let secureStorage: SecureStorage
    private let tokenRefreshLock = NSLock()
    
    init(networkClient: NetworkClient, secureStorage: SecureStorage) {
        self.networkClient = networkClient
        self.secureStorage = secureStorage
    }
    
    func login(email: String, password: String) async throws -> AuthToken {
        struct LoginRequest: Codable {
            let email: String
            let password: String
        }
        
        struct LoginResponse: Codable {
            let accessToken: String
            let refreshToken: String
            let expiresIn: Int
        }
        
        let request = LoginRequest(email: email, password: password)
        let response: LoginResponse = try await networkClient.post("/auth/login", body: request)
        
        let token = AuthToken(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
        
        try await secureStorage.store(token)
        return token
    }
    
    func refreshToken() async throws -> AuthToken {
        // 동시 갱신 방지를 위한 락
        return try await withCheckedThrowingContinuation { continuation in
            tokenRefreshLock.lock()
            defer { tokenRefreshLock.unlock() }
            
            Task {
                do {
                    guard let currentToken = try await secureStorage.retrieve() else {
                        throw AuthError.noTokenFound
                    }
                    
                    struct RefreshRequest: Codable {
                        let refreshToken: String
                    }
                    
                    struct RefreshResponse: Codable {
                        let accessToken: String
                        let refreshToken: String
                        let expiresIn: Int
                    }
                    
                    let request = RefreshRequest(refreshToken: currentToken.refreshToken)
                    let response: RefreshResponse = try await networkClient.post("/auth/refresh", body: request)
                    
                    let newToken = AuthToken(
                        accessToken: response.accessToken,
                        refreshToken: response.refreshToken,
                        expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
                    )
                    
                    try await secureStorage.store(newToken)
                    continuation.resume(returning: newToken)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func logout() async throws {
        try await secureStorage.delete()
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
    
    var isAuthenticated: Bool {
        get async {
            do {
                return try await getCurrentToken() != nil
            } catch {
                return false
            }
        }
    }
}

// 4️⃣ 인증이 필요한 네트워크 클라이언트
final class AuthenticatedNetworkClient: NetworkClient {
    private let baseClient: NetworkClient
    private let authService: AuthService
    
    init(baseClient: NetworkClient, authService: AuthService) {
        self.baseClient = baseClient
        self.authService = authService
    }
    
    func get<T: Codable>(_ endpoint: String) async throws -> T {
        return try await performAuthenticatedRequest {
            try await baseClient.get(endpoint)
        }
    }
    
    func post<T: Codable, U: Codable>(_ endpoint: String, body: T) async throws -> U {
        return try await performAuthenticatedRequest {
            try await baseClient.post(endpoint, body: body)
        }
    }
    
    private func performAuthenticatedRequest<T>(_ request: () async throws -> T) async throws -> T {
        guard let token = try await authService.getCurrentToken() else {
            throw AuthError.notAuthenticated
        }
        
        // 여기서 실제로는 Authorization 헤더를 추가해야 함
        // 간단한 예제를 위해 생략
        return try await request()
    }
}

// 5️⃣ 모듈 구성
struct AuthModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        // 보안 저장소
        await builder.register(SecureStorageKey.self, scope: .shared) { _ in
            KeychainSecureStorage()
        }
        
        // 인증 서비스
        await builder.register(AuthServiceKey.self, scope: .shared) { resolver in
            let networkClient = try await resolver.resolve(NetworkClientKey.self)
            let secureStorage = try await resolver.resolve(SecureStorageKey.self)
            return APIAuthService(networkClient: networkClient, secureStorage: secureStorage)
        }
        
        // 인증된 네트워크 클라이언트
        await builder.register(AuthenticatedNetworkClientKey.self, scope: .shared) { resolver in
            let baseClient = try await resolver.resolve(NetworkClientKey.self)
            let authService = try await resolver.resolve(AuthServiceKey.self)
            return AuthenticatedNetworkClient(baseClient: baseClient, authService: authService)
        }
    }
}

// 6️⃣ 로그인 화면
struct LoginView: View {
    @Inject(AuthServiceKey.self) private var authService
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            TextField("이메일", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
            
            SecureField("비밀번호", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Button("로그인") {
                Task { await performLogin() }
            }
            .disabled(isLoading || email.isEmpty || password.isEmpty)
            
            if isLoading {
                ProgressView("로그인 중...")
            }
        }
        .padding()
        .alert("로그인 실패", isPresented: .constant(errorMessage != nil)) {
            Button("확인") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    private func performLogin() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let service = await authService()
            _ = try await service.login(email: email, password: password)
            // 로그인 성공 처리...
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

#### 3. 🧪 A/B 테스트 + 기능 플래그 시스템

```swift
// 1️⃣ 기능 플래그 모델
struct FeatureFlag: Codable, Sendable {
    let key: String
    let isEnabled: Bool
    let variant: String?
    let rolloutPercentage: Double
    let targetAudience: [String]
    
    func isEnabledForUser(_ userId: String) -> Bool {
        // 타겟 오디언스 체크
        if !targetAudience.isEmpty && !targetAudience.contains(userId) {
            return false
        }
        
        // 롤아웃 퍼센티지 체크
        let userHash = abs(userId.hashValue) % 100
        return isEnabled && Double(userHash) < rolloutPercentage
    }
}

// 2️⃣ A/B 테스트 매니저
protocol ABTestManager: Sendable {
    func getVariant(for experiment: String, userId: String) async -> String
    func isFeatureEnabled(_ feature: String, userId: String) async -> Bool
    func trackExperimentExposure(_ experiment: String, variant: String, userId: String) async
}

final class RemoteABTestManager: ABTestManager {
    private let networkClient: NetworkClient
    private let cache: ResponseCache
    private let analytics: AnalyticsService
    
    init(networkClient: NetworkClient, cache: ResponseCache, analytics: AnalyticsService) {
        self.networkClient = networkClient
        self.cache = cache
        self.analytics = analytics
    }
    
    func getVariant(for experiment: String, userId: String) async -> String {
        do {
            // 캐시에서 먼저 확인
            let cacheKey = "experiment_\(experiment)_\(userId)"
            if let cachedVariant = cache.get(cacheKey, type: String.self) {
                return cachedVariant
            }
            
            // 서버에서 실험 설정 가져오기
            struct ExperimentRequest: Codable {
                let experimentKey: String
                let userId: String
            }
            
            struct ExperimentResponse: Codable {
                let variant: String
                let shouldTrack: Bool
            }
            
            let request = ExperimentRequest(experimentKey: experiment, userId: userId)
            let response: ExperimentResponse = try await networkClient.post("/experiments/assign", body: request)
            
            // 결과 캐싱 (1시간)
            cache.set(cacheKey, value: response.variant)
            
            // 실험 노출 추적
            if response.shouldTrack {
                await trackExperimentExposure(experiment, variant: response.variant, userId: userId)
            }
            
            return response.variant
        } catch {
            // 에러 시 기본 변형 반환
            return "control"
        }
    }
    
    func isFeatureEnabled(_ feature: String, userId: String) async -> Bool {
        do {
            let flags: [FeatureFlag] = try await networkClient.get("/features/flags")
            
            guard let flag = flags.first(where: { $0.key == feature }) else {
                return false
            }
            
            return flag.isEnabledForUser(userId)
        } catch {
            return false
        }
    }
    
    func trackExperimentExposure(_ experiment: String, variant: String, userId: String) async {
        await analytics.track("experiment_exposure", properties: [
            "experiment": experiment,
            "variant": variant,
            "user_id": userId
        ])
    }
}

// 3️⃣ 조건부 서비스 팩토리
struct ConditionalServiceFactory {
    static func createRecommendationService(
        abTestManager: ABTestManager,
        userId: String,
        networkClient: NetworkClient
    ) async -> any RecommendationService {
        let variant = await abTestManager.getVariant(for: "recommendation_algorithm", userId: userId)
        
        switch variant {
        case "ml_enhanced":
            return MLRecommendationService(networkClient: networkClient)
        case "collaborative_filtering":
            return CollaborativeFilteringService(networkClient: networkClient)
        case "hybrid":
            return HybridRecommendationService(networkClient: networkClient)
        default:
            return BasicRecommendationService(networkClient: networkClient)
        }
    }
}

// 4️⃣ 추천 서비스 구현들
protocol RecommendationService: Sendable {
    func getRecommendations(for userId: String) async throws -> [Recommendation]
}

final class BasicRecommendationService: RecommendationService {
    private let networkClient: NetworkClient
    
    init(networkClient: NetworkClient) {
        self.networkClient = networkClient
    }
    
    func getRecommendations(for userId: String) async throws -> [Recommendation] {
        return try await networkClient.get("/recommendations/basic?userId=\(userId)")
    }
}

final class MLRecommendationService: RecommendationService {
    private let networkClient: NetworkClient
    
    init(networkClient: NetworkClient) {
        self.networkClient = networkClient
    }
    
    func getRecommendations(for userId: String) async throws -> [Recommendation] {
        return try await networkClient.get("/recommendations/ml?userId=\(userId)")
    }
}

// 5️⃣ 모듈 구성
struct ABTestModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        // A/B 테스트 매니저
        await builder.register(ABTestManagerKey.self, scope: .shared) { resolver in
            let networkClient = try await resolver.resolve(NetworkClientKey.self)
            let cache = try await resolver.resolve(ResponseCacheKey.self)
            let analytics = try await resolver.resolve(AnalyticsServiceKey.self)
            return RemoteABTestManager(
                networkClient: networkClient,
                cache: cache,
                analytics: analytics
            )
        }
        
        // 사용자별 추천 서비스 (동적 생성)
        await builder.register(RecommendationServiceKey.self, scope: .whenNeeded) { resolver in
            let abTestManager = try await resolver.resolve(ABTestManagerKey.self)
            let networkClient = try await resolver.resolve(NetworkClientKey.self)
            let userSession = try await resolver.resolve(UserSessionKey.self)
            
            return await ConditionalServiceFactory.createRecommendationService(
                abTestManager: abTestManager,
                userId: userSession.currentUserId,
                networkClient: networkClient
            )
        }
    }
}

// 6️⃣ SwiftUI에서 기능 플래그 사용
struct RecommendationView: View {
    @Inject(ABTestManagerKey.self) private var abTestManager
    @Inject(RecommendationServiceKey.self) private var recommendationService
    @Inject(UserSessionKey.self) private var userSession
    
    @State private var recommendations: [Recommendation] = []
    @State private var isNewUIEnabled = false
    
    var body: some View {
        Group {
            if isNewUIEnabled {
                NewRecommendationListView(recommendations: recommendations)
            } else {
                ClassicRecommendationListView(recommendations: recommendations)
            }
        }
        .task {
            await loadRecommendations()
            await checkFeatureFlags()
        }
    }
    
    private func loadRecommendations() async {
        do {
            let service = await recommendationService()
            let session = await userSession()
            recommendations = try await service.getRecommendations(for: session.currentUserId)
        } catch {
            print("추천 로딩 실패: \(error)")
        }
    }
    
    private func checkFeatureFlags() async {
        let manager = await abTestManager()
        let session = await userSession()
        isNewUIEnabled = await manager.isFeatureEnabled("new_recommendation_ui", userId: session.currentUserId)
    }
}

// 7️⃣ 실험 결과 분석을 위한 이벤트 추적
extension RecommendationView {
    private func trackRecommendationClick(_ recommendation: Recommendation) async {
        let manager = await abTestManager()
        let session = await userSession()
        
        // 현재 실험 변형 확인
        let variant = await manager.getVariant(for: "recommendation_algorithm", userId: session.currentUserId)
        
        // 클릭 이벤트 추적
        await manager.trackExperimentExposure("recommendation_click", variant: variant, userId: session.currentUserId)
    }
}
```


## 성능 최적화 & 고급 패턴

### 성능 모니터링 및 최적화

#### 1. 실시간 성능 모니터링

```swift
// 1️⃣ 성능 모니터 설정
struct PerformanceModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(PerformanceMonitorKey.self, scope: .shared) { _ in
            WeaverPerformanceMonitor(
                enabled: WeaverEnvironment.isDevelopment,
                slowResolutionThreshold: 0.1, // 100ms
                memoryWarningThreshold: 200    // 200MB
            )
        }
    }
}

// 2️⃣ 성능 측정 래퍼 사용
struct OptimizedUserService: UserService {
    @Inject(PerformanceMonitorKey.self) private var monitor
    @Inject(NetworkClientKey.self) private var networkClient
    
    func getCurrentUser() async throws -> User? {
        let performanceMonitor = await monitor()
        
        return try await performanceMonitor.measureResolution(keyName: "getCurrentUser") {
            let client = await networkClient()
            return try await client.get("/user/me")
        }
    }
}

// 3️⃣ 성능 보고서 자동 생성
class PerformanceReportingService {
    @Inject(PerformanceMonitorKey.self) private var monitor
    
    func generateDailyReport() async {
        let performanceMonitor = await monitor()
        let report = await performanceMonitor.generatePerformanceReport()
        
        print("""
        일일 성능 보고서
        ==================
        \(report.description)
        
        느린 해결 (100ms 이상):
        \(report.slowResolutions.map { "- \($0.keyName): \(String(format: "%.2f", $0.duration * 1000))ms" }.joined(separator: "\n"))
        
        메모리 사용량:
        - 평균: \(report.averageMemoryUsage / 1024 / 1024)MB
        - 최대: \(report.peakMemoryUsage / 1024 / 1024)MB
        """)
        
        // 성능 이슈가 있으면 알림
        if report.averageResolutionTime > 0.05 { // 50ms 이상
            await sendPerformanceAlert(report)
        }
    }
    
    private func sendPerformanceAlert(_ report: PerformanceReport) async {
        // 개발팀에 성능 알림 전송
        print("성능 경고: 평균 해결 시간이 \(String(format: "%.2f", report.averageResolutionTime * 1000))ms입니다")
    }
}
```

#### 2. 메모리 최적화 패턴

```swift
// 1️⃣ 메모리 압박 감지 및 자동 정리
class MemoryOptimizedContainer {
    @Inject(WeaverContainerKey.self) private var container
    
    init() {
        // 메모리 경고 알림 등록
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
        
        // 강제 메모리 정리 실행
        await weaverContainer.performMemoryCleanup(forced: true)
        
        print("메모리 경고로 인한 DI 컨테이너 정리 완료")
    }
}

// 2️⃣ 스마트 캐싱 전략
final class SmartCacheManager: CacheManaging {
    private var cache: [AnyDependencyKey: (instance: any Sendable, lastAccessed: Date)] = [:]
    private let maxCacheSize = 50
    private let cacheTimeout: TimeInterval = 300 // 5분
    
    func taskForInstance<T: Sendable>(
        key: AnyDependencyKey,
        factory: @Sendable @escaping () async throws -> T
    ) async -> (task: Task<any Sendable, Error>, isHit: Bool) {
        
        // 캐시 정리 (오래된 항목 제거)
        await cleanupExpiredItems()
        
        // 캐시 히트 확인
        if let cached = cache[key],
           Date().timeIntervalSince(cached.lastAccessed) < cacheTimeout {
            
            // 접근 시간 업데이트
            cache[key] = (cached.instance, Date())
            
            let task = Task<any Sendable, Error> {
                return cached.instance
            }
            return (task, true)
        }
        
        // 캐시 미스 - 새로 생성
        let task = Task<any Sendable, Error> {
            let instance = try await factory()
            
            // 캐시 크기 제한 확인
            if cache.count >= maxCacheSize {
                await evictLeastRecentlyUsed()
            }
            
            cache[key] = (instance, Date())
            return instance
        }
        
        return (task, false)
    }
    
    private func cleanupExpiredItems() async {
        let now = Date()
        cache = cache.filter { _, value in
            now.timeIntervalSince(value.lastAccessed) < cacheTimeout
        }
    }
    
    private func evictLeastRecentlyUsed() async {
        guard let oldestKey = cache.min(by: { $0.value.lastAccessed < $1.value.lastAccessed })?.key else {
            return
        }
        cache.removeValue(forKey: oldestKey)
    }
    
    func getMetrics() async -> (hits: Int, misses: Int) {
        // 실제 구현에서는 히트/미스 카운터 유지
        return (0, 0)
    }
    
    func clear() async {
        cache.removeAll()
    }
}
```

#### 3. 지연 로딩 최적화

```swift
// 1️⃣ 조건부 지연 로딩
struct ConditionalLazyModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        // 사용자가 프리미엄 기능에 접근할 때만 로딩
        await builder.register(PremiumFeatureServiceKey.self, scope: .whenNeeded) { resolver in
            let userSession = try await resolver.resolve(UserSessionKey.self)
            
            // 프리미엄 사용자가 아니면 제한된 서비스 반환
            guard userSession.isPremiumUser else {
                return LimitedFeatureService()
            }
            
            // 프리미엄 사용자만 전체 기능 서비스 로딩
            let networkClient = try await resolver.resolve(NetworkClientKey.self)
            let analytics = try await resolver.resolve(AnalyticsServiceKey.self)
            
            return FullPremiumFeatureService(
                networkClient: networkClient,
                analytics: analytics
            )
        }
        
        // 위치 기반 서비스 - 권한이 있을 때만 로딩
        await builder.register(LocationServiceKey.self, scope: .whenNeeded) { _ in
            guard await LocationPermissionManager.hasPermission() else {
                return NoOpLocationService()
            }
            
            return CoreLocationService()
        }
    }
}

// 2️⃣ 백그라운드 예열 (Prewarming)
class ServicePrewarmingManager {
    @Inject(WeaverContainerKey.self) private var container
    
    func prewarmCriticalServices() async {
        let container = await container()
        
        // 백그라운드에서 중요한 서비스들을 미리 로딩
        Task.detached(priority: .background) {
            _ = try? await container.resolve(NetworkClientKey.self)
            _ = try? await container.resolve(UserSessionKey.self)
            _ = try? await container.resolve(AnalyticsServiceKey.self)
            
            print("중요 서비스 예열 완료")
        }
    }
    
    func prewarmBasedOnUserBehavior() async {
        let container = await container()
        
        // 사용자 행동 패턴에 따른 예측적 로딩
        Task.detached(priority: .utility) {
            let userSession = try? await container.resolve(UserSessionKey.self)
            
            // 사용자가 자주 사용하는 기능 예측
            if let session = userSession, session.frequentlyUsesCamera {
                _ = try? await container.resolve(CameraServiceKey.self)
            }
            
            if let session = userSession, session.frequentlyUsesLocation {
                _ = try? await container.resolve(LocationServiceKey.self)
            }
        }
    }
}
```

#### 4. 배치 해결 최적화

```swift
// 1️⃣ 배치 의존성 해결
extension WeaverContainer {
    func resolveBatch<T1: DependencyKey, T2: DependencyKey, T3: DependencyKey>(
        _ key1: T1.Type,
        _ key2: T2.Type,
        _ key3: T3.Type
    ) async throws -> (T1.Value, T2.Value, T3.Value) {
        
        // 병렬로 해결하여 성능 최적화
        async let service1 = resolve(key1)
        async let service2 = resolve(key2)
        async let service3 = resolve(key3)
        
        return try await (service1, service2, service3)
    }
}

// 2️⃣ 사용 예시
struct OptimizedViewController: UIViewController {
    @Inject(WeaverContainerKey.self) private var container
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        Task {
            let weaverContainer = await container()
            
            // 여러 서비스를 병렬로 해결
            let (userService, networkService, analyticsService) = try await weaverContainer.resolveBatch(
                UserServiceKey.self,
                NetworkServiceKey.self,
                AnalyticsServiceKey.self
            )
            
            // 모든 서비스가 준비된 후 UI 업데이트
            await MainActor.run {
                setupUI(userService: userService, networkService: networkService, analyticsService: analyticsService)
            }
        }
    }
}
```

### 앱 생명주기 연동

```swift
class AnalyticsService: AppLifecycleAware {
    func appDidEnterBackground() async throws {
        // 백그라운드 진입 시 데이터 플러시
        await flushEvents()
    }
    
    func appWillEnterForeground() async throws {
        // 포그라운드 복귀 시 세션 재시작
        await startNewSession()
    }
    
    func appWillTerminate() async throws {
        // 앱 종료 시 정리 작업
        await cleanup()
    }
}

// startup 스코프로 등록하면 앱 시작 시 자동으로 초기화
await builder.register(AnalyticsKey.self, scope: .startup) { _ in
    AnalyticsService()
}
```

### 메모리 관리

```swift
// 약한 참조 사용 (클래스 타입만 가능)
await builder.registerWeak(ImageCacheKey.self) { _ in
    ImageCache() // 메모리 압박 시 자동 해제
}

// 수동 메모리 정리
await container.performMemoryCleanup(forced: true)

// WeakBox 패턴으로 안전한 약한 참조 관리
let weakCollection = WeakBoxCollection<String, MyService>()
await weakCollection.set(myService, for: "key")
let cleanedCount = await weakCollection.cleanup()
```

### 성능 모니터링 및 최적화

```swift
// WeaverPerformanceMonitor로 성능 측정
let monitor = WeaverPerformanceMonitor(enabled: true)

// 의존성 해결 성능 측정
let result = try await monitor.measureResolution(keyName: "UserService") {
    try await container.resolve(UserServiceKey.self)
}

// 성능 보고서 생성
let report = await monitor.generatePerformanceReport()
print(report.description)

// 메모리 압박 시 자동 정리
await container.performMemoryCleanup(forced: false)

// 메트릭 수집
let metrics = await container.getMetrics()
print("총 해결 횟수: \(metrics.totalResolutions)")
print("평균 해결 시간: \(String(format: "%.3f", metrics.averageResolutionTime * 1000))ms")
```


## 🔍 디버깅 도구

```swift
// 성능 모니터링 활성화
let monitor = WeaverPerformanceMonitor(enabled: WeaverEnvironment.isDevelopment)
let report = await monitor.generatePerformanceReport()
print(report.description)

// 의존성 그래프 검증
let graph = DependencyGraph(registrations: container.registrations)
let validation = graph.validate()
switch validation {
case .valid:
    print("의존성 그래프가 유효합니다")
case .circular(let path):
    print("순환 참조 감지: \(path.joined(separator: " → "))")
case .missing(let deps):
    print("누락된 의존성: \(deps.joined(separator: ", "))")
case .invalid(let key, let error):
    print("잘못된 설정: \(key) - \(error.localizedDescription)")
}

// DOT 그래프 생성 (시각화용)
let dotGraph = graph.generateDotGraph()
print("의존성 그래프 (DOT 형식):\n\(dotGraph)")


## 문제 해결 가이드

### 자주 발생하는 문제와 해결책

#### "Container not found" 에러

**문제**: `@Inject`를 사용했는데 "Container not found" 에러가 발생합니다.

```swift
// ❌ 문제가 되는 코드
@Inject(UserServiceKey.self) private var userService

func someFunction() async {
    let service = try await $userService.resolve() // 💥 Container not found
}
```

**해결책**:
```swift
// 해결 방법 1: 안전한 접근 사용 (권장)
@Inject(UserServiceKey.self) private var userService

func someFunction() async {
    let service = await userService() // 크래시하지 않음
}

// 해결 방법 2: 앱 초기화 확인
@main
struct MyApp: App {
    init() {
        Task {
            try await Weaver.setup(modules: [AppModule()]) // 이 부분이 누락되었을 수 있음
        }
    }
}

// 해결 방법 3: 커널 상태 확인
let kernelState = await Weaver.currentKernelState
switch kernelState {
case .ready:
    print("커널 준비 완료")
case .failed(let error):
    print("커널 실패: \(error)")
default:
    print("커널 상태: \(kernelState)")
}
```

#### SwiftUI Preview 크래시

**문제**: SwiftUI Preview에서 DI 관련 크래시가 발생합니다.

```swift
// ❌ 문제가 되는 코드
struct UserServiceKey: DependencyKey {
    typealias Value = UserService
    static var defaultValue: UserService { 
        fatalError("Use real implementation") // 💥 Preview에서 크래시
    }
}
```

**해결책**:
```swift
// Preview 친화적인 기본값
struct UserServiceKey: DependencyKey {
    typealias Value = UserService
    static var defaultValue: UserService { 
        MockUserService() // Preview에서 안전하게 동작
    }
}

// DefaultValueGuidelines 사용 (권장)
struct UserServiceKey: DependencyKey {
    typealias Value = UserService
    static var defaultValue: UserService {
        DefaultValueGuidelines.safeDefault(
            production: OfflineUserService(),
            preview: MockUserService()
        )
    }
}

// PreviewWeaverContainer 사용
#Preview {
    UserView()
        .weaver(modules: PreviewWeaverContainer.previewModules(
            .register(UserServiceKey.self, mockValue: MockUserService())
        ))
}
```

#### 순환 참조 에러

**문제**: "Circular dependency detected" 에러가 발생합니다.

```swift
// 순환 참조 문제
struct ModuleA: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(ServiceAKey.self) { resolver in
            let serviceB = try await resolver.resolve(ServiceBKey.self) // B에 의존
            return ServiceA(serviceB: serviceB)
        }
    }
}

struct ModuleB: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(ServiceBKey.self) { resolver in
            let serviceA = try await resolver.resolve(ServiceAKey.self) // A에 의존 💥
            return ServiceB(serviceA: serviceA)
        }
    }
}
```

**해결책**:
```swift
// 인터페이스 분리로 해결
protocol ServiceAInterface: Sendable {
    func doSomething() async
}

protocol ServiceBInterface: Sendable {
    func doSomethingElse() async
}

// 공통 의존성을 별도로 분리
struct SharedModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(SharedDataKey.self, scope: .shared) { _ in
            SharedDataService()
        }
    }
}

struct ServiceModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(ServiceAKey.self) { resolver in
            let sharedData = try await resolver.resolve(SharedDataKey.self)
            return ServiceA(sharedData: sharedData)
        }
        
        await builder.register(ServiceBKey.self) { resolver in
            let sharedData = try await resolver.resolve(SharedDataKey.self)
            return ServiceB(sharedData: sharedData)
        }
    }
}
```


### 🔍 디버깅 도구

#### 1. 성능 분석

```swift
// 개발 환경에서 성능 모니터링 활성화
let monitor = WeaverPerformanceMonitor(enabled: WeaverEnvironment.isDevelopment)

// 느린 의존성 해결 감지
let report = await monitor.generatePerformanceReport()
if !report.slowResolutions.isEmpty {
    print("느린 의존성 해결 감지:")
    for slow in report.slowResolutions {
        print("- \(slow.keyName): \(String(format: "%.2f", slow.duration * 1000))ms")
    }
}
```

#### 2. 의존성 그래프 검증

```swift
// 빌드 타임에 의존성 그래프 자동 검증
let builder = WeaverContainer.builder()
    .withModules([AppModule(), NetworkModule(), UserModule()])

// build() 호출 시 자동으로 검증됨
let container = try await builder.build()

// 수동 검증도 가능
let graph = DependencyGraph(registrations: container.registrations)
let validation = graph.validate()

switch validation {
case .valid:
    print("✅ 의존성 그래프가 유효합니다")
case .circular(let path):
    print("❌ 순환 참조 감지: \(path.joined(separator: " → "))")
case .missing(let deps):
    print("❌ 누락된 의존성: \(deps.joined(separator: ", "))")
case .invalid(let key, let error):
    print("❌ 잘못된 설정: \(key) - \(error.localizedDescription)")
}
}
```

#### 3. 메모리 누수 감지

```swift
// WeakBox 패턴으로 메모리 누수 감지
let weakCollection = WeakBoxCollection<String, MyService>()

// 서비스 등록
await weakCollection.set(myService, for: "service1")

// 메모리 정리 및 메트릭 확인
let cleanedCount = await weakCollection.cleanup()
let metrics = await weakCollection.getMetrics()

print("총 약한 참조: \(metrics.totalWeakReferences)")
print("살아있는 참조: \(metrics.aliveWeakReferences)")
print("해제된 참조: \(metrics.deallocatedWeakReferences)")

// 컨테이너 레벨 메모리 정리
await container.performMemoryCleanup(forced: false)

// 성능 모니터링과 함께 메모리 사용량 추적
await monitor.recordMemoryUsage()
```

### 📚 FAQ

<details>
<summary><strong>Q: Weaver와 다른 DI 라이브러리의 주요 차이점은 무엇인가요?</strong></summary>

**A**: Weaver의 핵심 차별점:
- 크래시 방지: `@Inject`의 `callAsFunction()`은 항상 안전한 값 반환
- 스코프 기반 점진적 로딩: 앱 시작 성능 최적화
- Swift 6 지원: Actor 기반 동시성으로 데이터 경쟁 방지
- 빌드 타임 검증: DependencyGraph로 순환 참조 사전 감지
- iOS 15+ 호환: 플랫폼별 최적화
- SwiftUI 통합: View 생명주기와 동기화
- 성능 모니터링: WeaverPerformanceMonitor로 분석

</details>


<details>
<summary><strong>Q: 성능에 미치는 영향은 어느 정도인가요?</strong></summary>

**A**: Weaver는 고성능을 위해 설계되었습니다:
- 의존성 해결: 평균 < 0.1ms
- 메모리 오버헤드: 최소 (약한 참조 자동 정리)
- 앱 시작 시간: 영향 없음 (비블로킹 초기화)
- 배터리 사용량: 영향 없음

</details>

<details>
<summary><strong>Q: 테스트는 어떻게 작성하나요?</strong></summary>

**A**: Weaver는 테스트 친화적으로 설계되었습니다:

```swift
func testUserService() async throws {
    // 테스트용 컨테이너 생성
    let testContainer = await WeaverContainer.builder()
        .override(NetworkClientKey.self) { _ in MockNetworkClient() }
        .override(UserServiceKey.self) { resolver in
            let mockClient = try await resolver.resolve(NetworkClientKey.self)
            return UserService(networkClient: mockClient)
        }
        .build()
    
    // 격리된 테스트 환경에서 실행
    await Weaver.withScope(testContainer) {
        @Inject(UserServiceKey.self) var userService
        let service = await userService()
        let user = try await service.getCurrentUser()
        XCTAssertEqual(user?.name, "Mock User")
    }
}
```

</details>

## 🤝 기여하기

Weaver는 오픈소스 프로젝트입니다. 기여를 환영합니다!

### 기여 방법

1. **이슈 리포트**: 버그나 개선 사항을 [GitHub Issues](https://github.com/AxiomOrient/weaver/issues)에 등록
2. **기능 제안**: 새로운 기능 아이디어를 [Discussions](https://github.com/AxiomOrient/weaver/discussions)에 공유
3. **코드 기여**: Pull Request를 통한 직접적인 코드 기여

## 📱 플랫폼 지원

- **iOS 15.0+**
- **macOS 13.0+**
- **watchOS 8.0+**
- **Swift 6.0+** (Actor 기반 동시성 완전 지원)

## 📚 추가 자료

- [📖 전체 API 문서](Docs/WeaverAPI.md)
- [🏗️ 아키텍처 가이드](Docs/ARCHITECTURE.md)
- [🎯 스코프 설계 가이드라인](Docs/SCOPE_DESIGN_GUIDELINES.md)
- [📖 튜토리얼](Docs/TUTORIAL.md)

## 💬 커뮤니티

- [GitHub Discussions](https://github.com/AxiomOrient/Weaver/discussions) - 질문과 토론
- [GitHub Issues](https://github.com/AxiomOrient/Weaver/issues) - 버그 리포트 및 기능 요청

---

**Weaver로 더 안전하고 빠른 Swift 앱을 만들어보세요.**

[![Star on GitHub](https://img.shields.io/github/stars/AxiomOrient/Weaver.svg?style=social)](https://github.com/AxiomOrient/Weaver/stargazers)

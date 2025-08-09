# Weaver DI 완전 튜토리얼

> 🎯 **실습 중심 학습** | **단계별 가이드** | **실제 앱 개발 시나리오**

이 튜토리얼은 Weaver DI를 처음 사용하는 개발자부터 고급 패턴을 배우고 싶은 개발자까지 모든 레벨을 위한 완전한 학습 가이드입니다.

## 📋 학습 목표

이 튜토리얼을 완료하면 다음을 할 수 있습니다:
- ✅ Weaver DI의 핵심 개념 이해
- ✅ 실제 앱에서 의존성 주입 구현
- ✅ SwiftUI와 UIKit에서 안전하게 사용
- ✅ 테스트 가능한 코드 작성
- ✅ 성능 최적화 및 메모리 관리
- ✅ 고급 패턴 적용 (A/B 테스트, 인증 등)

## 🎓 레벨별 학습 경로

### 🟢 초급 (Beginner)
- [1단계: 기본 개념과 첫 번째 의존성](#1단계-기본-개념과-첫-번째-의존성)
- [2단계: SwiftUI에서 사용하기](#2단계-swiftui에서-사용하기)
- [3단계: 모듈로 의존성 그룹화](#3단계-모듈로-의존성-그룹화)

### 🟡 중급 (Intermediate)  
- [4단계: 네트워크 서비스 구현](#4단계-네트워크-서비스-구현)
- [5단계: 에러 처리와 안전성](#5단계-에러-처리와-안전성)
- [6단계: 테스트 작성하기](#6단계-테스트-작성하기)

### 🔴 고급 (Advanced)
- [7단계: 인증 시스템 구현](#7단계-인증-시스템-구현)
- [8단계: 성능 최적화](#8단계-성능-최적화)
- [9단계: A/B 테스트 시스템](#9단계-ab-테스트-시스템)

---

## 🟢 초급 레벨

### 1단계: 기본 개념과 첫 번째 의존성

#### 🎯 학습 목표
- DependencyKey 프로토콜 이해
- 첫 번째 서비스 만들기
- @Inject 프로퍼티 래퍼 사용법

#### 📝 실습: 간단한 로거 서비스

**1.1 서비스 프로토콜 정의**
```swift
import Weaver

// 로깅 기능을 정의하는 프로토콜
protocol Logger: Sendable {
    func info(_ message: String)
    func error(_ message: String)
    func debug(_ message: String)
}
```

**1.2 실제 구현체 만들기**
```swift
// 콘솔에 로그를 출력하는 구현체
final class ConsoleLogger: Logger {
    private let dateFormatter: DateFormatter
    
    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }
    
    func info(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] [INFO] \(message)")
    }
    
    func error(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] [ERROR] \(message)")
    }
    
    func debug(_ message: String) {
        #if DEBUG
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] [DEBUG] \(message)")
        #endif
    }
}
```*
*1.3 의존성 키 정의**
```swift
// 의존성 키 - 타입 안전성의 핵심!
struct LoggerKey: DependencyKey {
    typealias Value = Logger
    
    // 🎯 크래시 방지를 위한 안전한 기본값
    static var defaultValue: Logger {
        if WeaverEnvironment.isPreview {
            return PreviewLogger() // Preview용 간단한 로거
        } else {
            return ConsoleLogger()
        }
    }
}

// Preview용 간단한 로거
struct PreviewLogger: Logger {
    func info(_ message: String) { print("Preview: \(message)") }
    func error(_ message: String) { print("Preview Error: \(message)") }
    func debug(_ message: String) { print("Preview Debug: \(message)") }
}
```

**1.4 앱에서 사용하기**
```swift
// App.swift
@main
struct TutorialApp: App {
    init() {
        // 앱 시작 시 DI 시스템 초기화
        Task {
            try await Weaver.setup(modules: [LoggingModule()])
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// 로깅 모듈
struct LoggingModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(LoggerKey.self, scope: .shared) { _ in
            ConsoleLogger()
        }
    }
}

// ContentView.swift
struct ContentView: View {
    @Inject(LoggerKey.self) private var logger
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Weaver DI 튜토리얼")
                .font(.title)
            
            Button("정보 로그") {
                Task {
                    let log = await logger()
                    log.info("정보 버튼이 클릭되었습니다!")
                }
            }
            
            Button("에러 로그") {
                Task {
                    let log = await logger()
                    log.error("에러 버튼이 클릭되었습니다!")
                }
            }
            
            Button("디버그 로그") {
                Task {
                    let log = await logger()
                    log.debug("디버그 버튼이 클릭되었습니다!")
                }
            }
        }
        .padding()
    }
}
```

**🎉 축하합니다!** 첫 번째 의존성 주입을 성공적으로 구현했습니다.

#### 💡 핵심 포인트
- `DependencyKey`는 타입 안전성을 보장합니다
- `defaultValue`는 절대 `fatalError()`를 사용하지 마세요
- `@Inject`의 `callAsFunction()`은 절대 크래시하지 않습니다
- `scope: .shared`는 싱글톤 패턴입니다

---

### 2단계: SwiftUI에서 사용하기

#### 🎯 학습 목표
- SwiftUI View에서 안전한 의존성 사용
- Preview에서 Mock 객체 사용
- View 생명주기와 DI 동기화

#### 📝 실습: 사용자 프로필 화면

**2.1 사용자 모델 정의**
```swift
struct User: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let email: String
    let avatarURL: String?
    
    static let mock = User(
        id: "mock-user",
        name: "김철수",
        email: "kim@example.com",
        avatarURL: nil
    )
}
```

**2.2 사용자 서비스 구현**
```swift
protocol UserService: Sendable {
    func getCurrentUser() async throws -> User?
    func updateProfile(name: String, email: String) async throws
}

// 실제 구현체 (나중에 네트워크 연동)
final class APIUserService: UserService {
    @Inject(LoggerKey.self) private var logger
    
    func getCurrentUser() async throws -> User? {
        let log = await logger()
        log.info("사용자 정보를 가져오는 중...")
        
        // 시뮬레이션을 위한 지연
        try await Task.sleep(for: .seconds(1))
        
        log.info("사용자 정보 로딩 완료")
        return User.mock
    }
    
    func updateProfile(name: String, email: String) async throws {
        let log = await logger()
        log.info("프로필 업데이트: \(name), \(email)")
        
        // 시뮬레이션을 위한 지연
        try await Task.sleep(for: .milliseconds(500))
        
        log.info("프로필 업데이트 완료")
    }
}

// Mock 구현체 (테스트/Preview용)
final class MockUserService: UserService {
    func getCurrentUser() async throws -> User? {
        return User.mock
    }
    
    func updateProfile(name: String, email: String) async throws {
        print("Mock: 프로필 업데이트 - \(name), \(email)")
    }
}

// 의존성 키
struct UserServiceKey: DependencyKey {
    typealias Value = UserService
    static var defaultValue: UserService { MockUserService() }
}
```

**2.3 사용자 프로필 View 구현**
```swift
struct UserProfileView: View {
    @Inject(UserServiceKey.self) private var userService
    @Inject(LoggerKey.self) private var logger
    
    @State private var user: User?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isEditing = false
    @State private var editName = ""
    @State private var editEmail = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("사용자 정보 로딩 중...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let user = user {
                    userInfoView(user)
                } else {
                    Text("사용자 정보를 불러올 수 없습니다")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("프로필")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if user != nil && !isLoading {
                    Button(isEditing ? "완료" : "편집") {
                        if isEditing {
                            Task { await saveProfile() }
                        } else {
                            startEditing()
                        }
                    }
                }
            }
            .alert("오류", isPresented: .constant(errorMessage != nil)) {
                Button("확인") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .task {
            await loadUser()
        }
    }
    
    @ViewBuilder
    private func userInfoView(_ user: User) -> some View {
        VStack(spacing: 16) {
            // 아바타
            AsyncImage(url: user.avatarURL.flatMap(URL.init)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.gray)
            }
            .frame(width: 100, height: 100)
            .clipShape(Circle())
            
            // 사용자 정보
            if isEditing {
                VStack(spacing: 12) {
                    TextField("이름", text: $editName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    TextField("이메일", text: $editEmail)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
                .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    Text(user.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(user.email)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func loadUser() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let service = await userService()
            user = try await service.getCurrentUser()
            
            let log = await logger()
            log.info("사용자 프로필 로딩 성공")
        } catch {
            errorMessage = error.localizedDescription
            
            let log = await logger()
            log.error("사용자 프로필 로딩 실패: \(error)")
        }
    }
    
    private func startEditing() {
        guard let user = user else { return }
        editName = user.name
        editEmail = user.email
        isEditing = true
    }
    
    private func saveProfile() async {
        guard !editName.isEmpty, !editEmail.isEmpty else {
            errorMessage = "이름과 이메일을 모두 입력해주세요"
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let service = await userService()
            try await service.updateProfile(name: editName, email: editEmail)
            
            // 성공 시 로컬 상태 업데이트
            user = User(id: user?.id ?? "", name: editName, email: editEmail, avatarURL: user?.avatarURL)
            isEditing = false
            
            let log = await logger()
            log.info("프로필 업데이트 성공")
        } catch {
            errorMessage = error.localizedDescription
            
            let log = await logger()
            log.error("프로필 업데이트 실패: \(error)")
        }
    }
}
```

**2.4 Preview 설정**
```swift
#Preview("기본 상태") {
    UserProfileView()
        .weaver(modules: PreviewWeaverContainer.previewModules(
            .register(LoggerKey.self, mockValue: PreviewLogger()),
            .register(UserServiceKey.self, mockValue: MockUserService())
        ))
}

#Preview("로딩 상태") {
    UserProfileView()
        .weaver(modules: PreviewWeaverContainer.previewModules(
            .register(LoggerKey.self, mockValue: PreviewLogger()),
            .register(UserServiceKey.self) { _ in
                SlowMockUserService() // 의도적으로 느린 서비스
            }
        ))
}

// 느린 Mock 서비스 (로딩 상태 테스트용)
final class SlowMockUserService: UserService {
    func getCurrentUser() async throws -> User? {
        try await Task.sleep(for: .seconds(3)) // 3초 지연
        return User.mock
    }
    
    func updateProfile(name: String, email: String) async throws {
        try await Task.sleep(for: .seconds(2)) // 2초 지연
    }
}
```

**2.5 모듈 업데이트**
```swift
struct UserModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(UserServiceKey.self, scope: .shared) { _ in
            APIUserService()
        }
    }
}

// App.swift 업데이트
@main
struct TutorialApp: App {
    init() {
        Task {
            try await Weaver.setup(modules: [
                LoggingModule(),
                UserModule()
            ])
        }
    }
    
    var body: some Scene {
        WindowGroup {
            UserProfileView() // ContentView 대신 UserProfileView 사용
        }
    }
}
```

#### 💡 핵심 포인트
- SwiftUI에서 `@Inject`는 `@State`와 함께 사용됩니다
- `task` modifier로 View 생명주기와 동기화합니다
- Preview에서는 Mock 객체를 사용하여 다양한 상태를 테스트합니다
- 에러 처리는 사용자 친화적으로 구현합니다

---

### 3단계: 모듈로 의존성 그룹화

#### 🎯 학습 목표
- 관련 의존성들을 모듈로 그룹화
- 모듈 간 의존성 관리
- 스코프의 올바른 사용법

#### 📝 실습: 네트워크 모듈 추가

**3.1 네트워크 클라이언트 구현**
```swift
protocol NetworkClient: Sendable {
    func get<T: Codable>(_ endpoint: String) async throws -> T
    func post<T: Codable, U: Codable>(_ endpoint: String, body: T) async throws -> U
}

final class URLSessionNetworkClient: NetworkClient {
    private let baseURL: String
    private let session: URLSession
    
    @Inject(LoggerKey.self) private var logger
    
    init(baseURL: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }
    
    func get<T: Codable>(_ endpoint: String) async throws -> T {
        let log = await logger()
        log.info("GET 요청: \(endpoint)")
        
        guard let url = URL(string: baseURL + endpoint) else {
            throw NetworkError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw NetworkError.serverError
        }
        
        log.info("GET 응답 성공: \(endpoint)")
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    func post<T: Codable, U: Codable>(_ endpoint: String, body: T) async throws -> U {
        let log = await logger()
        log.info("POST 요청: \(endpoint)")
        
        guard let url = URL(string: baseURL + endpoint) else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            throw NetworkError.serverError
        }
        
        log.info("POST 응답 성공: \(endpoint)")
        return try JSONDecoder().decode(U.self, from: data)
    }
}

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case serverError
    case noData
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "잘못된 URL입니다"
        case .serverError: return "서버 오류가 발생했습니다"
        case .noData: return "데이터가 없습니다"
        }
    }
}

struct NetworkClientKey: DependencyKey {
    typealias Value = NetworkClient
    static var defaultValue: NetworkClient {
        MockNetworkClient()
    }
}

// Mock 네트워크 클라이언트
final class MockNetworkClient: NetworkClient {
    func get<T: Codable>(_ endpoint: String) async throws -> T {
        // Mock 데이터 반환 로직
        if T.self == User.self {
            return User.mock as! T
        }
        throw NetworkError.noData
    }
    
    func post<T: Codable, U: Codable>(_ endpoint: String, body: T) async throws -> U {
        // Mock 응답 반환 로직
        if U.self == User.self {
            return User.mock as! U
        }
        throw NetworkError.noData
    }
}
```

**3.2 네트워크 모듈 생성**
```swift
struct NetworkModule: Module {
    let environment: AppEnvironment
    
    init(environment: AppEnvironment = .development) {
        self.environment = environment
    }
    
    func configure(_ builder: WeaverBuilder) async {
        // 환경별 베이스 URL 설정
        let baseURL = switch environment {
        case .production: "https://api.myapp.com"
        case .staging: "https://staging-api.myapp.com"
        case .development: "https://dev-api.myapp.com"
        }
        
        await builder.register(NetworkClientKey.self, scope: .shared) { _ in
            URLSessionNetworkClient(baseURL: baseURL)
        }
    }
}

enum AppEnvironment {
    case production
    case staging
    case development
}
```

**3.3 사용자 서비스 업데이트 (네트워크 의존성 추가)**
```swift
final class APIUserService: UserService {
    @Inject(LoggerKey.self) private var logger
    @Inject(NetworkClientKey.self) private var networkClient
    
    func getCurrentUser() async throws -> User? {
        let log = await logger()
        let client = await networkClient()
        
        log.info("사용자 정보 API 호출 시작")
        
        do {
            let user: User = try await client.get("/user/me")
            log.info("사용자 정보 API 호출 성공")
            return user
        } catch {
            log.error("사용자 정보 API 호출 실패: \(error)")
            throw error
        }
    }
    
    func updateProfile(name: String, email: String) async throws {
        let log = await logger()
        let client = await networkClient()
        
        log.info("프로필 업데이트 API 호출 시작")
        
        struct UpdateProfileRequest: Codable {
            let name: String
            let email: String
        }
        
        let request = UpdateProfileRequest(name: name, email: email)
        
        do {
            let _: User = try await client.post("/user/profile", body: request)
            log.info("프로필 업데이트 API 호출 성공")
        } catch {
            log.error("프로필 업데이트 API 호출 실패: \(error)")
            throw error
        }
    }
}
```

**3.4 모듈 통합**
```swift
// App.swift 최종 업데이트
@main
struct TutorialApp: App {
    init() {
        Task {
            try await Weaver.setup(modules: [
                LoggingModule(),           // 로깅 (다른 모듈들이 의존)
                NetworkModule(),           // 네트워크 (사용자 모듈이 의존)
                UserModule()               // 사용자 (네트워크와 로깅에 의존)
            ])
        }
    }
    
    var body: some Scene {
        WindowGroup {
            UserProfileView()
        }
    }
}
```

#### 💡 핵심 포인트
- 모듈은 관련 의존성들을 논리적으로 그룹화합니다
- 모듈 간 의존성 순서가 중요합니다 (로깅 → 네트워크 → 사용자)
- 환경별 설정을 모듈에서 처리할 수 있습니다
- `scope: .shared`는 앱 전체에서 하나의 인스턴스를 공유합니다

#### 💡 스코프 완전 가이드

Weaver는 5가지 직관적인 스코프를 제공합니다:

```swift
// 🔄 .shared: 앱 전체에서 하나의 인스턴스 공유 (싱글톤)
await builder.register(DatabaseKey.self, scope: .shared) { _ in
    CoreDataManager()
}

// 🧹 .weak: 약한 참조로 메모리 효율 관리
await builder.registerWeak(ImageCacheKey.self) { _ in
    ImageCache()
}

// 🚀 .startup: 앱 시작 시 즉시 로딩 (필수 서비스)
await builder.register(LoggerKey.self, scope: .startup) { _ in
    ProductionLogger()
}

// 💤 .whenNeeded: 실제 사용할 때만 로딩 (지연 로딩)
await builder.register(CameraServiceKey.self, scope: .whenNeeded) { _ in
    CameraService()
}

// 🔄 .transient: 매번 새로운 인스턴스 생성 (일회성)
await builder.register(DataProcessorKey.self, scope: .transient) { _ in
    DataProcessor()
}
```

**🎉 초급 레벨 완료!** 이제 Weaver DI의 기본 개념을 완전히 이해했습니다.

---

## 🟡 중급 레벨

### 4단계: 네트워크 서비스 구현

#### 🎯 학습 목표
- 실제 네트워크 통신 구현
- 에러 처리 및 재시도 로직
- 캐싱 시스템 구축

#### 📝 실습: 완전한 네트워크 스택

**4.1 고급 네트워크 클라이언트**
```swift
// 네트워크 설정
struct NetworkConfiguration {
    let baseURL: String
    let timeout: TimeInterval
    let retryCount: Int
    let cachePolicy: URLRequest.CachePolicy
    
    static let `default` = NetworkConfiguration(
        baseURL: "https://jsonplaceholder.typicode.com",
        timeout: 30.0,
        retryCount: 3,
        cachePolicy: .useProtocolCachePolicy
    )
}

// 고급 네트워크 클라이언트
final class AdvancedNetworkClient: NetworkClient {
    private let configuration: NetworkConfiguration
    private let session: URLSession
    
    @Inject(LoggerKey.self) private var logger
    
    init(configuration: NetworkConfiguration = .default) {
        self.configuration = configuration
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = configuration.timeout
        config.requestCachePolicy = configuration.cachePolicy
        
        self.session = URLSession(configuration: config)
    }
    
    func get<T: Codable>(_ endpoint: String) async throws -> T {
        return try await performRequest(endpoint: endpoint, method: "GET", body: nil as String?)
    }
    
    func post<T: Codable, U: Codable>(_ endpoint: String, body: T) async throws -> U {
        return try await performRequest(endpoint: endpoint, method: "POST", body: body)
    }
    
    private func performRequest<T: Codable, U: Codable>(
        endpoint: String,
        method: String,
        body: T?
    ) async throws -> U {
        let log = await logger()
        
        for attempt in 1...configuration.retryCount {
            do {
                log.info("\(method) 요청 시도 \(attempt)/\(configuration.retryCount): \(endpoint)")
                
                guard let url = URL(string: configuration.baseURL + endpoint) else {
                    throw NetworkError.invalidURL
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = method
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                if let body = body {
                    request.httpBody = try JSONEncoder().encode(body)
                }
                
                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.invalidResponse
                }
                
                switch httpResponse.statusCode {
                case 200...299:
                    log.info("\(method) 요청 성공: \(endpoint)")
                    return try JSONDecoder().decode(U.self, from: data)
                case 400...499:
                    throw NetworkError.clientError(httpResponse.statusCode)
                case 500...599:
                    throw NetworkError.serverError(httpResponse.statusCode)
                default:
                    throw NetworkError.unknownError(httpResponse.statusCode)
                }
                
            } catch {
                log.error("\(method) 요청 실패 (시도 \(attempt)): \(error)")
                
                // 마지막 시도가 아니면 재시도
                if attempt < configuration.retryCount {
                    let delay = TimeInterval(attempt * attempt) // 지수 백오프
                    try await Task.sleep(for: .seconds(delay))
                    continue
                } else {
                    throw error
                }
            }
        }
        
        throw NetworkError.maxRetriesExceeded
    }
}

// 확장된 네트워크 에러
enum NetworkError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case clientError(Int)
    case serverError(Int)
    case unknownError(Int)
    case maxRetriesExceeded
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "잘못된 URL입니다"
        case .invalidResponse:
            return "잘못된 응답입니다"
        case .clientError(let code):
            return "클라이언트 오류 (코드: \(code))"
        case .serverError(let code):
            return "서버 오류 (코드: \(code))"
        case .unknownError(let code):
            return "알 수 없는 오류 (코드: \(code))"
        case .maxRetriesExceeded:
            return "최대 재시도 횟수를 초과했습니다"
        case .decodingError(let error):
            return "데이터 파싱 오류: \(error.localizedDescription)"
        }
    }
}
```

이제 튜토리얼의 나머지 부분을 계속 작성하겠습니다.**4.2 캐싱
 시스템 구현**
```swift
// 캐시 정책
enum CachePolicy {
    case noCache
    case memoryOnly(maxSize: Int)
    case diskAndMemory(maxSize: Int, diskSize: Int)
    case custom(TimeInterval) // 커스텀 만료 시간
}

// 응답 캐시 매니저
final class ResponseCacheManager: Sendable {
    private let memoryCache = NSCache<NSString, NSData>()
    private let cachePolicy: CachePolicy
    
    @Inject(LoggerKey.self) private var logger
    
    init(policy: CachePolicy = .memoryOnly(maxSize: 100)) {
        self.cachePolicy = policy
        
        switch policy {
        case .memoryOnly(let maxSize), .diskAndMemory(let maxSize, _):
            memoryCache.countLimit = maxSize
        default:
            break
        }
    }
    
    func get<T: Codable>(_ key: String, type: T.Type) async -> T? {
        let log = await logger()
        
        guard case .noCache = cachePolicy else {
            return nil
        }
        
        if let data = memoryCache.object(forKey: key as NSString) {
            do {
                let object = try JSONDecoder().decode(T.self, from: data as Data)
                log.debug("캐시 히트: \(key)")
                return object
            } catch {
                log.error("캐시 디코딩 실패: \(error)")
                memoryCache.removeObject(forKey: key as NSString)
            }
        }
        
        log.debug("캐시 미스: \(key)")
        return nil
    }
    
    func set<T: Codable>(_ key: String, value: T) async {
        let log = await logger()
        
        guard case .noCache = cachePolicy else {
            return
        }
        
        do {
            let data = try JSONEncoder().encode(value)
            memoryCache.setObject(data as NSData, forKey: key as NSString)
            log.debug("캐시 저장: \(key)")
        } catch {
            log.error("캐시 인코딩 실패: \(error)")
        }
    }
    
    func clear() async {
        memoryCache.removeAllObjects()
        let log = await logger()
        log.info("캐시 전체 삭제")
    }
}

struct ResponseCacheManagerKey: DependencyKey {
    typealias Value = ResponseCacheManager
    static var defaultValue: ResponseCacheManager {
        ResponseCacheManager(policy: .memoryOnly(maxSize: 50))
    }
}
```

**4.3 캐시된 네트워크 서비스**
```swift
final class CachedNetworkService: Sendable {
    @Inject(NetworkClientKey.self) private var networkClient
    @Inject(ResponseCacheManagerKey.self) private var cacheManager
    @Inject(LoggerKey.self) private var logger
    
    func getCachedData<T: Codable>(
        _ endpoint: String,
        type: T.Type,
        cacheKey: String? = nil,
        forceRefresh: Bool = false
    ) async throws -> T {
        let key = cacheKey ?? "cached_\(endpoint)"
        let log = await logger()
        
        // 강제 새로고침이 아니면 캐시 확인
        if !forceRefresh {
            let cache = await cacheManager()
            if let cachedData = await cache.get(key, type: T.self) {
                log.info("캐시에서 데이터 반환: \(endpoint)")
                return cachedData
            }
        }
        
        // 캐시 미스 또는 강제 새로고침 시 네트워크 요청
        let client = await networkClient()
        let data: T = try await client.get(endpoint)
        
        // 응답을 캐시에 저장
        let cache = await cacheManager()
        await cache.set(key, value: data)
        
        log.info("네트워크에서 데이터 가져와서 캐시 저장: \(endpoint)")
        return data
    }
    
    func postWithCache<T: Codable, U: Codable>(
        _ endpoint: String,
        body: T,
        responseType: U.Type,
        invalidateCacheKeys: [String] = []
    ) async throws -> U {
        let client = await networkClient()
        let response: U = try await client.post(endpoint, body: body)
        
        // POST 성공 시 관련 캐시 무효화
        if !invalidateCacheKeys.isEmpty {
            let cache = await cacheManager()
            let log = await logger()
            
            for key in invalidateCacheKeys {
                // 실제 구현에서는 특정 키만 삭제하는 메서드 필요
                log.info("캐시 무효화: \(key)")
            }
        }
        
        return response
    }
}

struct CachedNetworkServiceKey: DependencyKey {
    typealias Value = CachedNetworkService
    static var defaultValue: CachedNetworkService { CachedNetworkService() }
}
```

**4.4 업데이트된 네트워크 모듈**
```swift
struct NetworkModule: Module {
    let environment: AppEnvironment
    let cachePolicy: CachePolicy
    
    init(environment: AppEnvironment = .development, cachePolicy: CachePolicy = .memoryOnly(maxSize: 100)) {
        self.environment = environment
        self.cachePolicy = cachePolicy
    }
    
    func configure(_ builder: WeaverBuilder) async {
        // 네트워크 설정
        let config = NetworkConfiguration(
            baseURL: environment.baseURL,
            timeout: 30.0,
            retryCount: environment == .production ? 3 : 1,
            cachePolicy: .useProtocolCachePolicy
        )
        
        // 기본 네트워크 클라이언트
        await builder.register(NetworkClientKey.self, scope: .shared) { _ in
            AdvancedNetworkClient(configuration: config)
        }
        
        // 캐시 매니저
        await builder.register(ResponseCacheManagerKey.self, scope: .shared) { _ in
            ResponseCacheManager(policy: cachePolicy)
        }
        
        // 캐시된 네트워크 서비스
        await builder.register(CachedNetworkServiceKey.self, scope: .shared) { _ in
            CachedNetworkService()
        }
    }
}

extension AppEnvironment {
    var baseURL: String {
        switch self {
        case .production: return "https://api.myapp.com"
        case .staging: return "https://staging-api.myapp.com"
        case .development: return "https://jsonplaceholder.typicode.com"
        }
    }
}
```

**4.5 사용자 서비스 최종 업데이트**
```swift
final class APIUserService: UserService {
    @Inject(CachedNetworkServiceKey.self) private var cachedNetworkService
    @Inject(LoggerKey.self) private var logger
    
    func getCurrentUser() async throws -> User? {
        let log = await logger()
        log.info("사용자 정보 요청 시작")
        
        do {
            let service = await cachedNetworkService()
            // JSONPlaceholder API 사용 (실제 앱에서는 /user/me)
            let user = try await service.getCachedData("/users/1", type: User.self)
            
            log.info("사용자 정보 요청 성공")
            return user
        } catch {
            log.error("사용자 정보 요청 실패: \(error)")
            throw error
        }
    }
    
    func updateProfile(name: String, email: String) async throws {
        let log = await logger()
        log.info("프로필 업데이트 요청 시작")
        
        struct UpdateRequest: Codable {
            let name: String
            let email: String
        }
        
        do {
            let service = await cachedNetworkService()
            let request = UpdateRequest(name: name, email: email)
            
            // 프로필 업데이트 후 사용자 정보 캐시 무효화
            let _: User = try await service.postWithCache(
                "/users/1",
                body: request,
                responseType: User.self,
                invalidateCacheKeys: ["cached_/users/1"]
            )
            
            log.info("프로필 업데이트 성공")
        } catch {
            log.error("프로필 업데이트 실패: \(error)")
            throw error
        }
    }
}
```

#### 💡 핵심 포인트
- 네트워크 클라이언트는 재시도 로직과 지수 백오프를 구현합니다
- 캐싱 시스템으로 성능을 크게 향상시킬 수 있습니다
- POST 요청 후 관련 캐시를 무효화하여 데이터 일관성을 유지합니다
- 환경별로 다른 설정을 사용할 수 있습니다

---

### 5단계: 에러 처리와 안전성

#### 🎯 학습 목표
- 구조화된 에러 처리 시스템
- 사용자 친화적 에러 메시지
- 에러 복구 전략

#### 📝 실습: 완전한 에러 처리 시스템

**5.1 앱 전체 에러 타입 정의**
```swift
// 앱 레벨 에러
enum AppError: Error, LocalizedError {
    case network(NetworkError)
    case user(UserError)
    case cache(CacheError)
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .network(let error):
            return "네트워크 오류: \(error.localizedDescription)"
        case .user(let error):
            return "사용자 오류: \(error.localizedDescription)"
        case .cache(let error):
            return "캐시 오류: \(error.localizedDescription)"
        case .unknown(let error):
            return "알 수 없는 오류: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .network(.maxRetriesExceeded):
            return "네트워크 연결을 확인하고 다시 시도해주세요."
        case .network(.serverError):
            return "잠시 후 다시 시도해주세요."
        case .user(.invalidInput):
            return "입력 정보를 확인해주세요."
        default:
            return "앱을 다시 시작해보세요."
        }
    }
}

// 사용자 관련 에러
enum UserError: Error, LocalizedError {
    case notFound
    case invalidInput
    case unauthorized
    case profileUpdateFailed
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "사용자를 찾을 수 없습니다"
        case .invalidInput:
            return "입력 정보가 올바르지 않습니다"
        case .unauthorized:
            return "인증이 필요합니다"
        case .profileUpdateFailed:
            return "프로필 업데이트에 실패했습니다"
        }
    }
}

// 캐시 관련 에러
enum CacheError: Error, LocalizedError {
    case encodingFailed
    case decodingFailed
    case storageError
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "데이터 저장 중 오류가 발생했습니다"
        case .decodingFailed:
            return "데이터 읽기 중 오류가 발생했습니다"
        case .storageError:
            return "저장소 오류가 발생했습니다"
        }
    }
}
```

**5.2 에러 처리 서비스**
```swift
protocol ErrorHandlingService: Sendable {
    func handleError(_ error: Error) async -> AppError
    func shouldRetry(_ error: AppError) -> Bool
    func getRetryDelay(_ error: AppError, attempt: Int) -> TimeInterval
}

final class DefaultErrorHandlingService: ErrorHandlingService {
    @Inject(LoggerKey.self) private var logger
    
    func handleError(_ error: Error) async -> AppError {
        let log = await logger()
        
        let appError: AppError
        
        switch error {
        case let networkError as NetworkError:
            appError = .network(networkError)
        case let userError as UserError:
            appError = .user(userError)
        case let cacheError as CacheError:
            appError = .cache(cacheError)
        default:
            appError = .unknown(error)
        }
        
        log.error("에러 처리: \(appError.localizedDescription)")
        return appError
    }
    
    func shouldRetry(_ error: AppError) -> Bool {
        switch error {
        case .network(.serverError), .network(.unknownError):
            return true
        case .cache(.storageError):
            return true
        default:
            return false
        }
    }
    
    func getRetryDelay(_ error: AppError, attempt: Int) -> TimeInterval {
        // 지수 백오프: 1초, 2초, 4초, 8초...
        return TimeInterval(min(pow(2.0, Double(attempt)), 30.0))
    }
}

struct ErrorHandlingServiceKey: DependencyKey {
    typealias Value = ErrorHandlingService
    static var defaultValue: ErrorHandlingService { DefaultErrorHandlingService() }
}
```

**5.3 에러 복구 가능한 사용자 서비스**
```swift
final class ResilientUserService: UserService {
    @Inject(CachedNetworkServiceKey.self) private var cachedNetworkService
    @Inject(ErrorHandlingServiceKey.self) private var errorHandlingService
    @Inject(LoggerKey.self) private var logger
    
    private let maxRetryAttempts = 3
    
    func getCurrentUser() async throws -> User? {
        return try await performWithRetry { [weak self] in
            guard let self = self else { throw UserError.notFound }
            
            let service = await self.cachedNetworkService()
            return try await service.getCachedData("/users/1", type: User.self)
        }
    }
    
    func updateProfile(name: String, email: String) async throws {
        // 입력 검증
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UserError.invalidInput
        }
        
        guard email.contains("@") && email.contains(".") else {
            throw UserError.invalidInput
        }
        
        struct UpdateRequest: Codable {
            let name: String
            let email: String
        }
        
        let request = UpdateRequest(name: name, email: email)
        
        let _: User = try await performWithRetry { [weak self] in
            guard let self = self else { throw UserError.profileUpdateFailed }
            
            let service = await self.cachedNetworkService()
            return try await service.postWithCache(
                "/users/1",
                body: request,
                responseType: User.self,
                invalidateCacheKeys: ["cached_/users/1"]
            )
        }
    }
    
    private func performWithRetry<T>(
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let log = await logger()
        let errorHandler = await errorHandlingService()
        
        for attempt in 1...maxRetryAttempts {
            do {
                return try await operation()
            } catch {
                let appError = await errorHandler.handleError(error)
                
                // 마지막 시도이거나 재시도 불가능한 에러면 던지기
                if attempt == maxRetryAttempts || !errorHandler.shouldRetry(appError) {
                    log.error("최종 실패 (시도 \(attempt)/\(maxRetryAttempts)): \(appError)")
                    throw appError
                }
                
                // 재시도 대기
                let delay = errorHandler.getRetryDelay(appError, attempt: attempt)
                log.info("재시도 대기 \(delay)초 (시도 \(attempt)/\(maxRetryAttempts))")
                
                try await Task.sleep(for: .seconds(delay))
            }
        }
        
        throw UserError.profileUpdateFailed
    }
}
```

**5.4 에러 표시 UI 컴포넌트**
```swift
// 에러 상태를 관리하는 ObservableObject
@MainActor
class ErrorViewModel: ObservableObject {
    @Published var currentError: AppError?
    @Published var isShowingError = false
    
    @Inject(ErrorHandlingServiceKey.self) private var errorHandlingService
    @Inject(LoggerKey.self) private var logger
    
    func handleError(_ error: Error) async {
        let handler = await errorHandlingService()
        let appError = await handler.handleError(error)
        
        await MainActor.run {
            self.currentError = appError
            self.isShowingError = true
        }
    }
    
    func dismissError() {
        currentError = nil
        isShowingError = false
    }
    
    func canRetry() -> Bool {
        guard let error = currentError else { return false }
        
        Task {
            let handler = await errorHandlingService()
            return handler.shouldRetry(error)
        }
        
        return false
    }
}

// 에러 표시 View
struct ErrorView: View {
    let error: AppError
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("오류가 발생했습니다")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(error.localizedDescription)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            
            HStack(spacing: 12) {
                Button("확인") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                
                if let onRetry = onRetry {
                    Button("다시 시도") {
                        onRetry()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
}
```

**5.5 에러 처리가 통합된 사용자 프로필 View**
```swift
struct ResilientUserProfileView: View {
    @StateObject private var errorViewModel = ErrorViewModel()
    @Inject(UserServiceKey.self) private var userService
    
    @State private var user: User?
    @State private var isLoading = false
    @State private var isEditing = false
    @State private var editName = ""
    @State private var editEmail = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 20) {
                    if isLoading {
                        ProgressView("로딩 중...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let user = user {
                        userInfoView(user)
                    } else {
                        emptyStateView()
                    }
                }
                .navigationTitle("프로필")
                .toolbar {
                    if user != nil && !isLoading {
                        Button(isEditing ? "완료" : "편집") {
                            if isEditing {
                                Task { await saveProfile() }
                            } else {
                                startEditing()
                            }
                        }
                    }
                }
                
                // 에러 오버레이
                if errorViewModel.isShowingError {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            errorViewModel.dismissError()
                        }
                    
                    if let error = errorViewModel.currentError {
                        ErrorView(
                            error: error,
                            onRetry: errorViewModel.canRetry() ? {
                                errorViewModel.dismissError()
                                Task { await loadUser() }
                            } : nil,
                            onDismiss: {
                                errorViewModel.dismissError()
                            }
                        )
                        .padding()
                    }
                }
            }
        }
        .task {
            await loadUser()
        }
    }
    
    @ViewBuilder
    private func userInfoView(_ user: User) -> some View {
        VStack(spacing: 16) {
            // 아바타
            AsyncImage(url: user.avatarURL.flatMap(URL.init)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.gray)
            }
            .frame(width: 100, height: 100)
            .clipShape(Circle())
            
            // 사용자 정보
            if isEditing {
                VStack(spacing: 12) {
                    TextField("이름", text: $editName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    TextField("이메일", text: $editEmail)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
                .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    Text(user.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(user.email)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    @ViewBuilder
    private func emptyStateView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "person.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("사용자 정보를 불러올 수 없습니다")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Button("다시 시도") {
                Task { await loadUser() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private func loadUser() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let service = await userService()
            user = try await service.getCurrentUser()
        } catch {
            await errorViewModel.handleError(error)
        }
    }
    
    private func startEditing() {
        guard let user = user else { return }
        editName = user.name
        editEmail = user.email
        isEditing = true
    }
    
    private func saveProfile() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let service = await userService()
            try await service.updateProfile(name: editName, email: editEmail)
            
            // 성공 시 로컬 상태 업데이트
            user = User(id: user?.id ?? "", name: editName, email: editEmail, avatarURL: user?.avatarURL)
            isEditing = false
        } catch {
            await errorViewModel.handleError(error)
        }
    }
}
```

**5.6 에러 처리 모듈**
```swift
struct ErrorHandlingModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(ErrorHandlingServiceKey.self, scope: .shared) { _ in
            DefaultErrorHandlingService()
        }
    }
}

// 사용자 모듈 업데이트
struct UserModule: Module {
    func configure(_ builder: WeaverBuilder) async {
        await builder.register(UserServiceKey.self, scope: .shared) { _ in
            ResilientUserService() // 에러 복구 가능한 서비스로 변경
        }
    }
}
```

#### 💡 핵심 포인트
- 구조화된 에러 타입으로 명확한 에러 처리
- 자동 재시도 로직으로 일시적 오류 해결
- 사용자 친화적인 에러 메시지와 복구 제안
- 에러 상태를 별도 ViewModel로 관리하여 재사용성 향상

---

### 6단계: 테스트 작성하기

#### 🎯 학습 목표
- 의존성 주입을 활용한 테스트 작성
- Mock 객체 생성 및 사용
- 격리된 테스트 환경 구축

#### 📝 실습: 완전한 테스트 스위트

**6.1 테스트용 Mock 서비스들**
```swift
// Tests/TutorialTests/Mocks/MockServices.swift
import XCTest
@testable import Tutorial
import Weaver

// Mock 로거
final class MockLogger: Logger {
    private(set) var infoMessages: [String] = []
    private(set) var errorMessages: [String] = []
    private(set) var debugMessages: [String] = []
    
    func info(_ message: String) {
        infoMessages.append(message)
    }
    
    func error(_ message: String) {
        errorMessages.append(message)
    }
    
    func debug(_ message: String) {
        debugMessages.append(message)
    }
    
    func reset() {
        infoMessages.removeAll()
        errorMessages.removeAll()
        debugMessages.removeAll()
    }
}

// Mock 네트워크 클라이언트
final class MockNetworkClient: NetworkClient {
    var shouldFail = false
    var failureError: Error = NetworkError.serverError(500)
    var getResponses: [String: Any] = [:]
    var postResponses: [String: Any] = [:]
    
    private(set) var getRequests: [String] = []
    private(set) var postRequests: [(endpoint: String, body: Any)] = []
    
    func get<T: Codable>(_ endpoint: String) async throws -> T {
        getRequests.append(endpoint)
        
        if shouldFail {
            throw failureError
        }
        
        guard let response = getResponses[endpoint] as? T else {
            throw NetworkError.invalidResponse
        }
        
        return response
    }
    
    func post<T: Codable, U: Codable>(_ endpoint: String, body: T) async throws -> U {
        postRequests.append((endpoint, body))
        
        if shouldFail {
            throw failureError
        }
        
        guard let response = postResponses[endpoint] as? U else {
            throw NetworkError.invalidResponse
        }
        
        return response
    }
    
    func reset() {
        shouldFail = false
        getResponses.removeAll()
        postResponses.removeAll()
        getRequests.removeAll()
        postRequests.removeAll()
    }
}

// Mock 캐시 매니저
final class MockCacheManager: ResponseCacheManager {
    private var storage: [String: Any] = [:]
    private(set) var getRequests: [String] = []
    private(set) var setRequests: [(key: String, value: Any)] = []
    
    override func get<T: Codable>(_ key: String, type: T.Type) async -> T? {
        getRequests.append(key)
        return storage[key] as? T
    }
    
    override func set<T: Codable>(_ key: String, value: T) async {
        setRequests.append((key, value))
        storage[key] = value
    }
    
    override func clear() async {
        storage.removeAll()
    }
    
    func reset() {
        storage.removeAll()
        getRequests.removeAll()
        setRequests.removeAll()
    }
}
```

**6.2 테스트 헬퍼 및 베이스 클래스**
```swift
// Tests/TutorialTests/TestHelpers/TestHelpers.swift
import XCTest
@testable import Tutorial
import Weaver

class WeaverTestCase: XCTestCase {
    var testContainer: WeaverContainer!
    var mockLogger: MockLogger!
    var mockNetworkClient: MockNetworkClient!
    var mockCacheManager: MockCacheManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Mock 객체들 생성
        mockLogger = MockLogger()
        mockNetworkClient = MockNetworkClient()
        mockCacheManager = MockCacheManager()
        
        // 테스트용 컨테이너 생성
        testContainer = await WeaverContainer.builder()
            .override(LoggerKey.self) { _ in self.mockLogger }
            .override(NetworkClientKey.self) { _ in self.mockNetworkClient }
            .override(ResponseCacheManagerKey.self) { _ in self.mockCacheManager }
            .override(ErrorHandlingServiceKey.self) { _ in DefaultErrorHandlingService() }
            .build()
        
        // 전역 상태 초기화
        await Weaver.resetForTesting()
    }
    
    override func tearDown() async throws {
        // Mock 객체들 정리
        mockLogger?.reset()
        mockNetworkClient?.reset()
        mockCacheManager?.reset()
        
        testContainer = nil
        mockLogger = nil
        mockNetworkClient = nil
        mockCacheManager = nil
        
        await Weaver.resetForTesting()
        try await super.tearDown()
    }
    
    /// 테스트 컨테이너 스코프에서 작업 실행
    func withTestScope<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        return try await Weaver.withScope(testContainer) {
            try await operation()
        }
    }
}

// 테스트 데이터 팩토리
struct TestDataFactory {
    static let sampleUser = User(
        id: "test-user-1",
        name: "테스트 사용자",
        email: "test@example.com",
        avatarURL: "https://example.com/avatar.jpg"
    )
    
    static let updatedUser = User(
        id: "test-user-1",
        name: "업데이트된 사용자",
        email: "updated@example.com",
        avatarURL: "https://example.com/avatar.jpg"
    )
    
    static func createUsers(count: Int) -> [User] {
        return (1...count).map { index in
            User(
                id: "test-user-\(index)",
                name: "테스트 사용자 \(index)",
                email: "test\(index)@example.com",
                avatarURL: nil
            )
        }
    }
}
```

**6.3 사용자 서비스 테스트**
```swift
// Tests/TutorialTests/Services/UserServiceTests.swift
import XCTest
@testable import Tutorial
import Weaver

final class UserServiceTests: WeaverTestCase {
    
    func testGetCurrentUser_Success() async throws {
        // Given
        let expectedUser = TestDataFactory.sampleUser
        mockNetworkClient.getResponses["/users/1"] = expectedUser
        
        // When
        let result = try await withTestScope {
            let service = ResilientUserService()
            return try await service.getCurrentUser()
        }
        
        // Then
        XCTAssertEqual(result?.id, expectedUser.id)
        XCTAssertEqual(result?.name, expectedUser.name)
        XCTAssertEqual(result?.email, expectedUser.email)
        
        // 네트워크 요청이 올바르게 호출되었는지 확인
        XCTAssertEqual(mockNetworkClient.getRequests.count, 1)
        XCTAssertEqual(mockNetworkClient.getRequests.first, "/users/1")
        
        // 로그가 올바르게 기록되었는지 확인
        XCTAssertTrue(mockLogger.infoMessages.contains { $0.contains("사용자 정보 요청 시작") })
        XCTAssertTrue(mockLogger.infoMessages.contains { $0.contains("사용자 정보 요청 성공") })
    }
    
    func testGetCurrentUser_NetworkError_WithRetry() async throws {
        // Given
        mockNetworkClient.shouldFail = true
        mockNetworkClient.failureError = NetworkError.serverError(500)
        
        // When & Then
        await withTestScope {
            let service = ResilientUserService()
            
            do {
                _ = try await service.getCurrentUser()
                XCTFail("에러가 발생해야 합니다")
            } catch {
                // 에러가 AppError로 래핑되었는지 확인
                XCTAssertTrue(error is AppError)
                
                if case .network(let networkError) = error as? AppError {
                    XCTAssertTrue(networkError is NetworkError)
                } else {
                    XCTFail("NetworkError로 래핑되어야 합니다")
                }
            }
        }
        
        // 재시도가 3번 수행되었는지 확인
        XCTAssertEqual(mockNetworkClient.getRequests.count, 3)
        
        // 에러 로그가 기록되었는지 확인
        XCTAssertTrue(mockLogger.errorMessages.contains { $0.contains("최종 실패") })
    }
    
    func testGetCurrentUser_CacheHit() async throws {
        // Given
        let expectedUser = TestDataFactory.sampleUser
        let cacheKey = "cached_/users/1"
        
        // 캐시에 데이터 미리 저장
        await mockCacheManager.set(cacheKey, value: expectedUser)
        
        // When
        let result = try await withTestScope {
            let service = ResilientUserService()
            return try await service.getCurrentUser()
        }
        
        // Then
        XCTAssertEqual(result?.id, expectedUser.id)
        
        // 네트워크 요청이 호출되지 않았는지 확인 (캐시 히트)
        XCTAssertEqual(mockNetworkClient.getRequests.count, 0)
        
        // 캐시 조회가 수행되었는지 확인
        XCTAssertTrue(mockCacheManager.getRequests.contains(cacheKey))
    }
    
    func testUpdateProfile_Success() async throws {
        // Given
        let updatedUser = TestDataFactory.updatedUser
        mockNetworkClient.postResponses["/users/1"] = updatedUser
        
        // When
        try await withTestScope {
            let service = ResilientUserService()
            try await service.updateProfile(name: "업데이트된 사용자", email: "updated@example.com")
        }
        
        // Then
        XCTAssertEqual(mockNetworkClient.postRequests.count, 1)
        
        let postRequest = mockNetworkClient.postRequests.first
        XCTAssertEqual(postRequest?.endpoint, "/users/1")
        
        // POST 요청 바디 확인
        if let requestBody = postRequest?.body as? [String: String] {
            XCTAssertEqual(requestBody["name"], "업데이트된 사용자")
            XCTAssertEqual(requestBody["email"], "updated@example.com")
        }
        
        // 성공 로그 확인
        XCTAssertTrue(mockLogger.infoMessages.contains { $0.contains("프로필 업데이트 성공") })
    }
    
    func testUpdateProfile_InvalidInput() async throws {
        // Given & When & Then
        await withTestScope {
            let service = ResilientUserService()
            
            // 빈 이름으로 테스트
            do {
                try await service.updateProfile(name: "", email: "test@example.com")
                XCTFail("에러가 발생해야 합니다")
            } catch {
                XCTAssertTrue(error is UserError)
                if case .invalidInput = error as? UserError {
                    // 올바른 에러 타입
                } else {
                    XCTFail("UserError.invalidInput이어야 합니다")
                }
            }
            
            // 잘못된 이메일로 테스트
            do {
                try await service.updateProfile(name: "테스트", email: "invalid-email")
                XCTFail("에러가 발생해야 합니다")
            } catch {
                XCTAssertTrue(error is UserError)
            }
        }
        
        // 네트워크 요청이 호출되지 않았는지 확인
        XCTAssertEqual(mockNetworkClient.postRequests.count, 0)
    }
}
```

**6.4 캐시된 네트워크 서비스 테스트**
```swift
// Tests/TutorialTests/Services/CachedNetworkServiceTests.swift
import XCTest
@testable import Tutorial
import Weaver

final class CachedNetworkServiceTests: WeaverTestCase {
    
    func testGetCachedData_CacheMiss() async throws {
        // Given
        let expectedUser = TestDataFactory.sampleUser
        mockNetworkClient.getResponses["/users/1"] = expectedUser
        
        // When
        let result: User = try await withTestScope {
            let service = CachedNetworkService()
            return try await service.getCachedData("/users/1", type: User.self)
        }
        
        // Then
        XCTAssertEqual(result.id, expectedUser.id)
        
        // 네트워크 요청이 호출되었는지 확인
        XCTAssertEqual(mockNetworkClient.getRequests.count, 1)
        
        // 캐시에 저장되었는지 확인
        XCTAssertEqual(mockCacheManager.setRequests.count, 1)
        XCTAssertEqual(mockCacheManager.setRequests.first?.key, "cached_/users/1")
    }
    
    func testGetCachedData_CacheHit() async throws {
        // Given
        let cachedUser = TestDataFactory.sampleUser
        let cacheKey = "cached_/users/1"
        await mockCacheManager.set(cacheKey, value: cachedUser)
        
        // When
        let result: User = try await withTestScope {
            let service = CachedNetworkService()
            return try await service.getCachedData("/users/1", type: User.self)
        }
        
        // Then
        XCTAssertEqual(result.id, cachedUser.id)
        
        // 네트워크 요청이 호출되지 않았는지 확인
        XCTAssertEqual(mockNetworkClient.getRequests.count, 0)
        
        // 캐시 조회가 수행되었는지 확인
        XCTAssertTrue(mockCacheManager.getRequests.contains(cacheKey))
    }
    
    func testGetCachedData_ForceRefresh() async throws {
        // Given
        let cachedUser = TestDataFactory.sampleUser
        let freshUser = TestDataFactory.updatedUser
        let cacheKey = "cached_/users/1"
        
        await mockCacheManager.set(cacheKey, value: cachedUser)
        mockNetworkClient.getResponses["/users/1"] = freshUser
        
        // When
        let result: User = try await withTestScope {
            let service = CachedNetworkService()
            return try await service.getCachedData("/users/1", type: User.self, forceRefresh: true)
        }
        
        // Then
        XCTAssertEqual(result.id, freshUser.id)
        XCTAssertEqual(result.name, freshUser.name)
        
        // 강제 새로고침이므로 네트워크 요청이 호출되어야 함
        XCTAssertEqual(mockNetworkClient.getRequests.count, 1)
        
        // 새로운 데이터가 캐시에 저장되었는지 확인
        XCTAssertEqual(mockCacheManager.setRequests.count, 1)
    }
    
    func testPostWithCache_InvalidatesCacheKeys() async throws {
        // Given
        let request = ["name": "테스트", "email": "test@example.com"]
        let response = TestDataFactory.updatedUser
        mockNetworkClient.postResponses["/users/1"] = response
        
        // When
        let result: User = try await withTestScope {
            let service = CachedNetworkService()
            return try await service.postWithCache(
                "/users/1",
                body: request,
                responseType: User.self,
                invalidateCacheKeys: ["cached_/users/1", "cached_/users/list"]
            )
        }
        
        // Then
        XCTAssertEqual(result.id, response.id)
        
        // POST 요청이 호출되었는지 확인
        XCTAssertEqual(mockNetworkClient.postRequests.count, 1)
        
        // 캐시 무효화 로그가 기록되었는지 확인
        XCTAssertTrue(mockLogger.infoMessages.contains { $0.contains("캐시 무효화") })
    }
}
```

**6.5 에러 처리 서비스 테스트**
```swift
// Tests/TutorialTests/Services/ErrorHandlingServiceTests.swift
import XCTest
@testable import Tutorial
import Weaver

final class ErrorHandlingServiceTests: WeaverTestCase {
    
    func testHandleError_NetworkError() async throws {
        // Given
        let networkError = NetworkError.serverError(500)
        
        // When
        let result = await withTestScope {
            let service = DefaultErrorHandlingService()
            return await service.handleError(networkError)
        }
        
        // Then
        if case .network(let wrappedError) = result {
            XCTAssertTrue(wrappedError is NetworkError)
        } else {
            XCTFail("NetworkError로 래핑되어야 합니다")
        }
        
        // 에러 로그가 기록되었는지 확인
        XCTAssertTrue(mockLogger.errorMessages.contains { $0.contains("에러 처리") })
    }
    
    func testShouldRetry_RetryableErrors() async throws {
        // Given
        let service = DefaultErrorHandlingService()
        
        // When & Then
        await withTestScope {
            // 서버 에러는 재시도 가능
            let serverError = AppError.network(.serverError(500))
            XCTAssertTrue(service.shouldRetry(serverError))
            
            // 클라이언트 에러는 재시도 불가능
            let clientError = AppError.network(.clientError(400))
            XCTAssertFalse(service.shouldRetry(clientError))
            
            // 사용자 에러는 재시도 불가능
            let userError = AppError.user(.invalidInput)
            XCTAssertFalse(service.shouldRetry(userError))
        }
    }
    
    func testGetRetryDelay_ExponentialBackoff() async throws {
        // Given
        let service = DefaultErrorHandlingService()
        let error = AppError.network(.serverError(500))
        
        // When & Then
        await withTestScope {
            // 지수 백오프 확인
            XCTAssertEqual(service.getRetryDelay(error, attempt: 1), 2.0)  // 2^1
            XCTAssertEqual(service.getRetryDelay(error, attempt: 2), 4.0)  // 2^2
            XCTAssertEqual(service.getRetryDelay(error, attempt: 3), 8.0)  // 2^3
            XCTAssertEqual(service.getRetryDelay(error, attempt: 4), 16.0) // 2^4
            
            // 최대 30초 제한 확인
            XCTAssertEqual(service.getRetryDelay(error, attempt: 10), 30.0)
        }
    }
}
```

**6.6 통합 테스트**
```swift
// Tests/TutorialTests/Integration/UserProfileIntegrationTests.swift
import XCTest
@testable import Tutorial
import Weaver

final class UserProfileIntegrationTests: WeaverTestCase {
    
    func testUserProfileFlow_SuccessPath() async throws {
        // Given
        let initialUser = TestDataFactory.sampleUser
        let updatedUser = TestDataFactory.updatedUser
        
        mockNetworkClient.getResponses["/users/1"] = initialUser
        mockNetworkClient.postResponses["/users/1"] = updatedUser
        
        // When & Then - 사용자 정보 로딩
        let loadedUser = try await withTestScope {
            let service = ResilientUserService()
            return try await service.getCurrentUser()
        }
        
        XCTAssertEqual(loadedUser?.id, initialUser.id)
        XCTAssertEqual(loadedUser?.name, initialUser.name)
        
        // When & Then - 프로필 업데이트
        try await withTestScope {
            let service = ResilientUserService()
            try await service.updateProfile(name: updatedUser.name, email: updatedUser.email)
        }
        
        // 전체 플로우 검증
        XCTAssertEqual(mockNetworkClient.getRequests.count, 1)
        XCTAssertEqual(mockNetworkClient.postRequests.count, 1)
        
        // 캐시 동작 검증
        XCTAssertEqual(mockCacheManager.setRequests.count, 1) // GET 응답 캐시
        
        // 로그 검증
        XCTAssertTrue(mockLogger.infoMessages.contains { $0.contains("사용자 정보 요청 성공") })
        XCTAssertTrue(mockLogger.infoMessages.contains { $0.contains("프로필 업데이트 성공") })
    }
    
    func testUserProfileFlow_NetworkFailureRecovery() async throws {
        // Given
        let user = TestDataFactory.sampleUser
        
        // 처음 2번은 실패, 3번째는 성공
        var callCount = 0
        mockNetworkClient.shouldFail = true
        mockNetworkClient.failureError = NetworkError.serverError(500)
        
        // 3번째 호출에서 성공하도록 설정
        let originalGet = mockNetworkClient.get
        mockNetworkClient.get = { endpoint in
            callCount += 1
            if callCount >= 3 {
                self.mockNetworkClient.shouldFail = false
                self.mockNetworkClient.getResponses[endpoint] = user
            }
            return try await originalGet(endpoint)
        }
        
        // When
        let result = try await withTestScope {
            let service = ResilientUserService()
            return try await service.getCurrentUser()
        }
        
        // Then
        XCTAssertEqual(result?.id, user.id)
        XCTAssertEqual(mockNetworkClient.getRequests.count, 3) // 3번 시도
        
        // 재시도 로그 확인
        XCTAssertTrue(mockLogger.infoMessages.contains { $0.contains("재시도 대기") })
        XCTAssertTrue(mockLogger.infoMessages.contains { $0.contains("사용자 정보 요청 성공") })
    }
}
```

**6.7 성능 테스트**
```swift
// Tests/TutorialTests/Performance/PerformanceTests.swift
import XCTest
@testable import Tutorial
import Weaver

final class PerformanceTests: WeaverTestCase {
    
    func testUserServicePerformance() async throws {
        // Given
        let user = TestDataFactory.sampleUser
        mockNetworkClient.getResponses["/users/1"] = user
        
        // When & Then
        measure {
            let expectation = XCTestExpectation(description: "User service performance")
            
            Task {
                try await self.withTestScope {
                    let service = ResilientUserService()
                    _ = try await service.getCurrentUser()
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 1.0)
        }
    }
    
    func testCachePerformance() async throws {
        // Given
        let users = TestDataFactory.createUsers(count: 100)
        
        // 캐시에 100개 사용자 저장
        for (index, user) in users.enumerated() {
            await mockCacheManager.set("user_\(index)", value: user)
        }
        
        // When & Then - 캐시 조회 성능 측정
        measure {
            let expectation = XCTestExpectation(description: "Cache performance")
            
            Task {
                for index in 0..<100 {
                    _ = await self.mockCacheManager.get("user_\(index)", type: User.self)
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 1.0)
        }
    }
}
```

#### 💡 핵심 포인트
- Mock 객체를 사용하여 외부 의존성을 제거합니다
- `WeaverTestCase` 베이스 클래스로 테스트 설정을 표준화합니다
- 단위 테스트, 통합 테스트, 성능 테스트를 모두 작성합니다
- 테스트에서도 DI 컨테이너를 사용하여 일관성을 유지합니다

**🎉 중급 레벨 완료!** 이제 실제 프로덕션 앱에서 사용할 수 있는 수준의 Weaver DI 시스템을 구축했습니다.

---

## 🔴 고급 레벨

고급 레벨에서는 실제 프로덕션 앱에서 필요한 복잡한 패턴들을 다룹니다. 인증 시스템, 성능 최적화, A/B 테스트 등 고급 주제들을 학습합니다.

### 7단계: 인증 시스템 구현

#### 🎯 학습 목표
- JWT 토큰 기반 인증 시스템
- 자동 토큰 갱신 메커니즘
- 키체인을 활용한 보안 저장소

#### 📝 실습: 완전한 인증 시스템

**7.1 인증 토큰 모델**
```swift
// Models/AuthToken.swift
import Foundation

struct AuthToken: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let scope: String?
    
    private let issuedAt: Date
    
    init(accessToken: String, refreshToken: String, tokenType: String = "Bearer", expiresIn: Int, scope: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.scope = scope
        self.issuedAt = Date()
    }
    
    var expiresAt: Date {
        issuedAt.addingTimeInterval(TimeInterval(expiresIn))
    }
    
    var isExpired: Bool {
        Date() >= expiresAt
    }
    
    var willExpireSoon: Bool {
        // 만료 5분 전을 "곧 만료"로 간주
        Date().addingTimeInterval(300) >= expiresAt
    }
    
    var authorizationHeader: String {
        "\(tokenType) \(accessToken)"
    }
}

// 로그인 요청/응답 모델
struct LoginRequest: Codable {
    let email: String
    let password: String
    let deviceId: String
    let deviceName: String
}

struct LoginResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let user: User
}

struct RefreshTokenRequest: Codable {
    let refreshToken: String
}

struct RefreshTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
}
```

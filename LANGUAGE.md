---
id: "swift-lang-guide"
category: "language"
type: "prescriptive-guide"
tags: ['swift', 'ios', 'mobile', 'production', 'swift6', 'concurrency', 'sendable']
priority: "medium"
last_updated: "2025-08-06"
version: "1.1"
---

# Swift 개발 가이드라인 (Production-Grade)

## SECTION 0: 문서 범위 및 지침

**목적**: 이 문서는 Swift 언어 사용을 위한 프로덕션 등급 개발 표준을 정의합니다.

**의무**: 이 규칙들은 세계적 수준의 Swift 코드 작성을 위한 필수 요건입니다. Swift 언어 사용에 관한 최종 권한을 가집니다.

---

## SECTION 1: 프로젝트 구조 및 품질 강제

### RULE_1_1: 자동화된 코드 품질

모든 코드는 자동 검증되어야 합니다:

**COMMAND_SET:**
```bash
swift-format --configuration .swift-format --recursive Sources/ Tests/
swiftlint --strict
```

**EXPLANATION:** `--strict` 플래그로 모든 경고를 하드 에러로 처리하여 코드 부패를 방지합니다.

### RULE_1_2: 파일 구조 및 Import 순서

**FILE_STRUCTURE_PATTERN:**
- 파일명은 반드시 파일 내에 선언된 주요 타입의 이름과 일치해야 합니다
- 예시: `struct User`는 `User.swift` 파일에 위치합니다

**IMPORT_ORDER_PATTERN:**
```swift
// 1. 표준 라이브러리
import SwiftUI
import Foundation

// 2. 내부 프로젝트 모듈
import Core
import Shared

// 3. 외부 SPM 패키지
import Alamofire
import SwiftUIIntrospect
```

### RULE_1_3: 코드 포매팅

**FORMATTING_RULES:**
```swift
// ✅ 올바른 중괄호 위치
func processData() {
    // 구현
}

// ✅ 매개변수 간 단일 공백
func calculate(a: Int, b: Int) -> Int {
    return a + b
}

// ✅ 긴 체이닝은 여러 줄로 분할 (최대 120자)
let result = data
    .filter { $0.isValid }
    .map { $0.processed() }
    .sorted { $0.priority > $1.priority }
```

### RULE_1_4: Swift Package Manager

모든 프로젝트는 Swift Package Manager를 사용합니다:

**PACKAGE_PATTERN:**
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyProject",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .executable(name: "CLI", targets: ["CLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing", from: "0.4.0")
    ],
    targets: [
        .target(name: "Core"),
        .testTarget(name: "CoreTests", dependencies: ["Core", .product(name: "Testing", package: "swift-testing")])
    ]
)
```

---

## SECTION 2: SOLID 원칙 구현

### RULE_2_1: 단일 책임 원칙 (SRP)

각 타입은 하나의 명확한 책임만 가집니다:

**SRP_PATTERN:**
```swift
// ❌ 잘못된 예: 여러 책임을 가진 클래스
class UserManager {
    private let database: Database
    private let emailService: EmailService
    private let logger: Logger
    
    func createUser(_ data: CreateUserRequest) -> User { /* ... */ }
    func sendEmail(to: String, subject: String) { /* ... */ }
    func logActivity(_ message: String) { /* ... */ }
}

// ✅ 올바른 예: 단일 책임 분리
struct UserRepository {
    private let database: Database
    
    func create(_ user: CreateUserRequest) async throws -> User { /* ... */ }
    func findById(_ id: UUID) async throws -> User? { /* ... */ }
}

class UserService {
    private let repository: UserRepository
    private let emailService: EmailService
    
    init(repository: UserRepository, emailService: EmailService) {
        self.repository = repository
        self.emailService = emailService
    }
    
    func createUser(_ data: CreateUserRequest) async throws -> User { /* ... */ }
}

class EmailService {
    private let smtpClient: SMTPClient
    
    init(smtpClient: SMTPClient) {
        self.smtpClient = smtpClient
    }
    
    func sendWelcomeEmail(to user: User) async throws { /* ... */ }
}
```

### RULE_2_2: 개방-폐쇄 원칙 (OCP)

프로토콜을 통해 확장에는 열려있고 수정에는 닫힌 설계:

**OCP_PATTERN:**
```swift
// 기본 알림 프로토콜
protocol NotificationSender {
    func send(message: String, to recipient: String) async throws
}

// 이메일 구현
struct EmailNotificationSender: NotificationSender {
    private let smtpClient: SMTPClient
    
    func send(message: String, to recipient: String) async throws {
        try await smtpClient.sendEmail(to: recipient, message: message)
    }
}

// SMS 구현 (기존 코드 수정 없이 확장)
struct SMSNotificationSender: NotificationSender {
    private let smsClient: SMSClient
    
    func send(message: String, to recipient: String) async throws {
        try await smsClient.sendSMS(to: recipient, message: message)
    }
}

// 푸시 알림 구현 (추가 확장)
struct PushNotificationSender: NotificationSender {
    private let pushService: PushService
    
    func send(message: String, to recipient: String) async throws {
        try await pushService.sendPush(to: recipient, message: message)
    }
}

// 사용하는 서비스는 구체적 구현에 의존하지 않음
class NotificationService {
    private let senders: [NotificationSender]
    
    init(senders: [NotificationSender]) {
        self.senders = senders
    }
    
    func notifyAll(message: String, to recipient: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for sender in senders {
                group.addTask {
                    try await sender.send(message: message, to: recipient)
                }
            }
            
            try await group.waitForAll()
        }
    }
}
```

### RULE_2_3: 의존성 역전 원칙 (DIP)

고수준 모듈이 저수준 모듈에 의존하지 않도록 추상화 사용:

**DIP_PATTERN:**
```swift
// 추상화 (프로토콜)
protocol OrderRepository {
    func create(_ order: CreateOrderRequest) async throws -> Order
    func updateStatus(_ id: UUID, status: OrderStatus) async throws
}

protocol PaymentProcessor {
    func processPayment(_ paymentInfo: PaymentInfo) async throws
}

// 고수준 정책 (추상화에 의존)
class OrderService {
    private let repository: OrderRepository
    private let paymentProcessor: PaymentProcessor
    
    init(repository: OrderRepository, paymentProcessor: PaymentProcessor) {
        self.repository = repository
        self.paymentProcessor = paymentProcessor
    }
    
    func processOrder(_ orderData: CreateOrderRequest) async throws -> Order {
        // 고수준 비즈니스 로직
        let order = try await repository.create(orderData)
        try await paymentProcessor.processPayment(order.paymentInfo)
        try await repository.updateStatus(order.id, status: .paid)
        return order
    }
}

// 저수준 구현 (추상화에 의존)
struct CoreDataOrderRepository: OrderRepository {
    private let context: NSManagedObjectContext
    
    func create(_ order: CreateOrderRequest) async throws -> Order {
        // Core Data 특정 구현
    }
    
    func updateStatus(_ id: UUID, status: OrderStatus) async throws {
        // Core Data 특정 구현
    }
}

struct StripePaymentProcessor: PaymentProcessor {
    private let apiKey: String
    
    func processPayment(_ paymentInfo: PaymentInfo) async throws {
        // Stripe API 호출
    }
}

// 의존성 주입을 통한 조립
let orderService = OrderService(
    repository: CoreDataOrderRepository(context: persistentContainer.viewContext),
    paymentProcessor: StripePaymentProcessor(apiKey: stripeApiKey)
)
```

---

## SECTION 3: 네이밍 컨벤션

### RULE_3_1: 기본 네이밍 규칙

| 요소 타입 | 규칙 | 예시 |
|-----------|------|------|
| **TYPES_AND_PROTOCOLS** | `UpperCamelCase` | `struct UserProfile`, `protocol Cacheable` |
| **VARIABLES_AND_FUNCTIONS** | `lowerCamelCase` | `let userProfile`, `func fetchUserData()` |
| **CONSTANTS** | `lowerCamelCase` | `let maxConnections = 100` |
| **ENUM_CASES** | `lowerCamelCase` | `case activeUser`, `case inactiveUser` |
| **GENERIC_TYPES** | 단일 대문자 | `struct Response<T, E>` |

### RULE_3_2: 특수 네이밍 규칙

**BOOLEAN_NAMING_PATTERN:**
```swift
// ✅ 올바른 불리언 네이밍
var isLoading: Bool = false
let hasChanges: Bool = true
var canEdit: Bool = false

// ❌ 잘못된 불리언 네이밍
var loading: Bool = false  // 'is' 접두사 누락
var changes: Bool = true   // 'has' 접두사 누락
```

**PROTOCOL_NAMING_PATTERN:**
```swift
// ✅ 역할을 명확히 하는 프로토콜명
protocol Cacheable {
    func cache()
}

protocol UserServiceDelegate {
    func userDidLogin(_ user: User)
}

protocol DataProviding {
    func fetchData() async throws -> Data
}
```

---

## SECTION 4: 메모리 관리와 소유권

### RULE_4_1: ARC 최적화

참조 사이클을 방지하고 메모리 효율성을 확보:

**WEAK_REFERENCE_PATTERN:**
```swift
class ViewController: UIViewController {
    private weak var delegate: ViewControllerDelegate?
    
    private lazy var button: UIButton = {
        let button = UIButton()
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        return button
    }()
}
```

**UNOWNED_REFERENCE_PATTERN:**
```swift
class Customer {
    let name: String
    var card: CreditCard?
    
    init(name: String) {
        self.name = name
    }
}

class CreditCard {
    let number: UInt64
    unowned let customer: Customer  // Customer가 항상 존재함을 보장
    
    init(number: UInt64, customer: Customer) {
        self.number = number
        self.customer = customer
    }
}
```

### RULE_4_2: 값 타입 우선 원칙

가능한 한 구조체와 열거형을 사용:

**VALUE_TYPE_PATTERN:**
```swift
struct User {
    let id: UUID
    let name: String
    let email: String
    
    func updated(name: String) -> User {
        User(id: id, name: name, email: email)
    }
}
```

---

## SECTION 5: 에러 처리

### RULE_5_1: 구조화된 에러 처리

**ERROR_ENUM_PATTERN:**
```swift
enum NetworkError: Error, LocalizedError {
    case invalidURL
    case noData
    case decodingFailed(Error)
    case serverError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "잘못된 URL입니다"
        case .noData:
            return "데이터를 받지 못했습니다"
        case .decodingFailed(let error):
            return "디코딩 실패: \(error.localizedDescription)"
        case .serverError(let code):
            return "서버 에러: \(code)"
        }
    }
}
```

### RULE_5_2: Result 타입 활용

비동기 작업에서 Result 타입 사용:

**RESULT_PATTERN:**
```swift
func fetchUser(id: String) async -> Result<User, NetworkError> {
    do {
        let user = try await networkService.fetchUser(id: id)
        return .success(user)
    } catch {
        return .failure(.decodingFailed(error))
    }
}
```

---

## SECTION 6: 동시성 (Swift Concurrency)

### RULE_6_1: async/await 우선

새로운 비동기 코드는 async/await 사용:

**ASYNC_AWAIT_PATTERN:**
```swift
actor UserCache {
    private var cache: [String: User] = [:]
    
    func getUser(id: String) async throws -> User {
        if let cached = cache[id] {
            return cached
        }
        
        let user = try await fetchUser(id: id)
        cache[id] = user
        return user
    }
    
    func clearCache() {
        cache.removeAll()
    }
}
```

### RULE_6_2: Actor를 통한 데이터 보호

공유 상태는 Actor로 보호:

**ACTOR_PATTERN:**
```swift
@MainActor
class ViewModel: ObservableObject {
    @Published var users: [User] = []
    @Published var isLoading = false
    
    private let userService: UserService
    
    init(userService: UserService) {
        self.userService = userService
    }
    
    func loadUsers() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            users = try await userService.fetchUsers()
        } catch {
            // 에러 처리
        }
    }
}
```

---

## SECTION 7: SwiftUI 패턴

### RULE_7_1: 뷰 분해

복잡한 뷰는 작은 컴포넌트로 분해:

**VIEW_DECOMPOSITION_PATTERN:**
```swift
struct UserListView: View {
    @StateObject private var viewModel = UserListViewModel()
    
    var body: some View {
        NavigationView {
            VStack {
                SearchBar(text: $viewModel.searchText)
                UserList(users: viewModel.filteredUsers)
            }
            .navigationTitle("사용자")
            .task {
                await viewModel.loadUsers()
            }
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        TextField("검색", text: $text)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .padding()
    }
}

struct UserList: View {
    let users: [User]
    
    var body: some View {
        List(users) { user in
            UserRow(user: user)
        }
    }
}
```

### RULE_7_2: 상태 관리

적절한 프로퍼티 래퍼 사용:

**STATE_MANAGEMENT_PATTERN:**
```swift
struct ContentView: View {
    @State private var count = 0           // 로컬 상태
    @StateObject private var store = Store() // 객체 생성 및 소유
    @ObservedObject var viewModel: ViewModel  // 외부에서 전달받은 객체
    @EnvironmentObject var settings: Settings // 환경에서 주입받은 객체
    
    var body: some View {
        VStack {
            Text("Count: \(count)")
            Button("Increment") {
                count += 1
            }
        }
    }
}
```

---

## SECTION 8: 보안 설계 원칙

### RULE_8_1: 입력 검증과 신뢰 경계

모든 외부 입력은 검증 후 신뢰하는 원칙을 적용:

**INPUT_VALIDATION_PATTERN:**
```swift
import Foundation

// 입력 검증을 위한 프로토콜
protocol Validatable {
    func validate() throws
}

// 검증 에러 정의
enum ValidationError: Error, LocalizedError {
    case invalidEmail(String)
    case weakPassword(String)
    case invalidName(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidEmail(let email):
            return "유효하지 않은 이메일 주소입니다: \(email)"
        case .weakPassword(let reason):
            return "비밀번호가 보안 요구사항을 충족하지 않습니다: \(reason)"
        case .invalidName(let reason):
            return "유효하지 않은 이름입니다: \(reason)"
        }
    }
}

// 검증 가능한 사용자 생성 요청
struct CreateUserRequest: Validatable {
    let name: String
    let email: String
    let password: String
    
    func validate() throws {
        // 이름 검증
        guard name.count >= 2 && name.count <= 50 else {
            throw ValidationError.invalidName("이름은 2-50자 사이여야 합니다")
        }
        
        guard name.allSatisfy({ $0.isLetter || $0.isWhitespace }) else {
            throw ValidationError.invalidName("이름은 문자와 공백만 포함할 수 있습니다")
        }
        
        // 이메일 검증
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        guard emailPredicate.evaluate(with: email) else {
            throw ValidationError.invalidEmail(email)
        }
        
        // 비밀번호 강도 검증
        try validatePasswordStrength(password)
    }
    
    private func validatePasswordStrength(_ password: String) throws {
        guard password.count >= 8 else {
            throw ValidationError.weakPassword("최소 8자 이상이어야 합니다")
        }
        
        let hasUppercase = password.contains { $0.isUppercase }
        let hasLowercase = password.contains { $0.isLowercase }
        let hasDigit = password.contains { $0.isNumber }
        let hasSpecial = password.contains { "!@#$%^&*".contains($0) }
        
        guard hasUppercase && hasLowercase && hasDigit && hasSpecial else {
            throw ValidationError.weakPassword("대소문자, 숫자, 특수문자를 모두 포함해야 합니다")
        }
    }
}

// 신뢰 경계에서의 검증
class UserController {
    private let userService: UserService
    
    init(userService: UserService) {
        self.userService = userService
    }
    
    func createUser(_ request: CreateUserRequest) async throws -> UserResponse {
        // 1. 입력 검증 (신뢰 경계)
        try request.validate()
        
        // 2. 추가 비즈니스 규칙 검증
        if await isEmailBlacklisted(request.email) {
            throw ValidationError.invalidEmail("차단된 이메일 도메인입니다")
        }
        
        // 3. 검증된 데이터로 비즈니스 로직 실행
        let user = try await userService.createUser(request)
        return UserResponse(from: user)
    }
}
```

### RULE_8_2: 최소 권한 원칙

각 컴포넌트는 필요한 최소한의 권한만 가집니다:

**LEAST_PRIVILEGE_PATTERN:**
```swift
// 권한 정의
enum Permission: String, CaseIterable {
    case readUser = "read:user"
    case writeUser = "write:user"
    case deleteUser = "delete:user"
    case readAdmin = "read:admin"
    case writeAdmin = "write:admin"
}

// 사용자 컨텍스트
struct UserContext {
    let userId: UUID
    let permissions: Set<Permission>
    let sessionId: String
}

// 권한 검증 프로퍼티 래퍼
@propertyWrapper
struct RequirePermission {
    let permission: Permission
    
    init(_ permission: Permission) {
        self.permission = permission
    }
    
    var wrappedValue: (UserContext) throws -> Void {
        return { context in
            guard context.permissions.contains(self.permission) else {
                throw SecurityError.insufficientPermissions(required: self.permission)
            }
        }
    }
}

// 보안 에러 정의
enum SecurityError: Error, LocalizedError {
    case insufficientPermissions(required: Permission)
    case accessDenied
    case cannotDeleteSelf
    
    var errorDescription: String? {
        switch self {
        case .insufficientPermissions(let permission):
            return "권한이 부족합니다: \(permission.rawValue)"
        case .accessDenied:
            return "접근이 거부되었습니다"
        case .cannotDeleteSelf:
            return "자신의 계정은 삭제할 수 없습니다"
        }
    }
}

// 서비스 레벨에서 권한 검증
class UserService {
    private let repository: UserRepository
    
    init(repository: UserRepository) {
        self.repository = repository
    }
    
    func getUser(context: UserContext, userId: UUID) async throws -> User {
        // 자신의 정보이거나 읽기 권한이 있는 경우만 허용
        if context.userId != userId {
            guard context.permissions.contains(.readUser) else {
                throw SecurityError.insufficientPermissions(required: .readUser)
            }
        }
        
        return try await repository.findById(userId)
    }
    
    func deleteUser(context: UserContext, userId: UUID) async throws {
        // 삭제 권한 확인
        guard context.permissions.contains(.deleteUser) else {
            throw SecurityError.insufficientPermissions(required: .deleteUser)
        }
        
        // 자신을 삭제하는 것은 금지
        guard context.userId != userId else {
            throw SecurityError.cannotDeleteSelf
        }
        
        try await repository.delete(userId)
    }
}
```

### RULE_8_3: 민감 정보 분리

민감한 정보는 코드베이스와 물리적으로 분리:

**SECRETS_MANAGEMENT_PATTERN:**
```swift
import Foundation
import Security

// 설정 관리자
class ConfigurationManager {
    static let shared = ConfigurationManager()
    
    private init() {}
    
    // 환경 변수에서 설정 로드
    func loadConfiguration() throws -> AppConfiguration {
        guard let databaseURL = ProcessInfo.processInfo.environment["DATABASE_URL"] else {
            throw ConfigurationError.missingEnvironmentVariable("DATABASE_URL")
        }
        
        guard let jwtSecret = ProcessInfo.processInfo.environment["JWT_SECRET"] else {
            throw ConfigurationError.missingEnvironmentVariable("JWT_SECRET")
        }
        
        guard let apiKey = ProcessInfo.processInfo.environment["API_KEY"] else {
            throw ConfigurationError.missingEnvironmentVariable("API_KEY")
        }
        
        return AppConfiguration(
            databaseURL: databaseURL,
            jwtSecret: SecretString(jwtSecret),
            apiKey: SecretString(apiKey)
        )
    }
}

// 민감한 문자열을 안전하게 래핑
struct SecretString {
    private let value: String
    
    init(_ value: String) {
        self.value = value
    }
    
    // 필요한 순간에만 값을 노출
    func withValue<T>(_ closure: (String) throws -> T) rethrows -> T {
        return try closure(value)
    }
}

// 설정 구조체
struct AppConfiguration {
    let databaseURL: String
    let jwtSecret: SecretString
    let apiKey: SecretString
    
    // 로깅용 안전한 표현
    var loggableDescription: String {
        return """
        AppConfiguration(
            databaseURL: \(databaseURL.prefix(20))...,
            jwtSecret: ***,
            apiKey: ***
        )
        """
    }
}

// 키체인을 사용한 민감한 데이터 저장
class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
    func store(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // 기존 항목 삭제
        SecItemDelete(query as CFDictionary)
        
        // 새 항목 추가
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }
    
    func retrieve(key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            throw KeychainError.retrieveFailed(status)
        }
        
        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }
        
        return data
    }
}

enum KeychainError: Error {
    case storeFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case invalidData
}

enum ConfigurationError: Error {
    case missingEnvironmentVariable(String)
}
```

---

## SECTION 9: 테스트 및 검증 원칙

### RULE_9_1: AAA 패턴과 단일 책임

모든 테스트는 Arrange-Act-Assert 패턴을 따르며 하나의 동작만 검증:

**AAA_SINGLE_RESPONSIBILITY_PATTERN:**
```swift
import XCTest
@testable import MyApp

class UserServiceTests: XCTestCase {
    var userService: UserService!
    var mockRepository: MockUserRepository!
    var mockEmailService: MockEmailService!
    
    override func setUp() {
        super.setUp()
        // 각 테스트마다 깨끗한 상태로 시작
        mockRepository = MockUserRepository()
        mockEmailService = MockEmailService()
        userService = UserService(
            repository: mockRepository,
            emailService: mockEmailService
        )
    }
    
    override func tearDown() {
        userService = nil
        mockRepository = nil
        mockEmailService = nil
        super.tearDown()
    }
    
    func test_createUser_withValidData_shouldReturnUser() async throws {
        // Arrange: 테스트 데이터와 모의 객체 설정
        let userData = CreateUserRequest(
            name: "John Doe",
            email: "john@example.com",
            password: "SecurePass123!"
        )
        let expectedUser = User(
            id: UUID(),
            name: userData.name,
            email: userData.email
        )
        
        mockRepository.createUserResult = .success(expectedUser)
        mockEmailService.sendWelcomeEmailResult = .success(())
        
        // Act: 테스트 대상 메서드 실행
        let result = try await userService.createUser(userData)
        
        // Assert: 결과 검증 (하나의 동작만)
        XCTAssertEqual(result.name, expectedUser.name)
        XCTAssertEqual(result.email, expectedUser.email)
        XCTAssertTrue(mockRepository.createUserCalled)
        XCTAssertTrue(mockEmailService.sendWelcomeEmailCalled)
    }
    
    func test_createUser_withDuplicateEmail_shouldThrowError() async {
        // Arrange
        let userData = CreateUserRequest(
            name: "John Doe",
            email: "existing@example.com",
            password: "SecurePass123!"
        )
        mockRepository.createUserResult = .failure(UserError.emailAlreadyExists)
        
        // Act & Assert: 예외 발생 검증
        do {
            _ = try await userService.createUser(userData)
            XCTFail("Expected error to be thrown")
        } catch UserError.emailAlreadyExists {
            // 예상된 에러
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
```

### RULE_9_2: 테스트 피라미드 전략

**TEST_PYRAMID_IMPLEMENTATION:**
```swift
// 1. 단위 테스트 (70-80%): 순수 함수와 비즈니스 로직
class EmailValidationTests: XCTestCase {
    func test_isValidEmail_withValidFormats_shouldReturnTrue() {
        // 다양한 유효한 이메일 형식 테스트
        let validEmails = [
            "user@example.com",
            "test.email+tag@domain.co.uk",
            "user123@test-domain.org"
        ]
        
        for email in validEmails {
            XCTAssertTrue(EmailValidator.isValid(email), "Failed for email: \(email)")
        }
    }
    
    func test_isValidEmail_withInvalidFormats_shouldReturnFalse() {
        let invalidEmails = [
            "invalid-email",
            "@domain.com",
            "user@",
            "user space@domain.com"
        ]
        
        for email in invalidEmails {
            XCTAssertFalse(EmailValidator.isValid(email), "Failed for email: \(email)")
        }
    }
}

// 2. 통합 테스트 (15-25%): 여러 컴포넌트 간 상호작용
class UserServiceIntegrationTests: XCTestCase {
    var userService: UserService!
    var testDatabase: TestDatabase!
    
    override func setUp() async throws {
        try await super.setUp()
        testDatabase = try await TestDatabase.create()
        userService = UserService(
            repository: CoreDataUserRepository(context: testDatabase.context),
            emailService: TestEmailService()
        )
    }
    
    override func tearDown() async throws {
        try await testDatabase.cleanup()
        testDatabase = nil
        userService = nil
        try await super.tearDown()
    }
    
    func test_completeUserCreationWorkflow() async throws {
        // 전체 사용자 생성 워크플로우 테스트
        let userData = CreateUserRequest(
            name: "Integration Test User",
            email: "integration@test.com",
            password: "TestPass123!"
        )
        
        let createdUser = try await userService.createUser(userData)
        let retrievedUser = try await userService.getUser(id: createdUser.id)
        
        XCTAssertEqual(retrievedUser.name, userData.name)
        XCTAssertEqual(retrievedUser.email, userData.email)
    }
}

// 3. UI 테스트 (5-10%): 전체 시스템 워크플로우
class UserRegistrationUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        app = XCUIApplication()
        app.launch()
    }
    
    func test_userRegistrationFlow() {
        // 회원가입 화면으로 이동
        app.buttons["회원가입"].tap()
        
        // 사용자 정보 입력
        let nameField = app.textFields["이름"]
        nameField.tap()
        nameField.typeText("UI Test User")
        
        let emailField = app.textFields["이메일"]
        emailField.tap()
        emailField.typeText("uitest@example.com")
        
        let passwordField = app.secureTextFields["비밀번호"]
        passwordField.tap()
        passwordField.typeText("UITestPass123!")
        
        // 회원가입 버튼 탭
        app.buttons["가입하기"].tap()
        
        // 성공 메시지 확인
        let successMessage = app.staticTexts["회원가입이 완료되었습니다"]
        XCTAssertTrue(successMessage.waitForExistence(timeout: 5))
    }
}
```

### RULE_9_3: 의존성 격리와 모의 객체

**DEPENDENCY_ISOLATION_PATTERN:**
```swift
// 테스트용 프로토콜
protocol MockUserRepository: UserRepository {
    var createUserResult: Result<User, Error> { get set }
    var createUserCalled: Bool { get set }
    var findByIdResult: Result<User?, Error> { get set }
}

// 모의 구현
class MockUserRepository: MockUserRepository {
    var createUserResult: Result<User, Error> = .failure(TestError.notImplemented)
    var createUserCalled = false
    var findByIdResult: Result<User?, Error> = .failure(TestError.notImplemented)
    
    func create(_ user: CreateUserRequest) async throws -> User {
        createUserCalled = true
        return try createUserResult.get()
    }
    
    func findById(_ id: UUID) async throws -> User? {
        return try findByIdResult.get()
    }
}

// 테스트 전용 에러
enum TestError: Error {
    case notImplemented
}

// 격리된 테스트
class IsolatedUserServiceTests: XCTestCase {
    func test_userService_handlesRepositoryError() async {
        // Arrange
        let mockRepository = MockUserRepository()
        mockRepository.createUserResult = .failure(UserError.databaseConnection)
        
        let userService = UserService(
            repository: mockRepository,
            emailService: MockEmailService()
        )
        
        let userData = CreateUserRequest(
            name: "Test User",
            email: "test@example.com",
            password: "TestPass123!"
        )
        
        // Act & Assert
        do {
            _ = try await userService.createUser(userData)
            XCTFail("Expected error to be thrown")
        } catch UserError.databaseConnection {
            // 예상된 에러
            XCTAssertTrue(mockRepository.createUserCalled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
```

---

## SECTION 10: 금지된 안티패턴

### ANTIPATTERN_1: 강제 언래핑 남용

**WRONG_PATTERN:**
```swift
let user = users.first!
let name = user.name!
```

**CORRECT_PATTERN:**
```swift
guard let user = users.first,
      let name = user.name else {
    return
}
```

### ANTIPATTERN_2: 거대한 뷰 컨트롤러

**WRONG_PATTERN:**
```swift
class MassiveViewController: UIViewController {
    // 수백 줄의 코드...
}
```

**CORRECT_PATTERN:**
```swift
class UserViewController: UIViewController {
    private let viewModel: UserViewModel
    private let coordinator: UserCoordinator
    
    // 각 책임을 분리된 객체에 위임
}
```

### ANTIPATTERN_3: 옵셔널 체이닝 남용

**WRONG_PATTERN:**
```swift
user?.profile?.settings?.theme?.color?.hex
```

**CORRECT_PATTERN:**
```swift
guard let profile = user?.profile,
      let settings = profile.settings,
      let theme = settings.theme,
      let color = theme.color else {
    return defaultColor
}
return color.hex
```

---

## SECTION 11: 성능 최적화

### RULE_11_1: 지연 초기화

무거운 객체는 지연 초기화 사용:

**LAZY_INITIALIZATION_PATTERN:**
```swift
class DataManager {
    private lazy var expensiveResource: ExpensiveResource = {
        return ExpensiveResource()
    }()
    
    private lazy var formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}
```

### RULE_11_2: 메모리 효율적인 컬렉션 사용

적절한 컬렉션 타입 선택:

**COLLECTION_OPTIMIZATION_PATTERN:**
```swift
// 순서가 중요하고 중복 허용
var items: [String] = []

// 고유성이 중요하고 빠른 검색 필요
var uniqueItems: Set<String> = []

// 키-값 매핑이 필요
var itemMap: [String: Item] = [:]

// 대용량 데이터의 지연 처리
let processedItems = items.lazy
    .filter { $0.isValid }
    .map { $0.processed() }
```

---

## SECTION 12: 언어 기능 사용 원칙

### RULE_12_1: 값 타입 우선 원칙

기본적으로 값 타입(`struct`, `enum`) 사용을 원칙으로 합니다:

**VALUE_TYPE_FIRST_PATTERN:**
```swift
// ✅ 기본적으로 구조체 사용
struct UserProfile {
    let id: UUID
    let name: String
    let settings: UserSettings
    
    func updated(name: String) -> UserProfile {
        UserProfile(id: id, name: name, settings: settings)
    }
}

// ✅ 클래스는 명백한 참조 시맨틱이 필요한 경우에만
class UserViewModel: ObservableObject {
    @Published var profile: UserProfile
    
    init(profile: UserProfile) {
        self.profile = profile
    }
}
```

### RULE_12_2: 프로토콜 지향 프로그래밍

행동과 기능은 반드시 `protocol`을 사용해 정의:

**PROTOCOL_ORIENTED_PATTERN:**
```swift
// ✅ 프로토콜로 행동 정의
protocol Cacheable {
    associatedtype CacheKey: Hashable
    var cacheKey: CacheKey { get }
    func cache()
}

// ✅ 기본 구현 제공
extension Cacheable {
    func cache() {
        CacheManager.shared.store(self, forKey: cacheKey)
    }
}

// ✅ 구체 타입에서 채택
struct User: Cacheable {
    let id: UUID
    let name: String
    
    var cacheKey: UUID { id }
}
```

### RULE_12_3: 안전한 옵셔널 처리

**강제 언래핑(`!`)은 엄격히 금지됩니다:**

**SAFE_OPTIONAL_PATTERN:**
```swift
// ✅ 안전한 옵셔널 언래핑
func processUser(_ user: User?) {
    guard let user = user else {
        return
    }
    
    // user 사용
}

// ✅ nil-병합 연산자 사용
let displayName = user?.name ?? "Unknown User"

// ✅ 옵셔널 체이닝
let emailDomain = user?.email?.components(separatedBy: "@").last

// ❌ 강제 언래핑 금지
let name = user.name!  // 절대 사용 금지
```

---

## SECTION 13: 동시성 (Strict 모드)

### RULE_13_1: Sendable 클로저

`Task` 또는 `TaskGroup`에 전달되는 모든 클로저는 반드시 `@Sendable`로 선언:

**SENDABLE_CLOSURE_PATTERN:**
```swift
// ✅ Sendable 클로저 사용
func processDataConcurrently(_ data: [Data]) async {
    await withTaskGroup(of: ProcessedData.self) { group in
        for item in data {
            group.addTask { @Sendable in
                return await processItem(item)
            }
        }
        
        for await result in group {
            // 결과 처리
        }
    }
}

// ✅ Sendable 타입만 캡처
struct SendableData: Sendable {
    let value: String
    let timestamp: Date
}
```

### RULE_13_2: 액터 격리

`actor` 내부의 상태는 `await` 키워드 없이는 외부에서 접근할 수 없습니다:

**ACTOR_ISOLATION_PATTERN:**
```swift
actor DataStore {
    private var data: [String: Any] = [:]
    
    func store(_ value: Any, forKey key: String) {
        data[key] = value
    }
    
    func retrieve(forKey key: String) -> Any? {
        return data[key]
    }
    
    // nonisolated 메서드는 격리된 상태에 접근하지 않음
    nonisolated func generateKey() -> String {
        return UUID().uuidString
    }
}

// 사용
let store = DataStore()
await store.store("value", forKey: "key")
let value = await store.retrieve(forKey: "key")
```

### RULE_13_3: MainActor 사용

UI와 상호작용하는 모든 프로퍼티와 메서드는 반드시 `@MainActor`로 명시:

**MAINACTOR_PATTERN:**
```swift
@MainActor
class UIViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func updateUI() {
        // UI 업데이트 로직
        isLoading = false
    }
    
    // 백그라운드 작업은 nonisolated로 표시
    nonisolated func performBackgroundTask() async {
        // 백그라운드 작업
        
        await MainActor.run {
            // UI 업데이트는 MainActor에서
            self.updateUI()
        }
    }
}
```

---

## SECTION 14: 제네릭 & 타입 추론

### RULE_14_1: 제한된 제네릭

타입 안정성과 명확성을 높이기 위해 제네릭 매개변수에 가능한 가장 엄격한 제약 조건 사용:

**CONSTRAINED_GENERICS_PATTERN:**
```swift
// ✅ 제약 조건이 있는 제네릭
func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let decoder = JSONDecoder()
    return try decoder.decode(type, from: data)
}

// ✅ 여러 제약 조건
func process<T: Codable & Identifiable>(_ items: [T]) where T.ID == UUID {
    for item in items {
        // T가 Codable이면서 Identifiable이고, ID가 UUID임을 보장
        print("Processing item with ID: \(item.id)")
    }
}

// ✅ 연관 타입 제약
protocol Repository {
    associatedtype Entity: Identifiable
    associatedtype ID = Entity.ID
    
    func find(by id: ID) async throws -> Entity?
}
```

### RULE_14_2: 명시적 타입 표기

복잡한 제네릭 함수나 가독성 향상이 필요할 때는 반드시 명시적으로 타입 표기:

**EXPLICIT_TYPE_ANNOTATION_PATTERN:**
```swift
// ✅ 복잡한 제네릭에서 명시적 타입 표기
let userRepository: Repository<User, UUID> = DatabaseRepository()

// ✅ 타입 추론이 모호할 때 명시적 표기
let result: Result<User, NetworkError> = await fetchUser(id: "123")

// ✅ 클로저에서 타입 명시
let processedUsers: [ProcessedUser] = users.compactMap { (user: User) -> ProcessedUser? in
    return processUser(user)
}
```

---

## SECTION 15: 코드 생성 (매크로)

### RULE_12_1: 목적이 분명한 매크로

Swift 매크로는 반복적인 상용구 코드를 제거하기 위해서만 사용:

**MACRO_USAGE_PATTERN:**
```swift
// ✅ 상용구 코드 제거를 위한 매크로 사용
@Codable
struct User {
    let id: UUID
    let name: String
    let email: String
    // Codable 구현이 자동 생성됨
}

// ✅ 커스텀 매크로 정의 (필요한 경우)
@attached(member, names: named(init))
public macro DefaultInit() = #externalMacro(module: "MyMacros", type: "DefaultInitMacro")

@DefaultInit
struct Configuration {
    let apiKey: String
    let baseURL: URL
    // init() 메서드가 자동 생성됨
}
```

### RULE_12_2: 매크로 도입 기준

매크로는 명확한 목적과 최소한의 오버헤드를 가질 경우에만 도입:

**MACRO_CRITERIA_PATTERN:**
```swift
// ✅ 반복적인 패턴이 있을 때만 매크로 사용
@Observable  // SwiftUI의 관찰 가능한 객체를 위한 매크로
class ViewModel {
    var isLoading = false
    var errorMessage: String?
    // @Published 등의 상용구 코드가 자동 생성됨
}

// ❌ 단순한 코드에는 매크로 사용 지양
// 매크로 없이도 충분히 간단한 경우
struct SimpleData {
    let value: String
}
```

---

## SECTION 13: 문서화 및 주석

### RULE_13_1: 공개 API 문서화

모든 공개 API는 반드시 DocC 스타일(`///`)을 사용하여 문서화:

**DOCC_DOCUMENTATION_PATTERN:**
```swift
/// 사용자 정보를 관리하는 서비스
///
/// 이 클래스는 사용자 데이터의 CRUD 작업을 담당하며,
/// 네트워크 요청과 로컬 캐싱을 통합적으로 관리합니다.
///
/// ## 사용 예시
/// ```swift
/// let service = UserService()
/// let user = try await service.fetchUser(id: "123")
/// ```
public class UserService {
    
    /// 지정된 ID로 사용자를 조회합니다
    ///
    /// - Parameter id: 조회할 사용자의 고유 식별자
    /// - Returns: 사용자 정보, 존재하지 않으면 nil
    /// - Throws: 네트워크 오류 또는 디코딩 오류
    public func fetchUser(id: String) async throws -> User? {
        // 구현
    }
}
```

### RULE_13_2: 주석의 초점

주석은 "어떻게"(구현 방식)가 아닌 "왜"(의도나 논리적 근거)를 설명:

**COMMENT_FOCUS_PATTERN:**
```swift
// ✅ "왜"를 설명하는 주석
func calculateDiscount(for user: User) -> Double {
    // 프리미엄 사용자는 추가 할인을 받습니다
    // 비즈니스 규칙: 1년 이상 사용자는 VIP 대우
    if user.membershipDuration > .year {
        return 0.15
    }
    
    return 0.10
}

// ❌ "어떻게"를 설명하는 불필요한 주석
func addNumbers(a: Int, b: Int) -> Int {
    // a와 b를 더합니다 (불필요한 주석)
    return a + b
}
```

### RULE_13_3: 코드 구조화

타입 내에서 프로퍼티와 메서드를 논리적으로 그룹화하기 위해 `// MARK:` 사용:

**CODE_ORGANIZATION_PATTERN:**
```swift
class UserViewController: UIViewController {
    
    // MARK: - Properties
    
    private let viewModel: UserViewModel
    private lazy var tableView = UITableView()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadData()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        // UI 설정
    }
    
    // MARK: - Data Loading
    
    private func loadData() {
        // 데이터 로딩
    }
    
    // MARK: - Actions
    
    @objc private func refreshButtonTapped() {
        // 새로고침 액션
    }
}
```
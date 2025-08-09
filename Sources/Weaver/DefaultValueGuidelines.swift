// Weaver/Sources/Weaver/DefaultValueGuidelines.swift

import Foundation

// MARK: - ==================== DefaultValue 설계 가이드라인 ====================

/// DependencyKey의 defaultValue 설계를 위한 가이드라인과 유틸리티를 제공합니다.
///
/// ## 기본 원칙
/// 1. **안전성 우선**: fatalError 대신 안전한 기본값이나 Mock 객체 제공
/// 2. **Preview 친화적**: SwiftUI Preview에서 즉시 동작 가능한 값
/// 3. **테스트 격리**: 외부 의존성 없이 독립적으로 동작
/// 4. **성능 고려**: 기본값 생성 비용 최소화
///
/// ## 타입별 권장 패턴
///
/// ### 1. Primitive 타입 - 직접적인 기본값
/// ```swift
/// struct CounterKey: DependencyKey {
///     static var defaultValue: Int { 0 }
/// }
/// ```
///
/// ### 2. Protocol 타입 - Null Object 패턴
/// ```swift
/// protocol Logger {
///     func log(_ message: String)
/// }
///
/// struct LoggerKey: DependencyKey {
///     static var defaultValue: Logger { NoOpLogger() }
/// }
/// ```
///
/// ### 3. 복잡한 객체 - Mock 구현
/// ```swift
/// struct NetworkServiceKey: DependencyKey {
///     static var defaultValue: NetworkService { MockNetworkService() }
/// }
/// ```
public enum DefaultValueGuidelines {

  /// Preview 환경에서 사용할 안전한 기본값을 생성하는 헬퍼입니다.
  /// - Parameter productionDefault: 프로덕션에서 사용할 기본값
  /// - Parameter previewDefault: Preview에서 사용할 기본값
  /// - Returns: 환경에 따른 적절한 기본값
  public static func safeDefault<T>(
    production: @autoclosure () -> T,
    preview: @autoclosure () -> T
  ) -> T {
    if WeaverEnvironment.isPreview {
      return preview()
    } else {
      return production()
    }
  }

  /// 디버그/릴리즈 환경에 따른 기본값을 제공하는 헬퍼입니다.
  public static func debugDefault<T>(
    debug: @autoclosure () -> T,
    release: @autoclosure () -> T
  ) -> T {
    #if DEBUG
      return debug()
    #else
      return release()
    #endif
  }
}

// MARK: - ==================== 공통 Null Object 구현 ====================

/// 로깅 기능을 위한 Null Object 패턴 구현입니다.
public struct NoOpLogger: Sendable {
  public init() {}

  public func debug(_ message: String) {}
  public func info(_ message: String) {}
  public func warning(_ message: String) {}
  public func error(_ message: String) {}
}

/// 분석/추적 기능을 위한 Null Object 패턴 구현입니다.
public struct NoOpAnalytics: Sendable {
  public init() {}

  public func track(event: String, parameters: [String: Any] = [:]) {}
  public func setUserProperty(key: String, value: String) {}
  public func setUserId(_ userId: String?) {}
}

/// 네트워크 서비스를 위한 기본 Mock 구현입니다.
public struct OfflineNetworkService: Sendable {
  public init() {}

  public func isOnline() -> Bool { false }
  public func fetch<T>(url: URL) async throws -> T where T: Decodable {
    throw NetworkError.offline
  }
}

/// 네트워크 관련 에러 정의
public enum NetworkError: Error, LocalizedError {
  case offline
  case invalidURL
  case noData

  public var errorDescription: String? {
    switch self {
    case .offline:
      return "오프라인 상태입니다. 네트워크 연결을 확인해주세요."
    case .invalidURL:
      return "잘못된 URL입니다."
    case .noData:
      return "데이터를 받을 수 없습니다."
    }
  }
}

// MARK: - ==================== 사용 예시 ====================

/// 실제 사용 예시들을 보여주는 샘플 DependencyKey들입니다.
public enum SampleDependencyKeys {

  /// 로거 서비스 키 - Null Object 패턴 사용
  /// 권장 스코프: .startup (앱 전체에서 사용되는 기반 서비스)
  public struct LoggerKey: DependencyKey {
    public typealias Value = NoOpLogger
    public static var defaultValue: NoOpLogger {
      DefaultValueGuidelines.debugDefault(
        debug: NoOpLogger(),  // 디버그에서는 콘솔 출력 가능한 로거
        release: NoOpLogger()  // 릴리즈에서는 조용한 로거
      )
    }
  }

  /// 설정 값 키 - 직접적인 기본값 사용
  /// 권장 스코프: .startup (앱 시작 시 필요한 설정)
  public struct AppConfigKey: DependencyKey {
    public struct AppConfig: Sendable {
      public let apiTimeout: TimeInterval
      public let maxRetryCount: Int
      public let isDebugMode: Bool

      public init(
        apiTimeout: TimeInterval = 30.0, maxRetryCount: Int = 3, isDebugMode: Bool = false
      ) {
        self.apiTimeout = apiTimeout
        self.maxRetryCount = maxRetryCount
        self.isDebugMode = isDebugMode
      }
    }

    public typealias Value = AppConfig
    public static var defaultValue: AppConfig {
      DefaultValueGuidelines.safeDefault(
        production: AppConfig(isDebugMode: false),
        preview: AppConfig(apiTimeout: 5.0, isDebugMode: true)  // Preview에서는 빠른 타임아웃
      )
    }
  }

  /// 네트워크 서비스 키 - Mock 객체 사용
  /// 권장 스코프: .shared (여러 곳에서 공유되는 서비스)
  public struct NetworkServiceKey: DependencyKey {
    public typealias Value = OfflineNetworkService
    public static var defaultValue: OfflineNetworkService {
      OfflineNetworkService()  // 항상 안전한 오프라인 모드
    }
  }
  
  /// 사용자 세션 키 - 상태 관리 서비스
  /// 권장 스코프: .shared (앱 전체에서 공유되는 사용자 상태)
  public struct UserSessionKey: DependencyKey {
    public typealias Value = AnonymousUserSession
    public static var defaultValue: AnonymousUserSession {
      AnonymousUserSession()
    }
  }
  
  /// 이미지 처리 서비스 키 - 무거운 서비스
  /// 권장 스코프: .whenNeeded (특정 기능에서만 사용, 메모리 사용량 큼)
  public struct ImageProcessingServiceKey: DependencyKey {
    public typealias Value = BasicImageProcessor
    public static var defaultValue: BasicImageProcessor {
      BasicImageProcessor()
    }
  }
  
  /// UUID 생성기 키 - 상태 없는 유틸리티
  /// 권장 스코프: .transient (매번 새로운 인스턴스 필요)
  public struct UUIDGeneratorKey: DependencyKey {
    public typealias Value = SystemUUIDGenerator
    public static var defaultValue: SystemUUIDGenerator {
      SystemUUIDGenerator()
    }
  }
}

// MARK: - ==================== 스코프별 권장 패턴 ====================

/// 스코프별 권장 사용 패턴과 예시를 제공합니다.
public enum ScopePatterns {
  
  /// .startup 스코프 권장 패턴
  /// - 앱 시작 시 반드시 필요한 서비스
  /// - 다른 서비스들이 의존하는 기반 서비스
  /// - 초기화 시간이 오래 걸리는 서비스
  public enum Startup {
    /// 로깅 서비스 패턴
    public static func logger() -> (any DependencyKey.Type, Scope) {
      return (SampleDependencyKeys.LoggerKey.self, .startup)
    }
    
    /// 설정 서비스 패턴
    public static func configuration() -> (any DependencyKey.Type, Scope) {
      return (SampleDependencyKeys.AppConfigKey.self, .startup)
    }
  }
  
  /// .shared 스코프 권장 패턴
  /// - 여러 곳에서 공유되는 서비스
  /// - 상태를 유지해야 하는 서비스
  /// - 일반적인 비즈니스 로직 서비스
  public enum Shared {
    /// 네트워크 서비스 패턴
    public static func network() -> (any DependencyKey.Type, Scope) {
      return (SampleDependencyKeys.NetworkServiceKey.self, .shared)
    }
    
    /// 사용자 세션 패턴
    public static func userSession() -> (any DependencyKey.Type, Scope) {
      return (SampleDependencyKeys.UserSessionKey.self, .shared)
    }
  }
  
  /// .whenNeeded 스코프 권장 패턴
  /// - 특정 기능에서만 사용되는 서비스
  /// - 메모리 사용량이 큰 서비스
  /// - 초기화 비용이 높은 서비스
  public enum WhenNeeded {
    /// 이미지 처리 서비스 패턴
    public static func imageProcessing() -> (any DependencyKey.Type, Scope) {
      return (SampleDependencyKeys.ImageProcessingServiceKey.self, .whenNeeded)
    }
  }
  
  /// .transient 스코프 권장 패턴
  /// - 상태를 공유하면 안 되는 서비스
  /// - 매번 새로운 인스턴스가 필요한 경우
  /// - 가벼운 유틸리티 서비스
  public enum Transient {
    /// UUID 생성기 패턴
    public static func uuidGenerator() -> (any DependencyKey.Type, Scope) {
      return (SampleDependencyKeys.UUIDGeneratorKey.self, .transient)
    }
  }
}

// MARK: - ==================== 추가 Mock 서비스들 ====================

/// 익명 사용자 세션 Mock
public struct AnonymousUserSession: Sendable {
  public let isLoggedIn = false
  public let userId: String? = nil
  
  public init() {}
  
  public func login(username: String, password: String) async -> Bool {
    return false // Mock에서는 항상 실패
  }
}

/// 기본 이미지 처리기 Mock
public struct BasicImageProcessor: Sendable {
  public init() {}
  
  public func resize(image: Data, to size: CGSize) async -> Data {
    return image // Mock에서는 원본 반환
  }
  
  public func applyFilter(image: Data, filter: String) async -> Data {
    return image // Mock에서는 원본 반환
  }
}

/// 시스템 UUID 생성기
public struct SystemUUIDGenerator: Sendable {
  public init() {}
  
  public func generate() -> String {
    return UUID().uuidString
  }
  
  public func generateShort() -> String {
    return String(UUID().uuidString.prefix(8))
  }
}

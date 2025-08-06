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
  public struct NetworkServiceKey: DependencyKey {
    public typealias Value = OfflineNetworkService
    public static var defaultValue: OfflineNetworkService {
      OfflineNetworkService()  // 항상 안전한 오프라인 모드
    }
  }
}

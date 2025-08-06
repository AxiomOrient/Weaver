// Weaver/Sources/Weaver/WeaverError.swift

import Foundation

// MARK: - ==================== Error Types ====================

/// Weaver 라이브러리에서 발생하는 최상위 에러 타입입니다.
/// DevPrinciples Article 10에 따라 명확한 에러 정보를 제공합니다.
public enum WeaverError: Error, LocalizedError, Sendable, Equatable {
    case containerNotFound
    case containerNotReady(currentState: LifecycleState)
    case containerFailed(underlying: any Error & Sendable)
    case resolutionFailed(ResolutionError)
    case shutdownInProgress
    case initializationTimeout(timeoutDuration: TimeInterval)
    case dependencyResolutionFailed(keyName: String, currentState: LifecycleState, underlying: any Error & Sendable)
    
    // 🔧 [NEW] 추가 에러 타입들
    case criticalDependencyFailed(keyName: String, underlying: any Error & Sendable)
    case memoryPressureDetected(availableMemory: UInt64)
    case appLifecycleEventFailed(event: String, keyName: String, underlying: any Error & Sendable)
    
    public var errorDescription: String? {
        switch self {
        case .containerNotFound:
            return "활성화된 WeaverContainer를 찾을 수 없습니다."
        case .containerNotReady(let state):
            return "컨테이너가 아직 준비되지 않았습니다. 현재 상태: \(state)"
        case .containerFailed(let error):
            return "컨테이너 초기화가 실패했습니다: \(error.localizedDescription)"
        case .resolutionFailed(let resolutionError):
            return "의존성 해결에 실패했습니다: \(resolutionError.localizedDescription)"
        case .shutdownInProgress:
            return "컨테이너가 종료 중이므로 의존성을 해결할 수 없습니다."
        case .initializationTimeout(let timeoutDuration):
            return "컨테이너 초기화 시간이 초과되었습니다 (\(timeoutDuration)초)"
        case .dependencyResolutionFailed(let keyName, let currentState, let underlying):
            return "의존성 '\(keyName)' 해결 실패 - 커널 상태: \(currentState), 원인: \(underlying.localizedDescription)"
        case .criticalDependencyFailed(let keyName, let underlying):
            return "🚨 필수 의존성 '\(keyName)' 초기화 실패 - 앱 시작 불가: \(underlying.localizedDescription)"
        case .memoryPressureDetected(let availableMemory):
            return "⚠️ 메모리 부족 감지 (사용 가능: \(availableMemory)MB) - 의존성 정리 필요"
        case .appLifecycleEventFailed(let event, let keyName, let underlying):
            return "📱 앱 생명주기 이벤트 '\(event)' 처리 실패 - 서비스: \(keyName), 원인: \(underlying.localizedDescription)"
        }
    }
    
    /// 🔧 [IMPROVED] 개발자를 위한 상세 디버깅 정보를 제공합니다.
    public var debugDescription: String {
        let baseDescription = errorDescription ?? "Unknown WeaverError"
        
        if WeaverEnvironment.isDevelopment {
            let timestamp = DateFormatter.debugTimestamp.string(from: Date())
            let threadInfo = Thread.isMainThread ? "MainThread" : "BackgroundThread"
            
            // 🚨 [FIXED] 스택 트레이스 안전성 개선
            let safeStackTrace = Thread.callStackSymbols.prefix(3)
                .compactMap { symbol in
                    // 민감한 정보 필터링
                    let filtered = symbol.replacingOccurrences(of: #"0x[0-9a-fA-F]+"#, with: "0x***", options: .regularExpression)
                    return filtered.isEmpty ? nil : filtered
                }
                .joined(separator: " → ")
            
            return """
            🐛 [DEBUG] \(baseDescription)
            📅 시간: \(timestamp)
            🧵 스레드: \(threadInfo)
            📍 호출 스택: \(safeStackTrace)
            💡 해결 방법: DependencyKey의 defaultValue 구현을 확인하세요.
            """
        }
        
        return baseDescription
    }
    
    // MARK: - Equatable 구현
    public static func == (lhs: WeaverError, rhs: WeaverError) -> Bool {
        switch (lhs, rhs) {
        case (.containerNotFound, .containerNotFound):
            return true
        case (.containerNotReady(let lhsState), .containerNotReady(let rhsState)):
            return lhsState == rhsState
        case (.containerFailed(let lhsError), .containerFailed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.resolutionFailed(let lhsError), .resolutionFailed(let rhsError)):
            return lhsError == rhsError
        case (.shutdownInProgress, .shutdownInProgress):
            return true
        case (.initializationTimeout(let lhsDuration), .initializationTimeout(let rhsDuration)):
            return lhsDuration == rhsDuration
        case (.dependencyResolutionFailed(let lhsKey, let lhsState, let lhsError), 
              .dependencyResolutionFailed(let rhsKey, let rhsState, let rhsError)):
            return lhsKey == rhsKey && lhsState == rhsState && lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

/// 의존성 해결 과정에서 발생하는 구체적인 에러 타입입니다.
public enum ResolutionError: Error, LocalizedError, Sendable, Equatable {
    case circularDependency(path: String)
    case factoryFailed(keyName: String, underlying: any Error & Sendable)
    case typeMismatch(expected: String, actual: String, keyName: String)
    case keyNotFound(keyName: String)
    case weakObjectDeallocated(keyName: String)
    
    public var errorDescription: String? {
        switch self {
        case .circularDependency(let path):
            return "순환 참조가 감지되었습니다: \(path)"
        case .factoryFailed(let keyName, let underlying):
            return "'\(keyName)' 의존성 생성(factory)에 실패했습니다: \(underlying.localizedDescription)"
        case .typeMismatch(let expected, let actual, let keyName):
            return "'\(keyName)' 의존성의 타입이 일치하지 않습니다. 예상: \(expected), 실제: \(actual). '.weak' 스코프는 클래스(AnyObject) 타입만 지원합니다."
        case .keyNotFound(let keyName):
            return "'\(keyName)' 키에 대한 등록 정보를 찾을 수 없습니다."
        case .weakObjectDeallocated(let keyName):
            return "'\(keyName)'에 대한 약한 참조(weak) 의존성이 이미 메모리에서 해제되었습니다."
        }
    }
    
    // MARK: - Equatable 구현
    public static func == (lhs: ResolutionError, rhs: ResolutionError) -> Bool {
        switch (lhs, rhs) {
        case (.circularDependency(let lhsPath), .circularDependency(let rhsPath)):
            return lhsPath == rhsPath
        case (.factoryFailed(let lhsKeyName, let lhsError), .factoryFailed(let rhsKeyName, let rhsError)):
            return lhsKeyName == rhsKeyName && lhsError.localizedDescription == rhsError.localizedDescription
        case (.typeMismatch(let lhsExpected, let lhsActual, let lhsKeyName), .typeMismatch(let rhsExpected, let rhsActual, let rhsKeyName)):
            return lhsExpected == rhsExpected && lhsActual == rhsActual && lhsKeyName == rhsKeyName
        case (.keyNotFound(let lhsKeyName), .keyNotFound(let rhsKeyName)):
            return lhsKeyName == rhsKeyName
        case (.weakObjectDeallocated(let lhsKeyName), .weakObjectDeallocated(let rhsKeyName)):
            return lhsKeyName == rhsKeyName
        default:
            return false
        }
    }
}

// MARK: - ==================== Helper Extensions ====================

extension DateFormatter {
    static let debugTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
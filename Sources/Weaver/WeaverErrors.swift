// Weaver/Sources/Weaver/WeaverErrors.swift

import Foundation

// MARK: - ==================== Errors ====================

/// Weaver 라이브러리에서 발생하는 최상위 에러 타입입니다.
public enum WeaverError: Error, LocalizedError, Sendable {
    case containerNotFound
    case resolutionFailed(ResolutionError)
    case shutdownInProgress
    
    public var errorDescription: String? {
        switch self {
        case .containerNotFound:
            return "활성화된 WeaverContainer를 찾을 수 없습니다."
        case .resolutionFailed(let error):
            return error.localizedDescription
        case .shutdownInProgress:
            return "컨테이너가 종료 처리 중입니다."
        }
    }
}

/// 의존성 해결 과정에서 발생하는 구체적인 에러 타입입니다.
public enum ResolutionError: Error, LocalizedError, Sendable {
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
}
import Foundation

/// Weaver 라이브러리 내에서 발생하는 주요 에러 타입입니다.
public enum WeaverError: Error, LocalizedError {
    /// 현재 실행 컨텍스트에서 활성화된 `WeaverContainer`를 찾을 수 없을 때 발생합니다.
    ///
    /// 이 에러는 보통 `container.withScope { ... }` 블록 외부에서 `@Inject`를 사용하려고 할 때 발생합니다.
    case containerNotFound
    
    public var errorDescription: String? {
        switch self {
        case .containerNotFound:
            return "No active WeaverContainer found in the current context. Make sure to wrap your operation in `container.withScope { ... }`."
        }
    }
}

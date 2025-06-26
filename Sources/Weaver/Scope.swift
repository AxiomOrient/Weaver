import Foundation

/// 의존성의 생명주기를 정의하는 열거형입니다.
///
/// `Scope`는 의존성이 언제, 어떻게 생성되고 관리되는지를 결정합니다.
public enum Scope: Sendable, CaseIterable, CustomStringConvertible {
    /// 컨테이너 스코프: 의존성이 등록된 컨테이너의 생명주기를 따릅니다.
    ///
    /// - 컨테이너 내에서 처음 `resolve`될 때 인스턴스가 생성됩니다.
    /// - 해당 컨테이너 내에서는 동일한 인스턴스가 계속 반환됩니다.
    /// - 컨테이너가 메모리에서 해제될 때 함께 해제됩니다.
    /// - 예: `AppContainer`에 등록된 `APIClient`는 앱 전체에서, `UserSessionContainer`에 등록된 `UserProfile`은 세션 동안 유지됩니다.
    case container
    
    /// 캐시드 스코프: 현재 `Task`의 생명주기를 따릅니다.
    ///
    /// - 동일 `Task` 내에서는 같은 인스턴스가 반환됩니다.
    /// - `Task`가 완료되면 인스턴스가 해제되어, 여러 비동기 작업에서 일관된 상태를 유지하는 데 유용합니다.
    case cached
    
    /// 일시적 스코프: `resolve`될 때마다 새로운 인스턴스를 생성합니다.
    ///
    /// - 캐싱을 하지 않으므로 항상 새로운 인스턴스가 반환됩니다.
    /// - 상태를 가지지 않는 서비스나 객체에 적합합니다.
    case transient
    
    /// 스코프의 문자열 표현
    public var description: String {
        switch self {
        case .container: return "container"
        case .cached: return "cached"
        case .transient: return "transient"
        }
    }
}

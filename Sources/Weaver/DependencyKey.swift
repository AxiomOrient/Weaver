import Foundation

/// 의존성을 타입-안전하게 식별하고 기본값을 제공하는 프로토콜입니다.
///
/// 모든 의존성은 `DependencyKey`를 준수하는 타입을 통해 고유하게 식별됩니다.
/// 이 프로토콜은 의존성의 `Value` 타입과, 의존성이 등록되지 않았을 때 사용될 `defaultValue`를 정의합니다.
///
/// # 사용 예제
/// ```swift
/// private struct APIClientKey: DependencyKey {
///     static var defaultValue: APIClient = MockAPIClient()
/// }
/// ```
public protocol DependencyKey {
    /// 의존성이 나타내는 실제 값의 타입입니다.
    associatedtype Value
    
    /// 의존성이 컨테이너에 명시적으로 등록되지 않았을 때 반환될 기본값입니다.
    ///
    /// 이 값은 주로 테스트 환경에서 Mock 객체를 제공하거나, 기본 설정이 있는 서비스에 사용됩니다.
    static var defaultValue: Value { get }
}

/// 타입 소거를 위한 내부 헬퍼 구조체입니다.
internal struct AnyDependencyKey: Hashable, CustomStringConvertible {
    private let id: ObjectIdentifier
    private let name: String
    
    init<Key: DependencyKey>(_ keyType: Key.Type) {
        self.id = ObjectIdentifier(keyType)
        self.name = String(describing: keyType)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: AnyDependencyKey, rhs: AnyDependencyKey) -> Bool {
        lhs.id == rhs.id
    }
    
    public var description: String {
        return name
    }
}

/// 의존성 등록 및 해결 과정에서 발생할 수 있는 에러 타입입니다.
public enum DependencyError: Error, LocalizedError {
    /// 요청된 의존성 키가 컨테이너에 등록되지 않았을 때 발생하는 에러입니다.
    /// - Parameter keyName: 등록되지 않은 의존성 키의 이름.
    case keyNotRegistered(String)
    
    /// 의존성 해결 과정에서 순환 참조가 감지되었을 때 발생하는 에러입니다.
    /// - Parameter cycle: 순환 참조 경로를 나타내는 문자열.
    case circularDependency(String)
    
    /// 의존성 팩토리(생성 클로저)가 에러를 던졌을 때 발생하는 에러입니다.
    /// - Parameters:
    ///   - keyName: 실패한 의존성 키의 이름.
    ///   - underlying: 팩토리에서 발생한 원본 에러.
    case factoryFailed(String, underlying: Error)
    
    /// 유효하지 않은 스코프를 사용하려고 할 때 발생하는 에러입니다.
    /// - Parameter scopeName: 잘못된 스코프의 이름.
    case invalidScope(String)
    
    public var errorDescription: String? {
        switch self {
        case .keyNotRegistered(let keyName):
            return "Dependency key '\(keyName)' is not registered."
        case .circularDependency(let cycle):
            return "Circular dependency detected: \(cycle)"
        case .factoryFailed(let keyName, let underlying):
            return "Factory for dependency '\(keyName)' failed: \(underlying.localizedDescription)"
        case .invalidScope(let scopeName):
            return "Invalid scope: \(scopeName)"
        }
    }
}

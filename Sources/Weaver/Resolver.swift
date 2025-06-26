/// 의존성을 해결하는 역할을 정의하는 프로토콜입니다.
public protocol Resolver: Sendable {
    /// 지정된 키에 해당하는 의존성을 해결하여 반환합니다.
    ///
    /// - Parameter keyType: 해결할 의존성의 `DependencyKey` 타입.
    /// - Returns: 해결된 의존성 인스턴스.
    /// - Throws: 의존성 해결 과정에서 발생할 수 있는 에러.
    func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value
}

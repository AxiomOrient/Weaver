/// 관련된 의존성 등록을 그룹화하는 프로토콜입니다.
///
/// 각 `Module`은 특정 기능 영역이나 계층에 필요한 의존성들을 정의하는 데 사용됩니다.
/// 이를 통해 의존성 구성을 모듈화하고 재사용할 수 있습니다.
///
/// # 사용 예제
/// ```swift
/// struct NetworkModule: Module {
///     func configure(_ container: ContainerBuilder) {
///         container.register(APIClientKey.self, scope: .container) { _ in
///             LiveAPIClient()
///         }
///     }
/// }
/// ```
public protocol Module: Sendable {
    /// 지정된 컨테이너 빌더에 의존성을 등록합니다.
    /// - Parameter container: 의존성을 등록할 `ContainerBuilder` 인스턴스.
    func configure(_ container: ContainerBuilder)
}

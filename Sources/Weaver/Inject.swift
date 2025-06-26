import Foundation

/// 의존성을 선언하고 현재 스코프의 컨테이너로부터 주입받기 위한 프로퍼티 래퍼입니다.
///
/// `Weaver.withScope`로 설정된 현재 `WeaverContainer`에서 의존성을 비동기적으로 해결합니다.
///
/// # 사용 예제
/// ```swift
/// let appContainer = WeaverContainer(modules: [AppModule()])
///
/// await Weaver.withScope(appContainer) {
///     let viewModel = MyViewModel()
///     await viewModel.onAppear()
/// }
///
/// @Observable
/// class MyViewModel {
///     @Inject(APIClientKey.self) private var apiClient
///
///     func onAppear() async {
///         let client = try! await apiClient()
///         // ...
///     }
/// }
/// ```
@propertyWrapper
public struct Inject<Key: DependencyKey> where Key.Value: Sendable {
    
    private let keyType: Key.Type

    public init(_ keyType: Key.Type) {
        self.keyType = keyType
    }

    public var wrappedValue: Self {
        return self
    }

    public func callAsFunction() async throws -> Key.Value {
        guard let container = Weaver.current else {
            throw WeaverError.containerNotFound
        }
        return try await container.resolve(keyType)
    }
}

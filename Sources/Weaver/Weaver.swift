import Foundation

/// Weaver DI 시스템의 최상위 네임스페이스 및 스코프 관리자입니다.
public enum Weaver {
    @TaskLocal public static var current: WeaverContainer?

    /// 지정된 컨테이너를 현재 스코프로 설정하고, 제공된 비동기 작업을 실행합니다.
    ///
    /// 이 클로저 내에서 `@Inject` 프로퍼티 래퍼를 사용하면, 제공된 `container`에서 의존성을 해결합니다.
    /// 여러 `withScope` 호출을 중첩하여 계층적 스코프를 구성할 수 있습니다.
    ///
    /// - Parameters:
    ///   - container: 작업 스코프 내에서 활성화할 `WeaverContainer` 인스턴스.
    ///   - operation: 지정된 컨테이너 스코프 내에서 실행할 비동기 클로저.
    /// - Returns: `operation` 클로저의 반환값.
    /// - Throws: `operation` 클로저에서 발생하는 에러.
    public static func withScope<R>(
        _ container: WeaverContainer,
        operation: () async throws -> R
    ) async rethrows -> R {
        try await Weaver.$current.withValue(container, operation: operation)
    }
}

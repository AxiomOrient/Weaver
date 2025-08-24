#if !LEGACY_DISABLED

import Foundation

// MARK: - ==================== 기존 DependencyKey 시스템 확장 ====================

/// 기존 DependencyKey를 확장하여 스코프 정보를 추가합니다.
/// 기존 시스템과 완전 호환되면서 성능 최적화를 제공합니다.
public protocol ScopedDependencyKey: DependencyKey {
    /// 이 의존성이 사용할 스코프 (기본값: shared)
    static var scope: Scope { get }
    
    /// 비동기 팩토리 메서드 (선택사항)
    /// 복잡한 초기화가 필요한 경우에만 구현
    static func createAsync() async throws -> Value
}

public extension ScopedDependencyKey {
    /// 기본 스코프는 shared (앱 전체에서 공유)
    static var scope: Scope { .shared }
    
    /// 기본 구현: liveValue 반환
    static func createAsync() async throws -> Value { liveValue }
}

// MARK: - ==================== 스코프 최적화 헬퍼 ====================

/// 스코프별 성능 최적화를 위한 유틸리티
public enum ScopeOptimization {
    
    /// 스코프별 권장 캐싱 전략을 반환합니다.
    public static func cachingStrategy(for scope: Scope) -> CachingStrategy {
        switch scope {
        case .startup, .shared:
            return .permanent  // 영구 캐시 (강한 참조)
        case .whenNeeded:
            return .smart      // 스마트 캐시 (조건부 해제)
        case .weak:
            return .weak       // WeakBox 캐시 (약한 참조)
        case .transient:
            return .none       // 캐시 안함
        }
    }
    
    /// 스코프별 활성화 우선순위를 반환합니다.
    public static func activationPriority(for scope: Scope) -> Int {
        switch scope {
        case .startup: return 100    // 최우선
        case .shared: return 90      // 두 번째 우선순위
        case .whenNeeded: return 50  // 필요시 로딩
        case .weak: return 30        // 낮은 우선순위
        case .transient: return 10   // 가장 낮음
        }
    }
}

/// 캐싱 전략 열거형
public enum CachingStrategy: String, CaseIterable {
    case permanent  // 영구 캐시
    case smart      // 스마트 캐시
    case weak       // 약한 참조 캐시
    case none       // 캐시 안함
}

#endif

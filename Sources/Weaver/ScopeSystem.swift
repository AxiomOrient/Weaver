import Foundation

// MARK: - 스코프 관리 시스템 내부 타입

/// Task-local 캐시를 thread-safe하게 관리하기 위한 actor
actor PerTaskCache {
    private var instances: [AnyDependencyKey: CachedInstance] = [:]

    func setInstance(_ instance: CachedInstance, forKey key: AnyDependencyKey) {
        instances[key] = instance
    }

    func getInstance(forKey key: AnyDependencyKey) -> CachedInstance? {
        return instances[key]
    }

    func removeAll() {
        instances.removeAll()
    }

    func count() -> Int {
        return instances.count
    }
}

/// 캐시된 의존성 인스턴스 정보
internal struct CachedInstance {
    let value: Any
    let scope: Scope
    let creationTime: Date
    
    init(value: Any, scope: Scope) {
        self.value = value
        self.scope = scope
        self.creationTime = Date()
    }
}

public protocol Disposable: Sendable {
    func dispose()
}

internal struct ScopeDebugInfo: Sendable {
    let containerScopeCount: Int
    let cachedCount: Int
    let containerCreationOrder: [String]
}

// MARK: - 스코프 관리자

internal actor ScopeManager: Sendable {
    private var containerCache: [AnyDependencyKey: CachedInstance] = [:]
    @TaskLocal private static var taskCache = PerTaskCache()
    private var containerCreationOrder: [AnyDependencyKey] = []

    func getInstance<T>(key: AnyDependencyKey, scope: Scope) async -> T? {
        switch scope {
        case .container:
            return containerCache[key]?.value as? T
        case .cached:
            if let cached = await Self.taskCache.getInstance(forKey: key) {
                return cached.value as? T
            }
            return nil
        case .transient:
            return nil
        }
    }
    
    func storeInstance<T>(key: AnyDependencyKey, value: T, scope: Scope) async {
        let cachedInstance = CachedInstance(value: value, scope: scope)
        switch scope {
        case .container:
            if containerCache[key] == nil {
                containerCreationOrder.append(key)
            }
            containerCache[key] = cachedInstance
        case .cached:
            await Self.taskCache.setInstance(cachedInstance, forKey: key)
        case .transient:
            break
        }
    }
    
    func clearScope(_ scope: Scope) async {
        switch scope {
        case .container:
            containerCreationOrder.reversed().forEach { key in
                if let instance = containerCache[key] {
                    performCleanup(for: instance.value)
                }
            }
            containerCache.removeAll()
            containerCreationOrder.removeAll()
        case .cached:
            await Self.taskCache.removeAll()
        case .transient:
            break
        }
    }
    
    func clearAll() async {
        await clearScope(.container)
        await clearScope(.cached)
    }

    private func performCleanup(for instance: Any) {
        if let disposable = instance as? Disposable {
            disposable.dispose()
        }
    }
    
    func getDebugInfo() async -> ScopeDebugInfo {
        ScopeDebugInfo(
            containerScopeCount: containerCache.count,
            cachedCount: await Self.taskCache.count(),
            containerCreationOrder: containerCreationOrder.map { $0.description }
        )
    }
}



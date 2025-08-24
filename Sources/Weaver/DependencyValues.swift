// Sources/Weaver/DependencyValues.swift
import Foundation

/// 정적 키(=타입) 기반 의존성 컨테이너
public struct DependencyValues: Sendable {
    private var storage: [ObjectIdentifier: AnySendableBox] = [:]

    public init() {}

    public subscript<K: DependencyKey>(_ key: K.Type) -> K.Value {
        get {
            let id = ObjectIdentifier(K.self)
            if let v = storage[id]?.value as? K.Value { return v }
            return K.liveValue
        }
        set {
            let id = ObjectIdentifier(K.self)
            storage[id] = AnySendableBox(newValue)
        }
    }
}

// 타입 소거용(보관용)
private struct AnySendableBox: @unchecked Sendable {
    let value: Any
    init(_ value: Any) { self.value = value }
}


// MARK: - Dependency Context Store

public actor DependencyContextStore {
    public static let shared = DependencyContextStore()
    private var current: DependencyContext = .live

    private init() {}

    public func get() -> DependencyContext { current }
    public func set(_ value: DependencyContext) { current = value }
}

public extension DependencyValues {
    static var currentContext: DependencyContext {
        get async { await DependencyContextStore.shared.get() }
    }

    static func setContext(_ context: DependencyContext) {
        Task {
            await DependencyContextStore.shared.set(context)
        }
    }
}
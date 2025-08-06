// Weaver/Sources/Weaver/WeakBox.swift

import Foundation

/// Swift 6 동시성 환경에서 약한 참조를 안전하게 관리하는 단순한 WeakBox 패턴
/// DevPrinciples Article 7 Rule 1: 단일 명확한 책임 - 약한 참조 관리만 담당
public actor WeakBox<T: AnyObject & Sendable>: Sendable {
    
    // MARK: - Properties
    
    private weak var _value: T?
    private let creationTime: CFAbsoluteTime
    private let typeDescription: String
    
    // MARK: - Initialization
    
    public init(_ value: T) {
        self._value = value
        self.creationTime = CFAbsoluteTimeGetCurrent()
        self.typeDescription = String(describing: type(of: value))
    }
    
    // MARK: - Public API
    
    /// 약한 참조가 아직 살아있는지 확인
    public var isAlive: Bool {
        _value != nil
    }
    
    /// 약한 참조 객체 반환 (nil이면 해제됨)
    public func getValue() -> T? {
        _value
    }
    
    /// 생성 이후 경과 시간
    public var age: TimeInterval {
        CFAbsoluteTimeGetCurrent() - creationTime
    }
    
    /// 디버깅을 위한 설명
    public var debugDescription: String {
        let status = isAlive ? "alive" : "deallocated"
        return "\(typeDescription) (\(status), age: \(String(format: "%.2f", age))s)"
    }
}

// MARK: - ==================== WeakBox 컬렉션 관리 ====================

/// WeakBox들을 효율적으로 관리하는 컬렉션
public actor WeakBoxCollection<Key: Hashable, Value: AnyObject & Sendable>: Sendable {
    
    private var boxes: [Key: WeakBox<Value>] = [:]
    
    /// 새로운 WeakBox를 추가하거나 기존 것을 교체
    public func set(_ value: Value, for key: Key) {
        boxes[key] = WeakBox(value)
    }
    
    /// 키에 해당하는 값 반환 (살아있는 경우만)
    public func get(for key: Key) async -> Value? {
        guard let box = boxes[key] else { return nil }
        
        if await box.isAlive {
            return await box.getValue()
        } else {
            // 해제된 참조 자동 정리
            boxes.removeValue(forKey: key)
            return nil
        }
    }
    
    /// 해제된 참조들을 일괄 정리하고 정리된 개수 반환
    public func cleanup() async -> Int {
        var keysToRemove: [Key] = []
        
        for (key, box) in boxes {
            if await !box.isAlive {
                keysToRemove.append(key)
            }
        }
        
        for key in keysToRemove {
            boxes.removeValue(forKey: key)
        }
        
        return keysToRemove.count
    }
    
    /// 현재 상태 메트릭
    public func getMetrics() async -> WeakReferenceMetrics {
        var aliveCount = 0
        let totalCount = boxes.count
        
        for box in boxes.values {
            if await box.isAlive {
                aliveCount += 1
            }
        }
        
        return WeakReferenceMetrics(
            totalWeakReferences: totalCount,
            aliveWeakReferences: aliveCount,
            deallocatedWeakReferences: totalCount - aliveCount
        )
    }
    
    /// 모든 참조 제거
    public func removeAll() {
        boxes.removeAll()
    }
}

// MARK: - ==================== 검증 테스트 ====================

#if DEBUG
/// WeakBox 패턴의 메모리 누수 방지 검증을 위한 테스트 클래스
internal final class TestObject: Sendable {
    let id: String
    
    init(id: String) {
        self.id = id
        print("🟢 TestObject \(id) created")
    }
    
    deinit {
        print("🔴 TestObject \(id) deallocated")
    }
}

/// WeakBox 패턴 검증 함수
public func verifyWeakBoxPattern() async {
    print("🧪 WeakBox 패턴 메모리 누수 검증 시작")
    
    let collection = WeakBoxCollection<String, TestObject>()
    
    // 1. 객체 생성 및 WeakBox에 저장
    do {
        let obj1 = TestObject(id: "test1")
        let obj2 = TestObject(id: "test2")
        
        await collection.set(obj1, for: "key1")
        await collection.set(obj2, for: "key2")
        
        // 객체들이 살아있는지 확인
        let retrieved1 = await collection.get(for: "key1")
        let retrieved2 = await collection.get(for: "key2")
        
        assert(retrieved1?.id == "test1", "WeakBox should return alive object")
        assert(retrieved2?.id == "test2", "WeakBox should return alive object")
        
        print("✅ WeakBox 저장 및 검색 성공")
    }
    
    // 2. 객체들이 스코프를 벗어나면 자동으로 해제되어야 함
    // (위의 do 블록을 벗어나면서 obj1, obj2가 해제됨)
    
    // 3. 약간의 지연 후 정리 작업 수행
    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
    
    let cleanedCount = await collection.cleanup()
    print("🧹 정리된 해제된 참조 개수: \(cleanedCount)")
    
    // 4. 해제된 객체들은 nil을 반환해야 함
    let retrieved1 = await collection.get(for: "key1")
    let retrieved2 = await collection.get(for: "key2")
    
    assert(retrieved1 == nil, "WeakBox should return nil for deallocated object")
    assert(retrieved2 == nil, "WeakBox should return nil for deallocated object")
    
    print("✅ WeakBox 패턴 메모리 누수 방지 검증 완료")
}
#endif
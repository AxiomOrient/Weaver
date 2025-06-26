import Foundation

// MARK: - 팩토리 관리자

/// 비동기 팩토리 실행 및 성능 메트릭 수집을 관리하는 actor
internal actor FactoryManager: Sendable {
    private var factoryMetrics: [AnyDependencyKey: FactoryMetrics] = [:]
    
    func executeFactory<T>(
        key: AnyDependencyKey,
        factory: @Sendable () async throws -> Any,
        keyName: String
    ) async throws -> T {
        let startTime = Date()
        
        do {
            let result = try await factory()
            guard let typedResult = result as? T else {
                throw CastingError("Factory for \(keyName) produced wrong type: expected \(T.self), got \(type(of: result))")
            }
            
            let executionTime = Date().timeIntervalSince(startTime)
            recordMetrics(key: key, executionTime: executionTime, success: true)
            
            return typedResult
        } catch {
            let executionTime = Date().timeIntervalSince(startTime)
            recordMetrics(key: key, executionTime: executionTime, success: false)
            throw error
        }
    }
    
    private func recordMetrics(key: AnyDependencyKey, executionTime: TimeInterval, success: Bool) {
        let metrics = factoryMetrics[key] ?? FactoryMetrics(keyName: key.description)
        factoryMetrics[key] = metrics.update(executionTime: executionTime, success: success)
    }

    func getAllMetrics() -> [AnyDependencyKey: FactoryMetrics] {
        return factoryMetrics
    }
    
    func clearMetrics() {
        factoryMetrics.removeAll()
    }
}

// MARK: - 팩토리 메트릭

/// 팩토리 실행 성능을 추적하는 구조체
internal struct FactoryMetrics: Sendable {
    let keyName: String
    let totalExecutions: Int
    let successfulExecutions: Int
    let averageExecutionTime: TimeInterval
    let lastExecutionTime: Date
    let fastestExecution: TimeInterval
    let slowestExecution: TimeInterval

    init(keyName: String) {
        self.keyName = keyName
        self.totalExecutions = 0
        self.successfulExecutions = 0
        self.averageExecutionTime = 0
        self.lastExecutionTime = Date.distantPast
        self.fastestExecution = .infinity
        self.slowestExecution = 0
    }

    private init(keyName: String, totalExecutions: Int, successfulExecutions: Int, averageExecutionTime: TimeInterval, lastExecutionTime: Date, fastestExecution: TimeInterval, slowestExecution: TimeInterval) {
        self.keyName = keyName
        self.totalExecutions = totalExecutions
        self.successfulExecutions = successfulExecutions
        self.averageExecutionTime = averageExecutionTime
        self.lastExecutionTime = lastExecutionTime
        self.fastestExecution = fastestExecution
        self.slowestExecution = slowestExecution
    }
    
    func update(executionTime: TimeInterval, success: Bool) -> FactoryMetrics {
        let newTotal = totalExecutions + 1
        let newSuccess = success ? successfulExecutions + 1 : successfulExecutions
        let newAverageTime = (averageExecutionTime * Double(totalExecutions) + executionTime) / Double(newTotal)
        
        return FactoryMetrics(
            keyName: keyName,
            totalExecutions: newTotal,
            successfulExecutions: newSuccess,
            averageExecutionTime: newAverageTime,
            lastExecutionTime: Date(),
            fastestExecution: min(fastestExecution, executionTime),
            slowestExecution: max(slowestExecution, executionTime)
        )
    }
}



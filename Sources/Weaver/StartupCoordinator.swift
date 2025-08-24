// Weaver/Sources/Weaver/StartupCoordinator.swift

import Foundation
import os

// MARK: - Time Utilities (ContinuousClock)
@inline(__always)
private func _seconds(_ d: Duration) -> TimeInterval {
    let comps = d.components
    return Double(comps.seconds) + Double(comps.attoseconds) / 1_000_000_000_000_000_000.0
}

// MARK: - ==================== 병렬 Startup 초기화 코디네이터 ====================
//
// 핵심 설계 원칙:
// 1. 의존성 그래프 기반 병렬 초기화로 앱 시작 시간 단축
// 2. TaskGroup을 사용한 안전한 동시성 제어
// 3. 의존성 순서를 보장하면서 독립적인 서비스는 병렬 처리
// 4. 상세한 성능 메트릭과 로깅으로 최적화 지원

/// Startup 스코프 서비스들의 병렬 초기화를 담당하는 코디네이터입니다.
/// 의존성 그래프를 분석하여 독립적인 서비스 그룹을 식별하고, 그룹 단위로 병렬 초기화를 수행합니다.
public actor StartupCoordinator {
    
    // MARK: - Types
    
    /// 초기화 계층을 나타내는 구조체입니다.
    /// 같은 계층의 서비스들은 서로 독립적이므로 병렬로 초기화할 수 있습니다.
    public struct InitializationLayer: Sendable {
        let services: Set<AnyDependencyKey>
        let layerIndex: Int
        
        public init(services: Set<AnyDependencyKey>, layerIndex: Int) {
            self.services = services
            self.layerIndex = layerIndex
        }
    }
    
    /// 병렬 초기화 결과를 나타내는 열거형입니다.
    public enum ParallelInitializationResult: Sendable {
        case success(metrics: InitializationMetrics)
        case partialFailure(successful: [AnyDependencyKey], failed: [AnyDependencyKey: Error], metrics: InitializationMetrics)
        case failure(error: Error, metrics: InitializationMetrics)
    }
    
    /// 초기화 성능 메트릭을 담는 구조체입니다.
    public struct InitializationMetrics: Sendable {
        let totalStartupTime: TimeInterval
        let serializedTime: TimeInterval  // 순차 실행 시 예상 시간
        let layerTimes: [Int: TimeInterval]
        let serviceInitializationTimes: [String: TimeInterval]
        let parallelizationEfficiency: Double  // 병렬화 효과 (0.0 ~ 1.0)
        let servicesCount: Int
        let layersCount: Int
        
        public init(
            totalStartupTime: TimeInterval,
            serializedTime: TimeInterval,
            layerTimes: [Int: TimeInterval],
            serviceInitializationTimes: [String: TimeInterval],
            parallelizationEfficiency: Double,
            servicesCount: Int,
            layersCount: Int
        ) {
            self.totalStartupTime = totalStartupTime
            self.serializedTime = serializedTime
            self.layerTimes = layerTimes
            self.serviceInitializationTimes = serviceInitializationTimes
            self.parallelizationEfficiency = parallelizationEfficiency
            self.servicesCount = servicesCount
            self.layersCount = layersCount
        }
    }
    
    // MARK: - Properties
    
    private let logger: WeaverLogger
    private let maxConcurrentInitializations: Int
    
    // MARK: - Initialization
    
    public init(
        logger: WeaverLogger = DefaultLogger(),
        maxConcurrentInitializations: Int = min(ProcessInfo.processInfo.activeProcessorCount, 8)
    ) {
        self.logger = logger
        self.maxConcurrentInitializations = maxConcurrentInitializations
    }
    
    // MARK: - Public Methods
    
    /// startup 스코프의 서비스들을 병렬로 초기화합니다.
    /// - Parameters:
    ///   - registrations: startup 스코프의 의존성 등록 정보
    ///   - container: 초기화를 실행할 컨테이너
    ///   - progressHandler: 초기화 진행률을 전달받는 클로저 (0.0 ~ 1.0)
    /// - Returns: 병렬 초기화 결과와 성능 메트릭
    public func initializeStartupServices(
        registrations: [AnyDependencyKey: DependencyRegistration],
        container: WeaverContainer,
        progressHandler: ( @Sendable (Double) -> Void)? = nil
    ) async -> ParallelInitializationResult {
        let clock = ContinuousClock()
        let startTime = clock.now
        let onProgress: @Sendable (Double) -> Void = progressHandler ?? { (_: Double) in }
        
        await logger.log(
            message: "🚀 병렬 startup 초기화 시작 - 서비스 \(registrations.count)개", 
            level: .info
        )
        
        do {
            // 1. 의존성 계층 분석
            let layers = await analyzeDependencyLayers(registrations: registrations)
            
            await logger.log(
                message: "📊 의존성 계층 분석 완료 - \(layers.count)개 계층으로 분할", 
                level: .debug
            )
            
            // 2. 계층별 병렬 초기화 실행
            let (serviceInitializationTimes, layerTimes) = try await initializeLayers(
                layers: layers,
                container: container,
                progressHandler: onProgress
            )
            
            let endTime = clock.now
            let totalTime = _seconds(endTime - startTime)
            let serializedTime = serviceInitializationTimes.values.reduce(0, +)
            let efficiency = calculateParallelizationEfficiency(
                totalTime: totalTime,
                serializedTime: serializedTime
            )
            
            let metrics = InitializationMetrics(
                totalStartupTime: totalTime,
                serializedTime: serializedTime,
                layerTimes: layerTimes,
                serviceInitializationTimes: serviceInitializationTimes,
                parallelizationEfficiency: efficiency,
                servicesCount: registrations.count,
                layersCount: layers.count
            )
            
            await logger.log(
                message: "✅ 병렬 startup 초기화 완료 - \(String(format: "%.2f", totalTime * 1000))ms (효율성: \(String(format: "%.1f", efficiency * 100))%)", 
                level: .info
            )
            
            return .success(metrics: metrics)
            
        } catch let startupError as StartupCoordinatorError {
            let endTime = clock.now
            let totalTime = _seconds(endTime - startTime)
            
            let metrics = InitializationMetrics(
                totalStartupTime: totalTime,
                serializedTime: 0,
                layerTimes: [:],
                serviceInitializationTimes: [:],
                parallelizationEfficiency: 0,
                servicesCount: registrations.count,
                layersCount: 0
            )
            
            switch startupError {
            case .partialInitializationFailure(let successful, let failed):
                await logger.log(message: "Startup partially failed. success=\(successful.count), failed=\(failed.count)", level: .default)
                return .partialFailure(successful: Array(successful), failed: failed, metrics: metrics)
            case .coordinatorDeallocated:
                await logger.log(message: "Startup coordinator deallocated during initialization", level: .error)
                return .failure(error: startupError, metrics: metrics)
            }
        } catch {
            let endTime = clock.now
            let totalTime = _seconds(endTime - startTime)
            
            let metrics = InitializationMetrics(
                totalStartupTime: totalTime,
                serializedTime: 0,
                layerTimes: [:],
                serviceInitializationTimes: [:],
                parallelizationEfficiency: 0,
                servicesCount: registrations.count,
                layersCount: 0
            )
            
            await logger.log(
                message: "🚨 병렬 startup 초기화 실패: \(error.localizedDescription)", 
                level: .error
            )
            return .failure(error: error, metrics: metrics)
        }
    }
    
    // MARK: - Private Methods
    
    /// 의존성 그래프를 분석하여 초기화 계층을 생성합니다.
    private func analyzeDependencyLayers(
        registrations: [AnyDependencyKey: DependencyRegistration]
    ) async -> [InitializationLayer] {
        // startup 스코프만 필터링
        let startupRegistrations = registrations.filter { _, registration in
            registration.scope == .startup
        }
        
        guard !startupRegistrations.isEmpty else {
            return []
        }
        
        // 의존성 그래프 생성
        let graph = DependencyGraph(registrations: startupRegistrations)
        let dependencyLayers = graph.calculateInitializationLayers()
        
        return dependencyLayers.enumerated().map { index, services in
            InitializationLayer(services: services, layerIndex: index)
        }
    }
    
    /// 계층별로 서비스를 병렬 초기화합니다.
    private func initializeLayers(
        layers: [InitializationLayer],
        container: WeaverContainer,
        progressHandler: @Sendable @escaping (Double) -> Void
    ) async throws -> ([String: TimeInterval], [Int: TimeInterval]) {
        var serviceInitializationTimes: [String: TimeInterval] = [:]
        var layerTimes: [Int: TimeInterval] = [:]
        var successfulServices: Set<AnyDependencyKey> = []
        var failedServices: [AnyDependencyKey: Error] = [:]
        
        let totalServices = layers.reduce(0) { $0 + $1.services.count }
        var completedServices = 0
        
        for layer in layers {
            let clock = ContinuousClock()
            let layerStartTime = clock.now
            
            await logger.log(
                message: "🔄 계층 \(layer.layerIndex) 초기화 시작 - \(layer.services.count)개 서비스 병렬 처리", 
                level: .debug
            )
            
            // TaskGroup을 사용한 병렬 초기화
            let layerResults = await withTaskGroup(
                of: (AnyDependencyKey, Result<TimeInterval, Error>).self,
                returning: [(AnyDependencyKey, Result<TimeInterval, Error>)].self
            ) { group in
                // 동시 실행 수 제한
                let concurrentCount = min(layer.services.count, maxConcurrentInitializations)
                let services = Array(layer.services)
                
                // 첫 번째 배치 시작
                for i in 0..<min(concurrentCount, services.count) {
                    let service = services[i]
                    group.addTask { [weak self] in
                        guard let self = self else {
                            return (service, .failure(StartupCoordinatorError.coordinatorDeallocated))
                        }
                        
                        let result = await self.initializeSingleService(service, container: container)
                        return (service, result)
                    }
                }
                
                var results: [(AnyDependencyKey, Result<TimeInterval, Error>)] = []
                var nextServiceIndex = concurrentCount
                
                // 결과를 수집하면서 남은 서비스들을 순차적으로 추가
                for await (service, result) in group {
                    results.append((service, result))
                    
                    // 다음 서비스가 있으면 새로운 Task 추가
                    if nextServiceIndex < services.count {
                        let nextService = services[nextServiceIndex]
                        nextServiceIndex += 1
                        
                        group.addTask { [weak self] in
                            guard let self = self else {
                                return (nextService, .failure(StartupCoordinatorError.coordinatorDeallocated))
                            }
                            
                            let result = await self.initializeSingleService(nextService, container: container)
                            return (nextService, result)
                        }
                    }
                }
                
                return results
            }
            
            // 계층 결과 처리
            for (service, result) in layerResults {
                switch result {
                case .success(let initTime):
                    successfulServices.insert(service)
                    serviceInitializationTimes[service.description] = initTime
                    completedServices += 1
                case .failure(let error):
                    failedServices[service] = error
                    await logger.log(
                        message: "❌ 서비스 초기화 실패: \(service.description) - \(error.localizedDescription)", 
                        level: .error
                    )
                }
                
                // 진행률 업데이트
                let progress = Double(completedServices) / Double(totalServices)
                progressHandler(progress)
            }
            
            let layerEndTime = clock.now
            let layerTime = _seconds(layerEndTime - layerStartTime)
            layerTimes[layer.layerIndex] = layerTime
            
            await logger.log(
                message: "✅ 계층 \(layer.layerIndex) 완료 - \(String(format: "%.2f", layerTime * 1000))ms", 
                level: .debug
            )
        }
        
        // 실패한 서비스가 있으면 부분 실패로 처리
        if !failedServices.isEmpty {
            throw StartupCoordinatorError.partialInitializationFailure(
                successful: successfulServices, 
                failed: failedServices
            )
        }
        
        return (serviceInitializationTimes, layerTimes)
    }
    
    /// 단일 서비스를 초기화합니다.
    private func initializeSingleService(
        _ service: AnyDependencyKey,
        container: WeaverContainer
    ) async -> Result<TimeInterval, Error> {
        let clock = ContinuousClock()
        let startTime = clock.now
        
        do {
            // 실제 의존성 해결을 통해 초기화 트리거 (반환값 필요 없음)
            try await container.resolveAny(service)
            
            let endTime = clock.now
            let initTime = _seconds(endTime - startTime)
            
            await logger.log(
                message: "✅ 서비스 초기화 완료: \(service.description) (\(String(format: "%.2f", initTime * 1000))ms)", 
                level: .debug
            )
            
            return .success(initTime)
        } catch {
            let endTime = clock.now
            let initTime = _seconds(endTime - startTime)
            
            await logger.log(
                message: "❌ 서비스 초기화 실패: \(service.description) - \(error.localizedDescription) (\(String(format: "%.2f", initTime * 1000))ms)", 
                level: .error
            )
            
            return .failure(error)
        }
    }
    
    /// 병렬화 효율성을 계산합니다.
    private func calculateParallelizationEfficiency(totalTime: TimeInterval, serializedTime: TimeInterval) -> Double {
        guard serializedTime > 0 else { return 1.0 }
        
        let speedup = serializedTime / totalTime
        let maxSpeedup = Double(maxConcurrentInitializations)
        
        // 효율성 = 실제 속도향상 / 최대 가능한 속도향상
        return min(speedup / maxSpeedup, 1.0)
    }
}

// MARK: - ==================== StartupCoordinator Errors ====================

/// StartupCoordinator에서 발생할 수 있는 에러를 정의합니다.
public enum StartupCoordinatorError: Error, Sendable {
    case partialInitializationFailure(successful: Set<AnyDependencyKey>, failed: [AnyDependencyKey: Error])
    case coordinatorDeallocated
}

extension StartupCoordinatorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .partialInitializationFailure(let successful, let failed):
            return "일부 서비스 초기화 실패 - 성공: \(successful.count)개, 실패: \(failed.count)개"
        case .coordinatorDeallocated:
            return "StartupCoordinator가 해제되어 초기화를 완료할 수 없습니다"
        }
    }
}

// 🔥 REMOVE: calculateInitializationLayers()는 DependencyGraph 쪽 단일 소스 유지
// (필요 시 Coordinator에서 graph.calculateInitializationLayers() 호출로 위임)

// MARK: - ==================== WeaverContainer Extensions ====================

// WeaverContainer의 resolveAny 메서드는 이미 구현되어 있습니다.
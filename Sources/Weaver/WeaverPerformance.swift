// Weaver/Sources/Weaver/WeaverPerformance.swift

import Foundation
import os

// MARK: - ==================== Performance Monitoring ====================

/// Weaver DI 시스템의 성능을 모니터링하고 최적화하는 액터입니다.
/// DevPrinciples Article 5에 따라 측정 가능한 성능 요구사항이 있을 때만 최적화를 수행합니다.
public actor WeaverPerformanceMonitor {

  // MARK: - Metrics

  private var resolutionTimes: [TimeInterval] = []
  private var slowResolutions: [(keyName: String, duration: TimeInterval)] = []
  private var memoryUsage: [UInt64] = []
  private let slowResolutionThreshold: TimeInterval = 0.1  // 100ms

  // MARK: - Configuration

  private let isEnabled: Bool
  private let logger: WeaverLogger

  public init(
    enabled: Bool = WeaverEnvironment.isDevelopment, logger: WeaverLogger = DefaultLogger()
  ) {
    self.isEnabled = enabled
    self.logger = logger
  }

  // MARK: - Public API

  /// 의존성 해결 성능을 측정합니다.
  public func measureResolution<T: Sendable>(
    keyName: String,
    operation: @Sendable () async throws -> T
  ) async rethrows -> T {
    guard isEnabled else {
      return try await operation()
    }

    // 🚀 [IMPROVED] 고정밀 시간 측정
    let startTime = DispatchTime.now()
    let result = try await operation()
    let endTime = DispatchTime.now()
    
    let duration = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000.0

    await recordResolution(keyName: keyName, duration: duration)
    return result
  }

  /// 메모리 사용량을 기록합니다.
  public func recordMemoryUsage() async {
    guard isEnabled else { return }

    var memoryInfo = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

    let result = withUnsafeMutablePointer(to: &memoryInfo) {
      $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }

    if result == KERN_SUCCESS {
      let memoryUsageBytes = UInt64(memoryInfo.resident_size)
      memoryUsage.append(memoryUsageBytes)

      // 메모리 사용량이 임계치를 초과하면 경고
      let memoryUsageMB = memoryUsageBytes / (1024 * 1024)
      if memoryUsageMB > 100 {  // 100MB 임계치
        await logger.log(
          message: "⚠️ 높은 메모리 사용량 감지: \(memoryUsageMB)MB",
          level: .info
        )
      }
    }
  }

  /// 성능 보고서를 생성합니다.
  public func generatePerformanceReport() async -> PerformanceReport {
    guard isEnabled else {
      return PerformanceReport(
        averageResolutionTime: 0,
        slowResolutions: [],
        totalResolutions: 0,
        averageMemoryUsage: 0,
        peakMemoryUsage: 0
      )
    }

    let averageResolutionTime =
      resolutionTimes.isEmpty ? 0 : resolutionTimes.reduce(0, +) / Double(resolutionTimes.count)
    let averageMemoryUsage =
      memoryUsage.isEmpty ? 0 : memoryUsage.reduce(0, +) / UInt64(memoryUsage.count)
    let peakMemoryUsage = memoryUsage.max() ?? 0

    return PerformanceReport(
      averageResolutionTime: averageResolutionTime,
      slowResolutions: slowResolutions,
      totalResolutions: resolutionTimes.count,
      averageMemoryUsage: averageMemoryUsage,
      peakMemoryUsage: peakMemoryUsage
    )
  }

  /// 성능 데이터를 초기화합니다.
  public func reset() async {
    resolutionTimes.removeAll()
    slowResolutions.removeAll()
    memoryUsage.removeAll()
  }

  // MARK: - Private Implementation

  private func recordResolution(keyName: String, duration: TimeInterval) async {
    resolutionTimes.append(duration)

    if duration > slowResolutionThreshold {
      slowResolutions.append((keyName: keyName, duration: duration))
      await logger.log(
        message: "🐌 느린 의존성 해결 감지: '\(keyName)' (\(String(format: "%.3f", duration * 1000))ms)",
        level: .info
      )
    }

    // 메모리 사용량도 함께 기록
    await recordMemoryUsage()
  }
}

// MARK: - ==================== Performance Report ====================

/// 성능 모니터링 결과를 담는 구조체입니다.
public struct PerformanceReport: Sendable, CustomStringConvertible {
  public let averageResolutionTime: TimeInterval
  public let slowResolutions: [(keyName: String, duration: TimeInterval)]
  public let totalResolutions: Int
  public let averageMemoryUsage: UInt64
  public let peakMemoryUsage: UInt64

  public var description: String {
    let avgTimeMs = averageResolutionTime * 1000
    let avgMemoryMB = averageMemoryUsage / (1024 * 1024)
    let peakMemoryMB = peakMemoryUsage / (1024 * 1024)

    var report = """
      📊 Weaver Performance Report
      ═══════════════════════════════
      📈 Resolution Performance:
      - Total Resolutions: \(totalResolutions)
      - Average Time: \(String(format: "%.3f", avgTimeMs))ms
      - Slow Resolutions: \(slowResolutions.count)

      💾 Memory Usage:
      - Average: \(avgMemoryMB)MB
      - Peak: \(peakMemoryMB)MB
      """

    if !slowResolutions.isEmpty {
      report += "\n\n🐌 Slow Resolutions:"
      for (keyName, duration) in slowResolutions.prefix(5) {
        let durationMs = duration * 1000
        report += "\n- \(keyName): \(String(format: "%.3f", durationMs))ms"
      }

      if slowResolutions.count > 5 {
        report += "\n- ... and \(slowResolutions.count - 5) more"
      }
    }

    return report
  }
}

// MARK: - ==================== Performance Extensions ====================

/// WeaverContainer에 성능 모니터링 기능을 추가하는 확장입니다.
extension WeaverContainer {
  /// 성능 모니터링과 함께 의존성을 해결합니다.
  public func resolveWithPerformanceMonitoring<Key: DependencyKey>(
    _ keyType: Key.Type,
    monitor: WeaverPerformanceMonitor
  ) async throws -> Key.Value {
    return try await monitor.measureResolution(keyName: String(describing: keyType)) {
      try await self.resolve(keyType)
    }
  }
}

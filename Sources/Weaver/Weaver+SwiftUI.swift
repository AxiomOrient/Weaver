// Weaver/Sources/Weaver/Weaver+SwiftUI.swift

#if canImport(SwiftUI)
import SwiftUI
import Foundation

// MARK: - ==================== SwiftUI Integration ====================

/// SwiftUI와 Weaver DI의 완벽한 통합을 위한 View Modifier입니다.
/// 앱 생명주기와 View 생명주기를 동기화하여 안전한 의존성 해결을 보장합니다.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct WeaverViewModifier: ViewModifier {
    private let modules: [Module]
    private let setAsGlobal: Bool
    private let loadingView: AnyView?
    
    @State private var containerState: ContainerState = .loading
    @State private var container: WeaverContainer?
    
    private enum ContainerState {
        case loading
        case ready(WeaverContainer)
        case failed(Error)
    }
    
    public init(
        modules: [Module],
        setAsGlobal: Bool = true,
        loadingView: AnyView? = nil
    ) {
        self.modules = modules
        self.setAsGlobal = setAsGlobal
        self.loadingView = loadingView
    }
    
    public func body(content: Content) -> some View {
        Group {
            switch containerState {
            case .loading:
                loadingView ?? AnyView(
                    VStack {
                        ProgressView()
                        Text("의존성 준비 중...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                )
            case .ready(let container):
                content
                    .task {
                        // SwiftUI View 생명주기와 동기화
                        await Weaver.withScope(container) {
                            // View가 활성화된 동안 스코프 유지
                        }
                    }
            case .failed(let error):
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text("의존성 초기화 실패")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .task {
            await initializeContainer()
        }
        .onDisappear {
            // View가 사라질 때 정리 작업
            Task {
                if !setAsGlobal, let container = container {
                    await container.shutdown()
                }
            }
        }
    }
    
    private func initializeContainer() async {
        do {
            let builder = WeaverContainer.builder()
            for module in modules {
                await module.configure(builder)
            }
            
            let newContainer = try await builder.build()
            
            if setAsGlobal {
                // 전역 커널로 설정
                let kernel = WeaverKernel(modules: modules)
                await Weaver.setGlobalKernel(kernel)
                try await kernel.build()
                // 🚀 Swift 6 방식: 안전한 타임아웃 기반 준비 대기
                _ = try await kernel.ensureReady()
            }
            
            await MainActor.run {
                self.container = newContainer
                self.containerState = .ready(newContainer)
            }
        } catch {
            await MainActor.run {
                self.containerState = .failed(error)
            }
        }
    }
}

/// SwiftUI View에 Weaver DI 컨테이너를 통합하는 편의 확장입니다.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public extension View {
    /// View에 Weaver DI 컨테이너를 연결합니다.
    /// - Parameters:
    ///   - modules: 등록할 모듈 배열
    ///   - setAsGlobal: 전역 커널로 설정할지 여부 (기본값: true)
    ///   - loadingView: 로딩 중 표시할 커스텀 뷰
    /// - Returns: DI가 통합된 View
    func weaver(
        modules: [Module],
        setAsGlobal: Bool = true,
        @ViewBuilder loadingView: @escaping () -> some View = {
            VStack {
                ProgressView()
                Text("의존성 준비 중...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    ) -> some View {
        self.modifier(
            WeaverViewModifier(
                modules: modules,
                setAsGlobal: setAsGlobal,
                loadingView: AnyView(loadingView())
            )
        )
    }
}

// MARK: - ==================== SwiftUI Preview Support ====================

/// SwiftUI Preview 환경에서 안전한 DI 컨테이너를 제공하는 헬퍼입니다.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct PreviewWeaverContainer {
    /// Preview 전용 모듈을 생성합니다.
    /// 모든 의존성이 기본값이나 Mock 객체로 등록됩니다.
    public static func previewModule<Key: DependencyKey>(
        _ keyType: Key.Type,
        mockValue: Key.Value
    ) -> Module {
        return AnonymousModule { builder in
            await builder.register(keyType) { _ in mockValue }
        }
    }
    
    /// 여러 Preview 의존성을 한 번에 등록하는 편의 메서드입니다.
    /// 타입 안전성을 보장하면서 동적으로 의존성을 등록합니다.
    public static func previewModules(_ registrations: PreviewRegistration...) -> [Module] {
        return registrations.map { registration in
            AnonymousModule { builder in
                await registration.configure(builder)
            }
        }
    }
    
    /// 타입 안전한 Preview 등록을 위한 헬퍼 구조체
    public struct PreviewRegistration: Sendable {
        private let registerBlock: @Sendable (WeaverBuilder) async -> Void
        
        /// 타입 안전한 Preview 등록을 생성합니다.
        public static func register<Key: DependencyKey>(
            _ keyType: Key.Type,
            mockValue: Key.Value,
            scope: Scope = .shared
        ) -> PreviewRegistration {
            return PreviewRegistration { builder in
                await builder.register(keyType, scope: scope) { _ in mockValue }
            }
        }
        
        /// 팩토리 기반 Preview 등록을 생성합니다.
        public static func register<Key: DependencyKey>(
            _ keyType: Key.Type,
            scope: Scope = .shared,
            factory: @escaping @Sendable (Resolver) async throws -> Key.Value
        ) -> PreviewRegistration {
            return PreviewRegistration { builder in
                await builder.register(keyType, scope: scope, factory: factory)
            }
        }
        
        internal func configure(_ builder: WeaverBuilder) async {
            await registerBlock(builder)
        }
    }
}

// MARK: - ==================== Anonymous Module Helper ====================

/// 간단한 의존성 등록을 위한 익명 모듈입니다.
public struct AnonymousModule: Module {
    private let configureBlock: @Sendable (WeaverBuilder) async -> Void
    
    public init(configure: @escaping @Sendable (WeaverBuilder) async -> Void) {
        self.configureBlock = configure
    }
    
    public func configure(_ builder: WeaverBuilder) async {
        await configureBlock(builder)
    }
}

#endif
// MARK: - ==================== Preview Usage Examples ====================

#if DEBUG
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public extension PreviewWeaverContainer {
    /// 일반적인 Preview 시나리오를 위한 편의 메서드들
    
    /// 네트워크 서비스 Mock을 생성합니다.
    static func mockNetworkService(baseURL: String = "https://preview.api.com") -> PreviewRegistration {
        return .register(NetworkServiceKey.self) { _ in
            MockNetworkService(baseURL: baseURL)
        }
    }
    
    /// 데이터베이스 서비스 Mock을 생성합니다.
    static func mockDatabaseService(connectionString: String = "preview://memory") -> PreviewRegistration {
        return .register(DatabaseServiceKey.self) { _ in
            MockDatabaseService(connectionString: connectionString)
        }
    }
    
    /// 로거 서비스 Mock을 생성합니다.
    static func mockLoggerService(level: MockLoggerService.LogLevel = .debug) -> PreviewRegistration {
        return .register(LoggerServiceKey.self) { _ in
            MockLoggerService(level: level)
        }
    }
}

// MARK: - Mock Services for Preview

/// Preview용 Mock 네트워크 서비스
public final class MockNetworkService: Sendable {
    public let baseURL: String
    public let id = UUID()
    
    public init(baseURL: String) {
        self.baseURL = baseURL
    }
    
    public func fetchData(endpoint: String) async -> String {
        return "mock_data_from_\(endpoint)"
    }
}

/// Preview용 Mock 데이터베이스 서비스
public final class MockDatabaseService: Sendable {
    public let connectionString: String
    public let id = UUID()
    
    public init(connectionString: String) {
        self.connectionString = connectionString
    }
    
    public func query(_ sql: String) async -> [String] {
        return ["mock_result_1", "mock_result_2"]
    }
}

/// Preview용 Mock 로거 서비스
public final class MockLoggerService: Sendable {
    public let level: LogLevel
    public let id = UUID()
    
    public enum LogLevel: String, Sendable {
        case debug, info, warning, error
    }
    
    public init(level: LogLevel) {
        self.level = level
    }
    
    public func log(_ message: String, level: LogLevel = .info) {
        print("[PREVIEW-\(level.rawValue.uppercased())] \(message)")
    }
}

// MARK: - Mock Dependency Keys

public struct NetworkServiceKey: DependencyKey {
    public static var defaultValue: MockNetworkService { 
        MockNetworkService(baseURL: "https://default.com") 
    }
}

public struct DatabaseServiceKey: DependencyKey {
    public static var defaultValue: MockDatabaseService { 
        MockDatabaseService(connectionString: "default://localhost") 
    }
}

public struct LoggerServiceKey: DependencyKey {
    public static var defaultValue: MockLoggerService { 
        MockLoggerService(level: .info) 
    }
}

#endif
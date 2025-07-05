// Weaver/Sources/Weaver/SwiftUI/WeaverSwiftUI.swift

import SwiftUI

// MARK: - ==================== Public APIs for SwiftUI ====================

/// SwiftUI 뷰 계층으로 의존성 해결사(`Resolver`)를 전달하기 위한 EnvironmentKey입니다.
public struct WeaverResolverKey: EnvironmentKey {
    /// 실제 컨테이너가 준비되기 전까지 안전망 역할을 하는 `PlaceholderResolver`를 기본값으로 가집니다.
    /// 이를 통해 컨테이너 로딩 중에도 뷰의 렌더링이 중단되지 않습니다.
    public static let defaultValue: any Resolver = PlaceholderResolver()
}

extension EnvironmentValues {
    /// SwiftUI 뷰에서 `Environment`를 통해 현재 범위의 `Resolver`에 접근할 때 사용합니다.
    ///
    /// 예시:
    /// ```
    /// @Environment(\.weaverResolver) private var resolver
    /// ```
    public var weaverResolver: any Resolver {
        get { self[WeaverResolverKey.self] }
        set { self[WeaverResolverKey.self] = newValue }
    }
}

extension View {
    /// SwiftUI 뷰 계층에 Weaver DI 컨테이너를 설정하고 주입하는 ViewModifier입니다.
    ///
    /// 이 수정자를 적용하면 뷰는 컨테이너가 비동기적으로 빌드되는 동안 로딩 뷰를 표시하고,
    /// 빌드가 완료되면 실제 DI 컨테이너를 환경(`Environment`)에 주입하여 모든 하위 뷰들이 의존성을 사용할 수 있게 합니다.
    ///
    /// - Parameters:
    ///   - modules: 컨테이너에 등록할 `Module`의 배열입니다.
    ///   - loadingView: DI 컨테이너가 빌드되는 동안 표시될 뷰입니다.
    /// - Returns: DI 컨테이너가 설정된 뷰를 반환합니다.
    public func weaver<LoadingView: View>(
        modules: [Module],
        @ViewBuilder loadingView: @escaping () -> LoadingView = { ProgressView() }
    ) -> some View {
        // 커널을 생성하고, 이를 관리할 어댑터를 ViewModifier에 주입합니다.
        let kernel = DefaultWeaverKernel(modules: modules)
        let adapter = WeaverSwiftUIAdapter(kernel: kernel)
        return modifier(WeaverSetupModifier(adapter: adapter, loadingView: loadingView))
    }
}

/// Weaver DI 컨테이너를 호스팅하고, 준비 상태에 따라 콘텐츠 뷰를 빌드하는 컨테이너 뷰입니다.
///
/// 앱의 최상위 뷰(`@main`이 있는 `App` 구조체)에서 화면 전체에 걸쳐 DI 컨테이너를 제공할 때 유용합니다.
/// `.weaver()` 수정자와 유사한 역할을 하지만, 뷰 빌더를 사용하여 더 유연한 구조를 만들 수 있습니다.
public struct WeaverHost<Content: View, LoadingView: View>: View {
    @StateObject private var adapter: WeaverSwiftUIAdapter
    private let loadingView: LoadingView
    private let content: (any Resolver) -> Content

    /// `WeaverHost`를 생성합니다.
    /// - Parameters:
    ///   - modules: 컨테이너에 등록할 `Module`의 배열.
    ///   - loadingView: DI 컨테이너가 빌드되는 동안 표시될 뷰.
    ///   - content: 현재 `Resolver`를 받아 콘텐츠 뷰를 구성하는 클로저.
    public init(
        modules: [Module],
        @ViewBuilder loadingView: () -> LoadingView = { ProgressView() },
        @ViewBuilder content: @escaping (any Resolver) -> Content
    ) {
        let kernel = DefaultWeaverKernel(modules: modules)
        _adapter = StateObject(wrappedValue: WeaverSwiftUIAdapter(kernel: kernel))
        self.loadingView = loadingView()
        self.content = content
    }

    public var body: some View {
        ZStack {
            // 어댑터가 제공하는 resolver를 사용하여 항상 content를 렌더링합니다.
            // 로딩 중에는 PlaceholderResolver가 사용됩니다.
            content(adapter.resolver)
                .environment(\.weaverResolver, adapter.resolver)
            
            // 어댑터의 상태에 따라 로딩 뷰 또는 에러 뷰를 오버레이합니다.
            if adapter.isLoading {
                loadingView
            } else if let error = adapter.error {
                // 기본 에러 뷰 (필요 시 커스텀 가능)
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Initialization Failed")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
                .background(.thinMaterial)
                .cornerRadius(12)
            }
        }
        .task {
            await adapter.start()
        }
    }
}


// MARK: - ==================== Internal Implementations ====================

/// `WeaverKernel`의 `LifecycleState`를 SwiftUI 뷰가 사용하기 쉬운 `@Published` 프로퍼티로 변환하는 어댑터 클래스입니다.
@MainActor
internal final class WeaverSwiftUIAdapter: ObservableObject {
    
    // MARK: - Published Properties
    
    /// 뷰에 제공될 현재 `Resolver`입니다. 로딩 중에는 `PlaceholderResolver`가 사용됩니다.
    @Published private(set) var resolver: any Resolver = PlaceholderResolver()
    
    /// 컨테이너가 빌드 중인지 여부를 나타냅니다. 이 값에 따라 로딩 뷰를 표시할 수 있습니다.
    @Published private(set) var isLoading: Bool = true
    
    /// 빌드 과정에서 발생한 에러입니다. 이 값에 따라 에러 뷰를 표시할 수 있습니다.
    @Published private(set) var error: (any Error & Sendable)?
    
    // MARK: - Private Properties
    
    private let kernel: WeaverKernel
    private var streamTask: Task<Void, Never>?

    // MARK: - Initialization

    internal init(kernel: WeaverKernel) {
        self.kernel = kernel
    }

    deinit {
        streamTask?.cancel()
    }

    // MARK: - Public Methods

    /// 커널 빌드를 시작하고 상태 스트림 구독을 시작합니다.
    func start() async {
        // 이미 스트림 구독이 시작되었다면 중복 실행을 방지합니다.
        guard streamTask == nil else { return }
        
        // Kernel의 상태 스트림을 구독하여 상태가 변할 때마다 @Published 프로퍼티를 업데이트합니다.
        self.streamTask = Task {
            for await state in kernel.stateStream {
                if Task.isCancelled { break }
                update(with: state)
            }
        }
        
        // 백그라운드에서 커널 빌드를 시작합니다.
        await kernel.build()
    }
    
    // MARK: - Private State Update

    /// `LifecycleState`에 따라 SwiftUI 뷰를 위한 상태를 업데이트합니다.
    private func update(with state: LifecycleState) {
        switch state {
        case .idle, .configuring, .warmingUp:
            self.isLoading = true
            self.error = nil
        case .ready(let resolver):
            self.resolver = resolver
            self.isLoading = false
            self.error = nil
        case .failed(let error):
            self.error = error
            self.isLoading = false
        case .shutdown:
            self.resolver = PlaceholderResolver()
            self.isLoading = true
            self.error = nil
        }
    }
}

/// `.weaver()` 수정자의 실제 로직을 구현하는 ViewModifier입니다.
internal struct WeaverSetupModifier<LoadingView: View>: ViewModifier {
    @StateObject private var adapter: WeaverSwiftUIAdapter
    private let loadingView: LoadingView

    internal init(adapter: WeaverSwiftUIAdapter, loadingView: @escaping () -> LoadingView) {
        _adapter = StateObject(wrappedValue: adapter)
        self.loadingView = loadingView()
    }

    internal func body(content: Content) -> some View {
        ZStack {
            content
                .environment(\.weaverResolver, adapter.resolver)
            
            if adapter.isLoading {
                loadingView
            } else if let error = adapter.error {
                // 기본 에러 뷰
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Initialization Failed")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
                .background(.thinMaterial)
                .cornerRadius(12)
            }
        }
        .task {
            await adapter.start()
        }
    }
}


/// DI 설정이 누락되었거나 로딩 중일 때 안전망 역할을 하는 플레이스홀더 리졸버입니다.
private struct PlaceholderResolver: Resolver {
    func resolve<Key: DependencyKey>(_ keyType: Key.Type) async throws -> Key.Value {
        // SwiftUI Preview 환경에서는 크래시 대신 `defaultValue`를 반환하여 Preview를 정상 동작시킵니다.
        if WeaverEnvironment.isPreview {
            return Key.defaultValue
        }
        
        // 실제 앱 환경에서 플레이스홀더의 `resolve`가 호출되면, DI 설정이 누락되었음을 명확히 알려줍니다.
        fatalError("""
        💥 Weaver DI 컨테이너가 준비되지 않았습니다.
        - 앱의 최상위 뷰를 'WeaverHost'로 감쌌거나 '.weaver()' ViewModifier를 올바르게 적용했는지 확인해주세요.
        - 또는, 컨테이너가 아직 비동기적으로 로딩 중일 수 있습니다. 이 경우 `@Inject` 프로퍼티 래퍼는 `DependencyKey`의 `defaultValue`를 반환하며 UI의 초기 상태를 표시합니다.
        - 만약 `try await $injected.resolved`를 사용하여 의존성을 해결하려 했다면, 컨테이너가 준비되기 전에 호출되어 에러가 발생할 수 있습니다.
        """)
    }
}

// Weaver/Sources/Weaver/WeaverKernel.swift

import Foundation

/// `WeaverKernel` 프로토콜의 기본 구현체로, DI 컨테이너의 생명주기를 관리하는 핵심 액터(Actor)입니다.
/// 이 액터는 프레임워크와 독립적으로 동작하여 모든 Swift 환경에서 일관된 방식으로 사용될 수 있습니다.
public actor DefaultWeaverKernel: WeaverKernel {

    // MARK: - Public Properties

    /// 컨테이너의 `LifecycleState` 변화를 실시간으로 구독할 수 있는 비동기 스트림입니다.
    public let stateStream: AsyncStream<LifecycleState>

    // MARK: - Private Properties

    /// `stateStream`으로 상태를 보내는 데 사용되는 Continuation입니다.
    private let stateContinuation: AsyncStream<LifecycleState>.Continuation
    
    /// 의존성 등록 로직을 담고 있는 모듈의 배열입니다.
    private let modules: [Module]
    
    /// 빌드가 완료된 후의 `WeaverContainer` 인스턴스입니다.
    private var container: WeaverContainer?

    /// `build()` 메서드의 중복 실행을 방지하기 위한 `Task`입니다.
    private var buildTask: Task<Void, Never>?

    // MARK: - Initialization

    /// 지정된 모듈들로 `WeaverKernel`을 생성합니다.
    /// - Parameter modules: 의존성 등록을 위한 `Module`의 배열.
    public init(modules: [Module]) {
        self.modules = modules
        
        // AsyncStream과 Continuation을 생성합니다.
        // 버퍼링 정책을 .unbounded로 설정하여 상태 업데이트가 유실되지 않도록 합니다.
        var continuation: AsyncStream<LifecycleState>.Continuation!
        self.stateStream = AsyncStream(bufferingPolicy: .unbounded) {
            continuation = $0
        }
        self.stateContinuation = continuation
        
        // 초기 상태로 `.idle`을 발행합니다.
        self.stateContinuation.yield(.idle)
    }

    // MARK: - Public Methods

    /// 컨테이너 빌드 및 초기화를 시작합니다.
    /// 이 메서드는 여러 번 호출되어도 실제 빌드 프로세스는 단 한 번만 실행됩니다.
    public func build() async {
        if let existingTask = buildTask {
            return await existingTask.value
        }
        
        let newTask = Task {
            await performBuild()
        }
        
        self.buildTask = newTask
        await newTask.value
    }
    
    /// 컨테이너를 안전하게 종료하고 모든 리소스를 해제합니다.
    public func shutdown() async {
        await container?.shutdown()
        self.container = nil
        
        stateContinuation.yield(.shutdown)
        stateContinuation.finish()
    }

    // MARK: - Private Build Logic

    private func performBuild() async {
        do {
            stateContinuation.yield(.configuring)
            
            // 1. 빌더를 생성하고 모듈을 등록합니다.
            let builder = WeaverContainer.builder()
            for module in modules {
                await module.configure(builder)
            }
            
            // 2. 컨테이너를 빌드합니다.
            //    `warmUp` 진행 상태를 콜백으로 받아 스트림에 전달합니다.
            let builtContainer = await builder.build { progress in
                self.stateContinuation.yield(.warmingUp(progress: progress))
            }
            
            self.container = builtContainer
            
            // 3. 모든 준비가 완료되면 `.ready` 상태를 발행합니다.
            stateContinuation.yield(.ready(builtContainer))
            
        } catch {
            // 4. 빌드 과정에서 에러 발생 시 `.failed` 상태를 발행합니다.
            stateContinuation.yield(.failed(error))
        }
    }
}

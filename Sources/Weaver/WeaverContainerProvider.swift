import SwiftUI
import Combine
//
///// DI 컨테이너의 비동기 생성, 상태, 생명주기를 전담하는 내부 클래스입니다.
///// ViewModifier와 HostView에서 공통으로 사용됩니다.
//@MainActor
//final class WeaverContainerProvider: ObservableObject {
//    /// 뷰가 컨테이너의 상태 변화를 감지할 수 있도록 @Published로 선언합니다.
//    @Published private(set) var container: WeaverContainer?
//    
//    /// 의존성 등록에 사용될 모듈의 배열입니다.
//    private let modules: [Module]
//
//    /// 생성자에서 사용자가 정의한 모듈들을 주입받습니다.
//    internal init(modules: [Module]) {
//        self.modules = modules
//    }
//
//    /// 컨테이너 빌드를 시작하는 비동기 함수입니다.
//    /// 중복 실행을 방지하기 위해 container가 nil일 때만 동작합니다.
//    internal func buildContainer() async {
//        guard container == nil else { return }
//
//        // 1. 빌더를 생성합니다.
//        let builder = WeaverContainer.builder()
//        
//        // 2. 루프를 돌며 주입받은 모든 모듈의 configure 메서드를 명시적으로 호출합니다.
//        //    이 과정은 WeaverBuilder가 actor이므로 비동기적으로 수행됩니다.
//        for module in modules {
//            await module.configure(builder)
//        }
//        
//        // 3. 모든 설정이 완료된 빌더로 컨테이너를 빌드하고,
//        //    @Published 프로퍼티에 할당하여 뷰의 갱신을 트리거합니다.
//        self.container = await builder.build()
//    }
//}

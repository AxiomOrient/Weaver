//import Testing
//import SwiftSyntaxMacrosTestSupport
//import Foundation
//@testable import Weaver
//import WeaverMacrosCore
//
//struct MacroExpansionTests {
//    @Test("@Registrar와 @Register 매크로가 올바른 코드를 생성한다")
//    func testMacrosGenerateCorrectCode() {
//        assertMacroExpansion(
//            """
//            @Registrar
//            struct MyServices {
//                @Register(scope: .container)
//                var service: Service { TestService() }
//            }
//            """,
//            expandedSource:
//            """
//            struct MyServices {
//                var service: Service { TestService() }
//
//                internal struct _serviceKey: DependencyKey {
//                    static var defaultValue: Service {
//                        fatalError("'Service'에 대한 의존성이 등록되지 않았습니다. 매크로로 등록된 의존성은 반드시 해결 가능해야 합니다.")
//                    }
//                }
//
//                public func configure(_ builder: WeaverBuilder) {
//                    builder.register(_serviceKey.self, scope: .container) { _ in
//                        self.service
//                    }
//                }
//            }
//
//            extension MyServices: Module {
//            }
//            """,
//            macros: [
//                "Registrar": RegistrarMacro.self,
//                "Register": RegisterMacro.self
//            ]
//        )
//    }
//}

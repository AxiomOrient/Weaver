import Foundation
import Combine

// 예시 서비스
struct Config: Sendable {
    let baseURL: URL
    static let fallback = Config(baseURL: URL(string: "https://fallback.local")!)
}

struct Profile: Sendable {
    let name: String
    static let empty = Profile(name: "Guest")
}

// 모듈 정의
let CoreModule = WeaverModule { weaver in
    await weaver
        .register(Config.self, startup: true) {
            try await Task.sleep(nanoseconds: 300_000_000)
            return Config(baseURL: URL(string: "https://api.example.com")!)
        }
        .register(Profile.self, startup: true) {
            try await Task.sleep(nanoseconds: 500_000_000)
            return Profile(name: "Aiden")
        }
}

@MainActor
final class ExampleVM: ObservableObject {
    @Use(default: Config.fallback) var config
    @Use(default: Profile.empty) var profile

    func bindUpgrades() {
        Task { [weak self] in
            guard let self else { return }
            for await c in UseStream.updates(Config.self) { self.config = c }
        }
        Task { [weak self] in
            guard let self else { return }
            for await p in UseStream.updates(Profile.self) { self.profile = p }
        }
    }
}

// 참고: 예제 엔트리포인트는 패키지 대상이 아니므로 빌드 대상에 포함되지 않습니다.
enum AppMainDemo {
    static func runDemo() async {
        await Weaver.shared.bootstrap(modules: [CoreModule])
        let vm = await MainActor.run { ExampleVM() }
        await MainActor.run { vm.bindUpgrades() }

        if let cfg: Config = await UseStream.current() {
            print("Config.current =", cfg.baseURL)
        }
    }
}


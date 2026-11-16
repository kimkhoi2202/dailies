import SwiftUI
import UIKit
import CoreText

// The app is hosted by UIKit rather than a SwiftUI App, so that one controller (LiveHost) can own
// the status bar, the home indicator and the appearance.

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MockFonts.registerAll()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        LiveMode.on = true
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = LiveHost()
        window.makeKeyAndVisible()
        self.window = window
        if let url = connectionOptions.urlContexts.first?.url { HomeShortcut.open(url) }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url { HomeShortcut.open(url) }
    }
}

enum MockArgs {
    /// The word that follows `name` in the launch arguments, if there is one.
    static func value(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let at = arguments.firstIndex(of: name), arguments.indices.contains(at + 1) else { return nil }
        return arguments[at + 1]
    }
}

enum MockFonts {
    /// Registers every font file in the bundle, so the Info.plist needs no font list.
    static func registerAll() {
        let files = ["ttf", "otf"].flatMap { Bundle.main.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
        for file in files { CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil) }
    }
}

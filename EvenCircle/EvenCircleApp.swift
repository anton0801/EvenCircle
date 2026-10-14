import SwiftUI
import UIKit

@main
struct EvenCircleApp: App {
    @StateObject private var root: AppRootViewModel

    init() {
        Appearance.configure()
        let container = AppContainer()
        if container.isUITesting {
            UIView.setAnimationsEnabled(false)
        }
        _root = StateObject(wrappedValue: AppRootViewModel(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView(root: root)
                .preferredColorScheme(.dark)
        }
    }
}

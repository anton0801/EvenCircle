import SwiftUI
import UIKit

/// Success haptic after a save, respecting the Haptics setting.
final class HapticFeedback {
    private let isEnabled: () -> Bool

    init(isEnabled: @escaping () -> Bool) {
        self.isEnabled = isEnabled
    }

    func success() {
        guard isEnabled() else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func warning() {
        guard isEnabled() else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

/// Presents the system share sheet. Only ever called from an explicit user action;
/// opening or cancelling the sheet does not count as sending anything.
enum SystemShare {
    static func present(items: [Any], completion: @escaping (_ completed: Bool) -> Void = { _ in }) {
        guard let presenter = topViewController() else {
            completion(false)
            return
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            DispatchQueue.main.async { completion(completed) }
        }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

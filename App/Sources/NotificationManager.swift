import Foundation
import UserNotifications
import AppKit
import AgentKit

extension Notification.Name {
    static let agentBarOpenMainWindow = Notification.Name("agentBarOpenMainWindow")
    static let agentBarShowAsk = Notification.Name("agentBarShowAsk")
}

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private var policy = NotificationPolicy()
    private var authorized = false
    private var hasSeeded = false

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.authorized = granted }
        }
    }

    func process(_ snapshots: [SessionSnapshot]) {
        let now = Date()
        // The first batch this instance ever sees is treated as a baseline, not
        // a burst of transitions: at app launch, every already-waiting session
        // would otherwise look like a fresh nil -> waitingForInput transition
        // and fire a notification for work that isn't new. Seed silently, then
        // let subsequent batches notify on genuine transitions as usual.
        guard hasSeeded else {
            hasSeeded = true
            for snap in snapshots {
                policy.seed(sessionID: snap.session.id, state: snap.state)
            }
            return
        }
        for snap in snapshots {
            guard policy.shouldNotify(sessionID: snap.session.id,
                                      newState: snap.state, now: now) else { continue }
            guard authorized else { continue } // badge-only degradation
            let content = UNMutableNotificationContent()
            content.title = "\(snap.session.projectName) is waiting for you"
            content.body = snap.session.title ?? snap.session.provider.displayName
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(
                identifier: snap.session.id + "-" + String(now.timeIntervalSince1970),
                content: content, trigger: nil))
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: @escaping () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .agentBarOpenMainWindow, object: nil)
        completion()
    }

    /// Without this, UNUserNotificationCenter suppresses banners/sounds while
    /// AgentBar is the frontmost app — since AgentBar is a menu-bar-only
    /// (LSUIElement) app that's often "frontmost" in a loose sense whenever its
    /// menu is open, notifications would silently vanish without this override.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completion:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .sound])
    }
}

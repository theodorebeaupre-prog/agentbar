import Foundation
import UserNotifications
import AppKit
import AgentKit

extension Notification.Name {
    static let agentBarOpenMainWindow = Notification.Name("agentBarOpenMainWindow")
}

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private var policy = NotificationPolicy()
    private var authorized = false

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
}

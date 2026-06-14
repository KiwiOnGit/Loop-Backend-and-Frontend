import Foundation
import UserNotifications

enum LoopNotificationService {
    static func requestAuthorization() async {
        do {
            try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            // Notification permission is not required for the app to keep working.
        }
    }

    static func publish(_ notification: LoopNotification) {
        guard notification.readAt == nil else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = notificationTitle(notification)
        content.body = notificationBody(notification)
        content.sound = .default
        content.userInfo = [
            "notificationId": notification.id,
            "conversationId": notification.conversationId ?? "",
            "loopId": notification.loop?.id ?? ""
        ]

        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func notificationTitle(_ notification: LoopNotification) -> String {
        let name = notification.actor?.displayName ?? "Loop"
        switch notification.type {
        case "like":
            return "\(name) liked your loop"
        case "comment":
            return "\(name) commented"
        case "follow":
            return "\(name) followed you"
        case "mention":
            return "\(name) mentioned you"
        case "message":
            return "\(name) sent a message"
        default:
            return "Loop"
        }
    }

    private static func notificationBody(_ notification: LoopNotification) -> String {
        if !notification.body.isEmpty {
            return notification.body
        }
        return "Open Loop to see what's new."
    }
}

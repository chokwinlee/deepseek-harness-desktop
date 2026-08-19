import Foundation
import UIKit
import UserNotifications

struct RemoteNotificationEvent {
    enum Kind: String {
        case completed
        case attention
    }

    let id: String
    let kind: Kind
    let body: String

    init?(payload: [String: Any]) {
        guard let id = payload["id"] as? String,
              !id.isEmpty,
              let rawKind = payload["kind"] as? String,
              let kind = Kind(rawValue: rawKind) else {
            return nil
        }

        self.id = id
        self.kind = kind
        self.body = (payload["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

final class RemoteNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RemoteNotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let deliveredEventLock = NSLock()
    private var deliveredEventIDs = Set<String>()
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private override init() {
        super.init()
    }

    func configure() {
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func deliver(_ event: RemoteNotificationEvent) {
        guard markAsDelivered(event.id) else {
            setMonitoringActive(false)
            return
        }

        Task { [weak self, center] in
            defer { self?.setMonitoringActive(false) }
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus.allowsRemoteReminders else { return }

            let content = UNMutableNotificationContent()
            content.title = event.kind == .completed ? "任务已完成" : "需要你确认"
            content.body = event.body.isEmpty ? event.kind.fallbackBody : String(event.body.prefix(220))
            content.sound = .default
            content.threadIdentifier = "dsh-remote"
            content.categoryIdentifier = event.kind == .completed
                ? "DSH_REMOTE_COMPLETED"
                : "DSH_REMOTE_ATTENTION"
            content.userInfo = [
                "eventID": event.id,
                "kind": event.kind.rawValue,
            ]

            let request = UNNotificationRequest(
                identifier: "dsh-remote-\(event.id)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
            )
            try? await center.add(request)
        }
    }

    func setMonitoringActive(_ active: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if active {
                guard self.backgroundTaskID == .invalid else { return }
                self.backgroundTaskID = UIApplication.shared.beginBackgroundTask(
                    withName: "Monitor DeepSeek Harness task"
                ) { [weak self] in
                    self?.setMonitoringActive(false)
                }
            } else {
                guard self.backgroundTaskID != .invalid else { return }
                UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                self.backgroundTaskID = .invalid
            }
        }
    }

    func clearDeliveredNotifications() {
        center.removeAllDeliveredNotifications()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    private func markAsDelivered(_ eventID: String) -> Bool {
        deliveredEventLock.lock()
        defer { deliveredEventLock.unlock() }
        return deliveredEventIDs.insert(eventID).inserted
    }
}

private extension UNAuthorizationStatus {
    var allowsRemoteReminders: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            true
        case .notDetermined, .denied:
            false
        @unknown default:
            false
        }
    }
}

private extension RemoteNotificationEvent.Kind {
    var fallbackBody: String {
        switch self {
        case .completed:
            "电脑上的 DeepSeek Harness 已完成本次任务。"
        case .attention:
            "DeepSeek Harness 正在等待你的选择。"
        }
    }
}

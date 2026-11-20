import SwiftUI
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

/// Port of MyFirebaseMessagingService: FCM token sync (`POST api/user/fcm-token`),
/// foreground alerts, and opening the booking a notification refers to.
@Observable
final class PushService {
    static let shared = PushService()

    /// Booking to open after a notification tap; MainTabView consumes and resets it.
    var pendingBookingId = 0

    private(set) var fcmToken: String {
        get { UserDefaults.standard.string(forKey: "fcm_token") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "fcm_token") }
    }

    private init() {}

    /// True when GoogleService-Info.plist is bundled and Firebase started.
    var isConfigured: Bool { FirebaseApp.app() != nil }

    func configure() {
        guard FirebaseApp.app() == nil,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
    }

    /// Asks for notification permission (once; iOS remembers the answer) and registers with APNs.
    func requestPermission() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func tokenChanged(_ token: String) {
        guard !token.isEmpty, token != fcmToken else { return }
        fcmToken = token
        Task { await syncToken() }
    }

    /// Same body as Android's updateFcmToken: `{ fcmToken, userId }`, only when logged in.
    func syncToken() async {
        let session = Session.shared
        let userId = session.userId.isEmpty ? session.uid : session.userId
        guard session.isLoggedIn, !fcmToken.isEmpty, !userId.isEmpty else { return }
        _ = await API.shared.ok(.post, "api/user/fcm-token", body: ["fcmToken": fcmToken, "userId": userId])
    }

    /// Android read `bookingId`, then `_id`, then `id` from the data payload.
    nonisolated static func bookingId(from userInfo: [AnyHashable: Any]) -> Int {
        for key in ["bookingId", "_id", "id"] {
            if let s = userInfo[key] as? String, let n = Int(s) { return n }
            if let n = userInfo[key] as? Int { return n }
        }
        return 0
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let push = PushService.shared
        push.configure()
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        if push.isConfigured { Messaging.messaging().delegate = NotificationDelegate.shared }
        // Registering needs no prompt, so the FCM token is ready to send with the OTP login.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard PushService.shared.isConfigured else { return }
        Messaging.messaging().apnsToken = deviceToken
    }
}

/// Firebase and UserNotifications call these off the main actor, so they hop over explicitly.
nonisolated final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, MessagingDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()

    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        Task { @MainActor in PushService.shared.tokenChanged(token) }
    }

    /// Show the alert even while the app is open (Android showed a heads-up notification).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let id = PushService.bookingId(from: response.notification.request.content.userInfo)
        guard id > 0 else { return }
        await MainActor.run { PushService.shared.pendingBookingId = id }
    }
}

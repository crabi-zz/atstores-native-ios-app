import SwiftUI
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

/// Push notifications for customers (order, booking and coupon updates), like the
/// Android app's MyFirebaseMessagingService: the FCM token goes to the server at
/// login and whenever it changes (`POST api/user/fcm-token`).
///
/// Push stays off until GoogleService-Info.plist (from Firebase, for this bundle id)
/// is added to the Atstores folder; everything else works without it.
@Observable
final class PushService {
    static let shared = PushService()

    /// Set when the user taps a notification; MainTabView opens Notifications and resets it.
    var openNotifications = false

    private(set) var fcmToken: String {
        get { UserDefaults.standard.string(forKey: "fcm_token") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "fcm_token") }
    }

    private init() {}

    var isConfigured: Bool { FirebaseApp.app() != nil }

    func configure() {
        guard FirebaseApp.app() == nil,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
    }

    /// Asks for permission once (iOS remembers the answer) and registers with APNs.
    func requestPermission() {
        guard isConfigured else { return }
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

    /// Same body as Android: `{ fcmToken, userId }`, only when logged in.
    func syncToken() async {
        let session = Session.shared
        let userId = session.numericUserId
        guard session.isLoggedIn, !fcmToken.isEmpty, userId > 0 else { return }
        _ = await API.shared.ok(.post, "api/user/fcm-token", body: ["fcmToken": fcmToken, "userId": userId], auth: true)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let push = PushService.shared
        push.configure()
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        if push.isConfigured {
            Messaging.messaging().delegate = NotificationDelegate.shared
            // Registering needs no prompt, so the token is ready to send with the OTP login.
            application.registerForRemoteNotifications()
        }
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

    /// Show the alert even while the app is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await MainActor.run { PushService.shared.openNotifications = true }
    }
}

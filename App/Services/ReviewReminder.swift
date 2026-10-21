import Foundation
import UserNotifications

/// 見返しのきっかけ通知（週1回だけ、静かに）。
/// 開くと「先週の今日」を、答え（筆跡）を見る前に思い出す流れで表示する。
enum ReviewReminder {
    static let identifier = "weekly-review"
    static let openReviewKey = "openReview"

    /// 許可を求めて、毎週の通知を登録する。許可されなければ false。
    static func schedule(weekday: Int, hour: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert])) ?? false
        guard granted else { return false }

        let content = UNMutableNotificationContent()
        content.title = "先週の今日を見返す"
        content.body = "答えを見る前に、何を書いたか思い出してみましょう。"
        // 音は鳴らさない（静かなUI）
        content.sound = nil
        content.interruptionLevel = .passive
        content.userInfo = [openReviewKey: true]

        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        return true
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

/// 通知をタップしたときに、見返し画面を開くための窓口
/// 起動直後（通知をタップして起動したとき）にも受け取れるよう、アプリの起動時に作る。
final class NotificationRouter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    @Published var showsReview = false

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.content.userInfo[ReviewReminder.openReviewKey] as? Bool == true {
            DispatchQueue.main.async { self.showsReview = true }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.list])
    }
}

import Foundation

/// 設定の保存キー（UserDefaults / @AppStorage）
enum Preferences {
    /// 完了の線と「今」の印（個性の演出）を表示する。初期値はオン。
    static let flourishes = "showsFlourishes"
    /// iCloud（CloudKit）で端末間を同期する。初期値はオフ。次回起動から有効。
    static let iCloudSync = "usesICloudSync"
    /// 見返しのきっかけ通知（週1回）。初期値はオフ。
    static let reviewReminder = "reviewReminderEnabled"
    /// 見返し通知の曜日（1=日曜〜7=土曜）と時刻
    static let reviewWeekday = "reviewReminderWeekday"
    static let reviewHour = "reviewReminderHour"
    /// AI連携サーバー（Cloudflare Workers）との同期。初期値はオフ。
    static let serverSync = "serverSyncEnabled"
    static let serverURL = "serverSyncURL"
    /// 最後に送った／受け取った時刻
    static let lastPushAt = "serverSyncLastPushAt"
    static let lastPullCursor = "serverSyncLastPullCursor"
}

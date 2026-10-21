import Foundation
import SwiftData

/// アプリ全体で1つだけ使うデータ保存先。
///
/// iCloud（CloudKit）での端末間同期は、設定で明示的にオンにしたときだけ使う（初期値はオフ）。
/// 保存先の作り方はアプリ起動時に決まるので、切り替えは次回起動から有効になる。
enum AppModelContainer {
    static let cloudKitContainerID = "iCloud.com.ryosuketakaoka.studyplan"

    static let schema = Schema([Board.self, Snapshot.self, Card.self, TimeLog.self])

    /// 起動時に iCloud 同期を使い始めたかどうか（設定画面の「開き直すと切り替わります」の判定に使う）
    private(set) static var isCloudKitEnabled = false

    /// アプリ本体と App Intents で共有する
    static let shared: ModelContainer = make(inMemory: false)

    static func make(inMemory: Bool) -> ModelContainer {
        let useCloudKit = !inMemory && UserDefaults.standard.bool(forKey: Preferences.iCloudSync)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: useCloudKit ? .private(cloudKitContainerID) : .none
        )
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            if !inMemory { isCloudKitEnabled = useCloudKit }
            return container
        } catch {
            // iCloud 側の準備ができていないなどで失敗したら、端末内だけで動かす
            let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: local)
            } catch {
                fatalError("データ保存先を作れませんでした: \(error)")
            }
        }
    }
}

import SwiftData
import SwiftUI

/// Xcode のプレビュー用。メモリの中だけにサンプルを入れる（端末のデータやウィジェットには触れない）。
enum PreviewSupport {
    @MainActor
    static let container: ModelContainer = {
        let container = AppModelContainer.make(inMemory: true)
        SampleData.insert(into: container.mainContext, refreshesWidget: false)
        return container
    }()
}

import SwiftUI

// 個性の演出は2つだけ：完了の線（CompletionStroke）と「今」の印（MarkerUnderline）。
// どちらも設定（Preferences.flourishes）でまとめて外せる。外しても、状態はアイコンと文字で分かる。

// MARK: - 完了の線

/// 「完了」を押したとき、カードの上にアクセント色の線を左から右へ引く。
/// 「視差効果を減らす」がオンのときは、線を引くアニメーションをせず、すぐに表示する。
struct CompletionStroke: View {
    @State private var progress: CGFloat

    init(animated: Bool) {
        _progress = State(initialValue: animated ? 0 : 1)
    }

    var body: some View {
        StrikeLine()
            .trim(from: 0, to: progress)
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .padding(.horizontal, 12)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard progress < 1 else { return }
                // 0.3秒以内
                withAnimation(.easeOut(duration: 0.25)) { progress = 1 }
            }
    }

    private struct StrikeLine: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

extension View {
    /// 完了の線と軽い触覚フィードバックを付ける。
    /// token は「完了」が押されるたびに増やす数。0 のときは（画面を開いた時点ですでに完了なら）線を静的に出す。
    func completionStroke(isDone: Bool, token: Int) -> some View {
        modifier(CompletionStrokeModifier(isDone: isDone, token: token))
    }
}

private struct CompletionStrokeModifier: ViewModifier {
    let isDone: Bool
    let token: Int
    @AppStorage(Preferences.flourishes) private var flourishes = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if flourishes && isDone {
                    CompletionStroke(animated: token > 0 && !reduceMotion)
                        .id(token)
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: token) { old, new in flourishes && new > old }
    }
}

// MARK: - 「今」の印

/// マーカーで引いたような下線。手書き風にするのはこの印だけで、形は固定（動かさない）。
struct MarkerUnderline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let height = rect.height
        // 1本目：少し右上がりに、ゆるく波打つ
        path.move(to: CGPoint(x: rect.minX + 1, y: rect.minY + height * 0.65))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + height * 0.3),
            control1: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + height * 0.2),
            control2: CGPoint(x: rect.minX + rect.width * 0.65, y: rect.minY + height * 0.8)
        )
        // 2本目：書き終わりで少し戻る
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.minY + height * 0.95))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.9, y: rect.minY + height * 0.6),
            control: CGPoint(x: rect.midX, y: rect.minY + height * 1.05)
        )
        return path
    }
}

extension View {
    /// 「今」の印を付ける（isVisible が false なら何も描かない）
    func nowMarker(_ isVisible: Bool) -> some View {
        padding(.bottom, 4)
            .background(alignment: .bottom) {
                if isVisible {
                    MarkerUnderline()
                        .stroke(Theme.accent.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(height: 8)
                        .offset(y: 3)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// 一覧の中で「今」を示すタグ。印を出さないときは、アクセント色の薄い背景で示す。
struct NowTag: View {
    var showsMarker = false

    var body: some View {
        Text("今")
            .font(TextRole.note.weight(.bold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, showsMarker ? 2 : 8)
            .padding(.vertical, 2)
            .background {
                if !showsMarker { Capsule().fill(Theme.accent.opacity(0.14)) }
            }
            .nowMarker(showsMarker)
            .accessibilityLabel("今のブロック")
    }
}

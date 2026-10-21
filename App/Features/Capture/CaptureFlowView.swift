import PhotosUI
import SwiftData
import SwiftUI

/// 撮影 → 処理 → 確認 → 保存 までの流れ
struct CaptureFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.createdAt) private var boards: [Board]
    @State private var processed: ProcessedCapture?
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            CaptureView(
                reference: boards.alive.first?.referenceImage,
                isProcessing: isProcessing,
                onCaptured: process
            )
            .navigationDestination(item: $processed) { capture in
                ConfirmView(capture: capture) { drafts in
                    save(capture, drafts: drafts)
                }
            }
        }
    }

    private func process(_ image: UIImage) {
        isProcessing = true
        Task {
            let result = await BoardProcessor.process(image, day: .now)
            isProcessing = false
            processed = result
        }
    }

    private func save(_ capture: ProcessedCapture, drafts: [CardDraft]) {
        SnapshotSaver.save(
            original: capture.original,
            corrected: capture.corrected,
            didCorrect: capture.didCorrect,
            day: capture.day,
            drafts: drafts,
            board: Board.defaultBoard(in: modelContext),
            context: modelContext
        )
        WidgetSync.refresh(using: modelContext)
        dismiss()
    }
}

/// 02・定点撮影：前回の写真を半透明で重ねて、毎日同じ構図で撮る
struct CaptureView: View {
    let reference: UIImage?
    let isProcessing: Bool
    let onCaptured: (UIImage) -> Void

    @StateObject private var camera = CameraModel()
    @State private var showsReference = true
    @State private var pickerItem: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            viewfinder
            Text("枠を合わせて撮影してください")
                .font(TextRole.note)
                .foregroundStyle(.secondary)
            controls
        }
        .padding()
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .navigationTitle("定点撮影")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") { dismiss() }
            }
        }
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    onCaptured(image)
                }
                pickerItem = nil
            }
        }
    }

    private var viewfinder: some View {
        // 大きさは 3:4（写真と同じ比率）に固定し、中身は overlay で重ねる
        Color(white: 0.12)
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay {
                if camera.state == .running {
                    CameraPreview(session: camera.session)
                }
            }
            .overlay {
                if showsReference, let reference {
                    Image(uiImage: reference)
                        .resizable()
                        .scaledToFill()
                        .opacity(0.3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if case .unavailable(let message) = camera.state {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .overlay {
                if isProcessing {
                    ProgressView("カードに切り出しています…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topLeading) {
                if showsReference && reference != nil {
                    Text("前回写真 30%")
                        .font(TextRole.note)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
            }
    }

    private var controls: some View {
        HStack(alignment: .center) {
            Toggle(isOn: $showsReference) {
                Label("前回写真を重ねる", systemImage: "square.on.square")
            }
            .toggleStyle(.button)
            .disabled(reference == nil)
            .frame(maxWidth: .infinity)

            Button {
                Task {
                    if let image = await camera.capture() { onCaptured(image) }
                }
            } label: {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 74, height: 74)
                    Circle().fill(.white).frame(width: 60, height: 60)
                }
            }
            .buttonStyle(.plain)
            .disabled(camera.state != .running || isProcessing)
            .opacity(camera.state == .running ? 1 : 0.4)
            .accessibilityLabel("撮影")

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("写真から", systemImage: "photo.on.rectangle")
            }
            .disabled(isProcessing)
            .frame(maxWidth: .infinity)
        }
        .labelStyle(VerticalLabelStyle())
        .font(TextRole.note)
    }
}

/// アイコンの下に文字を置くラベル
struct VerticalLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 4) {
            configuration.icon.font(.title3)
            configuration.title
        }
        .multilineTextAlignment(.center)
    }
}

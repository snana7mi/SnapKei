import SwiftUI

public struct CaptureView: View {
    @State private var sheetSource: ImageSourcePicker.Source?
    @Bindable private var viewModel: CaptureViewModel

    public init(viewModel: CaptureViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ChannelStatusBar(channel: viewModel.currentChannelDescription)

                switch viewModel.stage {
                case .idle:
                    Spacer()
                    Text("領収書を撮影またはインポート")
                        .foregroundStyle(.secondary)
                    Spacer()
                    ImageSourcePicker(
                        sheetSource: $sheetSource,
                        onImagePicked: { image in Task { await viewModel.handlePickedImage(image) } },
                        onPDFPicked: { url in Task { await viewModel.handlePickedPDF(url) } }
                    )

                case .parsing:
                    Spacer()
                    ProgressView("AI が解析中...")
                        .controlSize(.large)
                    Spacer()

                case .confirming(let draft):
                    ConfirmationFormWrapper(
                        initialDraft: draft,
                        receiptImagePath: viewModel.receiptImagePath,
                        receiptImageHash: viewModel.receiptImageHash,
                        sourceType: viewModel.sourceType,
                        onSave: { viewModel.saveConfirmed($0) }
                    )

                case .error(let message):
                    Spacer()
                    ContentUnavailableView("解析に失敗しました", systemImage: "exclamationmark.triangle", description: Text(message))
                    Button("やり直し") { viewModel.reset() }
                        .buttonStyle(.borderedProminent)
                    Spacer()

                case .saved:
                    Spacer()
                    ContentUnavailableView("保存しました", systemImage: "checkmark.circle.fill")
                    Button("次の領収書") { viewModel.reset() }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
            }
            .navigationTitle("撮影・取込")
        }
    }
}

private struct ConfirmationFormWrapper: View {
    let receiptImagePath: String?
    let receiptImageHash: String?
    let sourceType: RecordSource
    let onSave: (JournalEntry) -> Void
    @State private var draft: ReceiptDraft

    init(initialDraft: ReceiptDraft, receiptImagePath: String?, receiptImageHash: String?, sourceType: RecordSource, onSave: @escaping (JournalEntry) -> Void) {
        self.receiptImagePath = receiptImagePath
        self.receiptImageHash = receiptImageHash
        self.sourceType = sourceType
        self.onSave = onSave
        self._draft = State(initialValue: initialDraft)
    }

    var body: some View {
        ConfirmationForm(draft: $draft, receiptImagePath: receiptImagePath, receiptImageHash: receiptImageHash, sourceType: sourceType, onSave: onSave)
    }
}

private struct ChannelStatusBar: View {
    let channel: String

    var body: some View {
        HStack {
            Image(systemName: "cpu")
            Text(channel).font(.caption)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }
}

private extension CaptureViewModel {
    var currentChannelDescription: String {
        switch AISettings.load().aiChannel {
        case .directApiKey: "自前 API Key"
        case .builtInProxy: "内蔵 AI (OpenRouter Gemma)"
        }
    }
}

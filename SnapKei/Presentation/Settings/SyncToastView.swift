import LLMGatewayKit
import SwiftUI

struct SyncToastView: View {
    let observer: SyncStatusObserver

    @State private var toastMessage: String?
    @State private var isError = false

    var body: some View {
        Group {
            if let toastMessage {
                Text(toastMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isError ? .red : .green)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: toastMessage)
        .onChange(of: observer.lastResult?.timestamp) { _, _ in
            guard let result = observer.lastResult else { return }
            if result.success {
                if result.prunedCount > 0 {
                    toastMessage = "古いデータが自動削除されました (\(result.prunedCount))"
                    isError = true
                } else if result.pushedCount > 0 || result.pulledCount > 0 {
                    toastMessage = "同期完了"
                    isError = false
                } else {
                    return
                }
            } else {
                toastMessage = "同期エラー: \(result.error ?? "")"
                isError = true
            }

            Task {
                try? await Task.sleep(for: .seconds(2))
                toastMessage = nil
            }
        }
    }
}

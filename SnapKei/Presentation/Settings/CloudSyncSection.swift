import LLMGatewayKit
import SwiftUI

struct CloudSyncSection: View {
    let authService: AuthService
    let syncEngine: SyncEngine
    let onUpgrade: () -> Void

    @State private var isEnabled = SyncState.shared.isEnabled
    @State private var showDisableConfirm = false
    @State private var suppressOnChange = false

    private var isPaid: Bool {
        authService.currentUser?.tier == "paid"
    }

    var body: some View {
        Section {
            Toggle("クラウド同期", isOn: $isEnabled)
                .disabled(!authService.isLoggedIn || !isPaid)
                .onChange(of: isEnabled) { _, newValue in
                    if suppressOnChange {
                        suppressOnChange = false
                        return
                    }
                    if newValue {
                        SyncState.shared.isEnabled = true
                        Task { _ = try? await syncEngine.syncNow() }
                    } else {
                        showDisableConfirm = true
                    }
                }

            if !authService.isLoggedIn {
                Text("クラウド同期を使用するにはサインインしてください")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !isPaid {
                VStack(alignment: .leading, spacing: 8) {
                    Text("クラウド同期は Pro プランで利用できます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Pro にアップグレード", action: onUpgrade)
                        .font(.caption)
                }
            }

            if isEnabled && isPaid {
                Button("強制同期") {
                    Task { _ = try? await syncEngine.forceFullSync() }
                }
            }
        } header: {
            Text("クラウド同期")
        } footer: {
            Text("暗号化された通信で R1 ストレージに保存されます。")
        }
        .alert("クラウド同期を無効化しますか？", isPresented: $showDisableConfirm) {
            Button("無効化して削除", role: .destructive) {
                Task {
                    try? await syncEngine.disableAndDeleteCloud()
                    isEnabled = false
                }
            }
            Button("キャンセル", role: .cancel) {
                suppressOnChange = true
                isEnabled = true
            }
        } message: {
            Text("クラウド上のデータは完全に削除されます。本端末のローカルデータは保持されます。")
        }
    }
}

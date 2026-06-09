import SwiftUI

struct SaveButtonSection: View {
    let hasUnsavedChanges: Bool
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        Section {
            Button(action: onSave) {
                HStack {
                    Text("設定を保存")
                        .fontWeight(hasUnsavedChanges ? .semibold : .regular)
                    Spacer()
                    if hasUnsavedChanges {
                        Text("未保存の変更")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .foregroundStyle(hasUnsavedChanges ? .orange : .accentColor)

            if hasUnsavedChanges {
                Button("変更を破棄", role: .destructive, action: onDiscard)
            }
        }
    }
}

import LLMGatewayKit
import SwiftUI

struct AccountHeaderSection: View {
    let authService: AuthService
    let onTapAvatar: () -> Void
    @State private var avatarImage: Image?

    var body: some View {
        Section {
            HStack {
                Text("設定")
                    .font(.largeTitle.bold())
                Spacer()
                Button(action: onTapAvatar) {
                    avatarView
                }
                .buttonStyle(.plain)
                .accessibilityLabel("プロフィール")
            }
            .listRowBackground(Color.clear)
        }
        .task(id: authService.isLoggedIn) {
            guard authService.isLoggedIn else {
                avatarImage = nil
                return
            }
            try? await authService.fetchAccount()
            if let data = await authService.loadAvatarDataIfNeeded() {
                avatarImage = ProfileView.image(from: data)
            } else {
                avatarImage = nil
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if authService.isLoggedIn {
            ZStack {
                if let avatarImage {
                    avatarImage
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle().fill(Color.secondary.opacity(0.16))
                    Text(ProfileView.initial(from: authService.currentUser?.displayName ?? authService.currentUser?.email))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 45, height: 45)
            .clipShape(Circle())
            .rainbowAvatarBorder(isActive: authService.currentUser?.tier == "paid", size: 45)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
        }
    }
}

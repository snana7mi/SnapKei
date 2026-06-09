import SwiftUI

public struct OnboardingView: View {
    @State private var page = 0
    @State private var agreed = false
    @State private var businessName = ""
    @State private var ownerName = ""

    private let onComplete: (_ businessName: String, _ ownerName: String) -> Void

    public init(onComplete: @escaping (_ businessName: String, _ ownerName: String) -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        // Button-driven (no swipe paging) so the disclaimer consent on page 1 cannot be skipped.
        Group {
            switch page {
            case 0: welcomePage
            case 1: disclaimerPage
            default: setupPage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .animation(.default, value: page)
    }

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("SnapKei へようこそ")
                .font(.largeTitle.bold())
            Text("レシートを撮影して、個人事業主の記帳をサポートします。勘定科目や控除額は確認しながらご自身で判断できます。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            Button("次へ") { withAnimation { page = 1 } }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 48)
        }
    }

    private var disclaimerPage: some View {
        VStack(spacing: 16) {
            Text(LegalTexts.disclaimerTitle)
                .font(.title.bold())
                .padding(.top, 48)
            ScrollView {
                Text(LegalTexts.disclaimer)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
            }
            Toggle(LegalTexts.onboardingAgreeLabel, isOn: $agreed)
                .padding(.horizontal, 24)
            Button("次へ") { withAnimation { page = 2 } }
                .buttonStyle(.borderedProminent)
                .disabled(!agreed)
                .padding(.bottom, 48)
        }
    }

    private var setupPage: some View {
        VStack(spacing: 16) {
            Text("事業者情報")
                .font(.title.bold())
                .padding(.top, 48)
            Text("帳簿やレポート表示に使用します。あとから設定画面で変更できます。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Form {
                TextField("屋号（任意）", text: $businessName)
                TextField("氏名", text: $ownerName)
            }
            .frame(maxHeight: 180)
            .scrollDisabled(true)
            Spacer()
            Button("はじめる") { onComplete(businessName, ownerName) }
                .buttonStyle(.borderedProminent)
                .disabled(!agreed)
                .padding(.bottom, 48)
        }
    }
}

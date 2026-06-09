import SwiftUI

public struct DisclaimerView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            Text(LegalTexts.disclaimer)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(LegalTexts.disclaimerTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

public struct HouseholdAllocationSection: View {
    public init() {}

    public var body: some View {
        Section {
            NavigationLink {
                HouseholdAllocationDefaultsView()
            } label: {
                Label("家事按分デフォルト", systemImage: "percent")
            }
        }
    }
}

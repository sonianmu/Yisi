import SwiftUI

struct SoftwareRepairRow: View {
    @ObservedObject private var manager = SoftwareRepairManager.shared

    var body: some View {
        SettingsRow(title: "Help".localized) {
            HStack(spacing: 16) {
                TextAction(title: (manager.isRepairing ? "Repairing…" : "Repair Software").localized) {
                    manager.presentRepair()
                }
                .disabled(manager.isRepairing)
                Link("GitHub Issues".localized, destination: SoftwareRepairManager.issuesURL)
                    .font(.yisi(12))
                    .foregroundColor(AppColors.primary)
                if manager.isRepairing { ProgressView().controlSize(.small) }
            }
        }
    }
}

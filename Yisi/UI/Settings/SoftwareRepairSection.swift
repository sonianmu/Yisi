import SwiftUI

struct SoftwareRepairSection: View {
    @ObservedObject private var manager = SoftwareRepairManager.shared

    var body: some View {
        HStack(spacing: 16) {
            TextAction(title: (manager.isRepairing ? "Repairing…" : "Repair Software").localized) {
                manager.presentRepair()
            }
            .disabled(manager.isRepairing)
            if manager.isRepairing { ProgressView().controlSize(.small) }
            Link("GitHub Issues".localized, destination: SoftwareRepairManager.issuesURL)
                .font(.system(size: 12, design: .serif))
                .foregroundColor(AppColors.primary)
        }
    }
}

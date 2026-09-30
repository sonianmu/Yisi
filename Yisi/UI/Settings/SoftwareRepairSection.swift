import SwiftUI

struct SoftwareRepairSection: View {
    @ObservedObject private var manager = SoftwareRepairManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Button {
                    manager.presentRepair()
                } label: {
                    Text(manager.isRepairing ? "Repairing…".localized : "Repair Software".localized)
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.primary)
                }
                .buttonStyle(.plain)
                .disabled(manager.isRepairing)
                if manager.isRepairing { ProgressView().controlSize(.small) }
                Link("GitHub Issues".localized, destination: SoftwareRepairManager.issuesURL)
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.primary)
            }
            Text("Still not working after repair? Please report it on GitHub Issues.".localized)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

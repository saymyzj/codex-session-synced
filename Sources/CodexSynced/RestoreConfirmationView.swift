import SwiftUI

struct RestoreConfirmationView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmPulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(DS.warn)
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.l10n.text("恢复备份", "Restore Backup"))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(DS.ink)
                    Text(viewModel.l10n.text("这会把备份中的状态文件恢复到原位置。", "This restores backed-up state files to their original locations."))
                        .foregroundStyle(DS.muted)
                }
                Spacer()
            }

            if let backup = viewModel.selectedBackupForRestore {
                BackupRow(backup: backup, compact: false)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(DS.warn)
                Text(viewModel.l10n.text("恢复前请确认 Codex 已退出。此操作不会修改 OAuth Token、API Key 或第三方 URL。", "Make sure Codex is closed. OAuth tokens, API keys, and third-party URLs are not modified."))
                    .font(.system(size: 13))
                    .foregroundStyle(DS.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(DS.warn.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(DS.warn.opacity(0.18))
            )

            HStack {
                Spacer()
                SecondaryButton(title: viewModel.l10n.text("取消", "Cancel"), systemImage: "xmark") {
                    dismiss()
                }
                PrimaryButton(title: viewModel.l10n.text("确认恢复", "Restore"), systemImage: "arrow.counterclockwise") {
                    confirmPulse.toggle()
                    if let backup = viewModel.selectedBackupForRestore {
                        Task { await viewModel.restore(backup) }
                    }
                }
                .symbolEffect(.bounce, value: confirmPulse)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(DS.background)
    }
}

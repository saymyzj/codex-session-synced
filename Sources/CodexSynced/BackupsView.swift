import CodexSyncedCore
import SwiftUI

struct BackupsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HeaderView(
                    title: viewModel.l10n.text("备份", "Backups"),
                    subtitle: viewModel.l10n.text("查看本地备份并按需恢复。恢复前同样需要退出 Codex。", "View and restore local backups. Codex must be closed before restore.")
                )

                SoftPanel {
                    VStack(spacing: 12) {
                        HStack {
                            Text(viewModel.l10n.text("本地备份", "Local Backups"))
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                            SecondaryButton(title: viewModel.l10n.text("打开备份目录", "Open Folder"), systemImage: "folder") {
                                viewModel.openBackupDirectory()
                            }
                        }

                        if let backups = viewModel.scanResult?.backups, !backups.isEmpty {
                            ForEach(backups) { backup in
                                BackupRow(backup: backup, compact: false)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                    .overlay(alignment: .trailing) {
                                        SecondaryButton(
                                            title: viewModel.l10n.text("恢复此备份", "Restore"),
                                            systemImage: "arrow.counterclockwise"
                                        ) {
                                            viewModel.selectedBackupForRestore = backup
                                            viewModel.showingRestoreConfirmation = true
                                        }
                                        .padding(.trailing, 8)
                                    }
                                    .animation(AppMotion.smooth, value: viewModel.showingRestoreConfirmation)
                            }
                        } else {
                            HStack {
                                Spacer(minLength: 0)
                                EmptyState(
                                    image: "externaldrive.badge.plus",
                                    title: viewModel.l10n.text("暂无备份", "No backups yet"),
                                    message: viewModel.l10n.text("只有存在实际待修复项并执行“备份并修复”时，应用才会创建备份。轻简备份默认保留 5 份，全量备份默认保留 3 份。", "Backups are created only when repairs are applied. Lightweight keeps 5 by default; full keeps 3 by default."),
                                    actionTitle: viewModel.l10n.text("查看待修复项", "View Pending"),
                                    actionImage: "list.bullet.rectangle"
                                ) {
                                    viewModel.selectedSection = .pending
                                }
                                .frame(maxWidth: 560)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .padding(28)
        }
    }
}

struct BackupRow: View {
    var backup: BackupRecord
    var compact: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: backup.mode == .full ? "externaldrive.fill" : "externaldrive")
                .foregroundStyle(DS.blue)
                .frame(width: 34, height: 34)
                .background(DS.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(backup.createdAt.shortDateTime)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.ink)
                Text("\(backup.mode.zhTitle) · Provider \(backup.targetProvider) · \(backup.sizeBytes.fileSizeText)")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.muted)
                if !compact {
                    Text("SQLite \(backup.summary.sqliteProviderUpdates) · Rollout \(backup.summary.rolloutUpdates) · Index \(backup.summary.indexInsertions)")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.muted)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(DS.subtlePanel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DS.line)
        )
        .modifier(HoverLift(y: compact ? 0 : 1.5))
    }
}

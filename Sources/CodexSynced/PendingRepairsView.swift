import CodexSyncedCore
import SwiftUI

struct PendingRepairsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var showRepairPulse = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HeaderView(
                    title: viewModel.l10n.text("待修复项", "Pending Repairs"),
                    subtitle: viewModel.l10n.text("修复前预览，不会写入数据，确认后先备份再修复。", "Dry-run preview. Confirming creates a backup before changes.")
                )

                summary
                backupChoice
                previewList
            }
            .padding(28)
        }
    }

    private var summary: some View {
        SoftPanel {
            VStack(spacing: 0) {
                row(viewModel.l10n.text("目标 Provider", "Target Provider"), viewModel.scanResult?.providerInfo.provider ?? "-")
                row(viewModel.l10n.text("待修改 Provider 的 SQLite 记录", "SQLite provider rows"), "\(viewModel.scanResult?.sqliteProviderUpdates.count ?? 0)")
                row(viewModel.l10n.text("待修改 Provider 的 rollout 文件", "Rollout files"), "\(viewModel.scanResult?.rolloutRepairs.count ?? 0)")
                row(viewModel.l10n.text("待补充的索引条目", "Missing index entries"), "\(viewModel.scanResult?.indexRepairs.count ?? 0)")
                row(viewModel.l10n.text("兼容性字段修复", "Compatibility rows"), "\(viewModel.scanResult?.sqliteCompatibilityUpdates.count ?? 0)", last: true)
            }
        }
    }

    private var backupChoice: some View {
        SoftPanel {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.l10n.text("备份模式", "Backup Mode"))
                        .font(.system(size: 16, weight: .semibold))
                    Text(viewModel.l10n.text("轻简备份只保存必要回滚数据；全量备份会额外保存 sessions。", "Lightweight stores rollback data; full also copies sessions."))
                        .font(.system(size: 13))
                        .foregroundStyle(DS.muted)
                }
                Spacer()
                BackupModeSwitch(selection: $viewModel.selectedBackupMode, language: viewModel.settings.language)
                .frame(width: 240)
                PrimaryButton(
                    title: viewModel.l10n.text("备份并修复", "Back Up and Repair"),
                    systemImage: "checkmark.seal",
                    disabled: !(viewModel.scanResult?.hasRepairs ?? false) || viewModel.isBusy,
                    isLoading: viewModel.isBusy
                ) {
                    showRepairPulse.toggle()
                    Task { await viewModel.repairNow() }
                }
                .symbolEffect(.bounce, value: showRepairPulse)
            }
        }
        .modifier(HoverLift(y: 1.5))
    }

    private var previewList: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text(viewModel.l10n.text("预览", "Preview"))
                    .font(.system(size: 16, weight: .semibold))

                if let result = viewModel.scanResult, result.hasRepairs {
                    let rows = result.sqliteProviderUpdates.prefix(8)
                    if rows.isEmpty {
                        EmptyState(
                            image: "doc.badge.gearshape",
                            title: viewModel.l10n.text("没有 Provider 记录需要修改", "No provider rows need changes"),
                            message: viewModel.l10n.text("当前主要待修复项是索引或兼容字段。确认后会先创建备份，再补齐可见性数据。", "Current repairs are index or compatibility updates. A backup is created before applying them."),
                            actionTitle: nil,
                            actionImage: "arrow.right",
                            action: nil
                        )
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, thread in
                        HStack(spacing: 12) {
                            Image(systemName: "cylinder.split.1x2")
                                .foregroundStyle(DS.blue)
                                .frame(width: 34, height: 34)
                                .background(DS.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                            Text(displayTitle(for: thread))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(DS.ink)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer()

                        Text("\(thread.modelProvider) -> \(result.providerInfo.provider)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(DS.muted)
                            .contentTransition(.opacity)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .modifier(HoverLift(y: 1))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(AppMotion.smooth.delay(Double(index) * 0.035), value: rows.count)
                        Divider().opacity(0.35)
                    }
                    if result.sqliteProviderUpdates.count > 8 {
                        Text(viewModel.l10n.text("还有 \(result.sqliteProviderUpdates.count - 8) 条记录未显示。", "\(result.sqliteProviderUpdates.count - 8) more rows hidden."))
                            .font(.system(size: 12))
                            .foregroundStyle(DS.muted)
                    }
                } else {
                    EmptyState(
                        image: "checkmark.circle",
                        title: viewModel.l10n.text("当前没有待修复项", "No pending repairs"),
                        message: viewModel.l10n.text("会话历史已经与当前 Provider 对齐。", "Conversation history is already aligned with the current provider."),
                        actionTitle: viewModel.l10n.text("重新扫描", "Scan Again"),
                        actionImage: "magnifyingglass"
                    ) {
                        Task { await viewModel.scan() }
                    }
                }
            }
        }
    }

    private func row(_ title: String, _ value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .foregroundStyle(DS.muted)
                Spacer()
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.ink)
            }
            .padding(.vertical, 11)
            if !last { Divider().opacity(0.35) }
        }
    }

    private func displayTitle(for thread: ThreadRow) -> String {
        let title = thread.title
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return title.isEmpty ? thread.id : title
    }
}

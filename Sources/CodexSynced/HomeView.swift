import CodexSyncedCore
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var statusPulse = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeaderView(
                    title: viewModel.l10n.text("会话历史修复", "Conversation History Repair"),
                    subtitle: viewModel.l10n.text("根据当前 Codex Provider 动态对齐本地历史。", "Match local history to the active Codex provider.")
                )

                statusPanel
                metrics
                actions
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 18)
        }
    }

    private var statusPanel: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .frame(width: 44, height: 44)
                        .background(statusColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .symbolEffect(.bounce, value: viewModel.pendingRepairCount)
                        .scaleEffect(viewModel.isBusy && statusPulse ? 1.06 : 1)
                        .animation(viewModel.isBusy ? .easeInOut(duration: 0.82).repeatForever(autoreverses: true) : AppMotion.quick, value: statusPulse)
                        .onAppear { statusPulse = true }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusTitle)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(DS.ink)
                        Text(statusSubtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(DS.muted)
                            .lineLimit(2)
                    }

                    Spacer()

                    if let result = viewModel.scanResult {
                        VStack(alignment: .trailing, spacing: 7) {
                            tag(result.providerInfo.authLabel, tint: statusColor)
                            tag("Provider: \(result.providerInfo.provider)", tint: DS.blue)
                            tag(result.stateDatabase?.url.lastPathComponent ?? viewModel.l10n.text("未找到状态库", "No state database"), tint: DS.muted)
                        }
                    }
                }

                Divider().opacity(0.45)

                if viewModel.isBusy {
                    ActivityStrip(tint: statusColor)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                HStack(spacing: 18) {
                    infoItem(
                        viewModel.l10n.text("Codex 本地目录", "Codex Home"),
                        viewModel.scanResult?.codexHome.path ?? viewModel.settings.codexHome.path
                    )
                    Divider().frame(height: 34)
                    infoItem(
                        viewModel.l10n.text("最近修复", "Last Repair"),
                        viewModel.scanResult?.lastRepairAt?.shortDateTime ?? viewModel.l10n.text("暂无记录", "No record")
                    )
                }
            }
        }
        .modifier(HoverLift(y: 1.5))
    }

    private var metrics: some View {
        let result = viewModel.scanResult
        return Grid(horizontalSpacing: 14, verticalSpacing: 14) {
            GridRow {
                MetricTile(
                    title: viewModel.l10n.text("待修复 Provider", "Provider Updates"),
                    value: "\(result?.sqliteProviderUpdates.count ?? 0)",
                    caption: viewModel.l10n.text("SQLite 记录", "SQLite rows")
                )
                MetricTile(
                    title: viewModel.l10n.text("Rollout Metadata", "Rollout Metadata"),
                    value: "\(result?.rolloutRepairs.count ?? 0)",
                    caption: viewModel.l10n.text("只修改第一行", "First line only")
                )
                MetricTile(
                    title: viewModel.l10n.text("索引补齐", "Index Repairs"),
                    value: "\(result?.indexRepairs.count ?? 0)",
                    caption: "session_index.jsonl"
                )
            }
        }
        .animation(AppMotion.smooth, value: result?.sqliteProviderUpdates.count ?? 0)
        .animation(AppMotion.smooth, value: result?.rolloutRepairs.count ?? 0)
        .animation(AppMotion.smooth, value: result?.indexRepairs.count ?? 0)
    }

    private var actions: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workflowTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DS.ink)
                        Text(workflowSubtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(DS.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    PrimaryButton(
                        title: workflowActionTitle,
                        systemImage: workflowActionIcon,
                        disabled: viewModel.isBusy,
                        isLoading: viewModel.isBusy
                    ) {
                        performWorkflowAction()
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    SecondaryButton(title: viewModel.l10n.text("重新扫描", "Scan Again"), systemImage: "arrow.clockwise") {
                        Task { await viewModel.scan() }
                    }
                    SecondaryButton(title: viewModel.l10n.text("打开备份目录", "Open Backups"), systemImage: "folder") {
                        viewModel.openBackupDirectory()
                    }
                    SecondaryButton(title: viewModel.l10n.text("打开 Codex", "Open Codex"), systemImage: "arrow.up.forward.app") {
                        viewModel.openCodex()
                    }
                    Spacer()
                }

                Divider().opacity(0.45)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.blue)
                        .frame(width: 34, height: 34)
                        .background(DS.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.l10n.text("最近备份", "Recent Backup"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DS.ink)
                        if let backup = viewModel.scanResult?.backups.first {
                            Text("\(backup.createdAt.shortDateTime) · \(backup.mode.zhTitle) · \(backup.sizeBytes.fileSizeText)")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.muted)
                                .lineLimit(1)
                        } else {
                            Text(viewModel.l10n.text("尚未创建备份。只有存在实际待修复项时才会备份。", "No backups yet. Backups are created only when repairs are applied."))
                                .font(.system(size: 12))
                                .foregroundStyle(DS.muted)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                }
            }
        }
        .animation(AppMotion.smooth, value: viewModel.pendingRepairCount)
        .animation(AppMotion.smooth, value: viewModel.isBusy)
    }

    private var workflowTitle: String {
        if viewModel.isBusy {
            return viewModel.l10n.text("正在处理", "Working")
        }
        return (viewModel.scanResult?.hasRepairs ?? false)
            ? viewModel.l10n.text("发现待修复项", "Repairs Found")
            : viewModel.l10n.text("会话历史已对齐", "History Is Aligned")
    }

    private var workflowSubtitle: String {
        if viewModel.isBusy {
            return viewModel.l10n.text("正在检查本地历史，请稍候。", "Checking local history. Please wait.")
        }
        if viewModel.scanResult?.hasRepairs ?? false {
            return viewModel.l10n.text("发现 \(viewModel.pendingRepairCount) 项待处理。下一步查看变更并选择备份模式。", "Found \(viewModel.pendingRepairCount) items. Review changes and select a backup mode.")
        }
        return viewModel.l10n.text("当前没有待处理项。切换 Provider 后，重新扫描即可检查历史。", "No pending items. Scan again after switching providers.")
    }

    private var workflowActionTitle: String {
        if viewModel.isBusy {
            return viewModel.l10n.text("正在扫描", "Scanning")
        }
        return (viewModel.scanResult?.hasRepairs ?? false)
            ? viewModel.l10n.text("查看并修复", "Review and Repair")
            : viewModel.l10n.text("重新扫描", "Scan Again")
    }

    private var workflowActionIcon: String {
        (viewModel.scanResult?.hasRepairs ?? false) ? "arrow.right.circle" : "magnifyingglass"
    }

    private func performWorkflowAction() {
        if viewModel.scanResult?.hasRepairs ?? false {
            withAnimation(AppMotion.settle) {
                viewModel.selectedSection = .pending
            }
        } else {
            Task { await viewModel.scan() }
        }
    }

    private var recentBackup: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.l10n.text("最近备份", "Recent Backup"))
                    .font(.system(size: 16, weight: .semibold))
                if let backup = viewModel.scanResult?.backups.first {
                    BackupRow(backup: backup, compact: true)
                } else {
                    Text(viewModel.l10n.text("尚未创建备份。只有存在实际待修复项时才会备份。", "No backups yet. Backups are created only when there are actual repairs."))
                        .font(.system(size: 13))
                        .foregroundStyle(DS.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var statusTitle: String {
        switch viewModel.status {
        case .idle: viewModel.l10n.text("正在识别当前环境", "Detecting Environment")
        case .scanning: viewModel.l10n.text("正在扫描本地历史", "Scanning Local History")
        case .ready: viewModel.l10n.text("当前环境已识别", "Environment Detected")
        case .repairing: viewModel.l10n.text("正在处理本地历史", "Updating Local History")
        case .success: viewModel.l10n.text("当前环境已识别", "Environment Detected")
        case .failed: viewModel.l10n.text("需要处理", "Needs Attention")
        }
    }

    private var statusSubtitle: String {
        switch viewModel.status {
        case .failed(let message): message
        default:
            viewModel.l10n.text("已读取当前登录态和 Provider。不会修改 Token、API Key、第三方 URL 或会话正文。", "The active login and provider are detected. Tokens, keys, URLs, and message bodies are never changed.")
        }
    }

    private var statusIcon: String {
        switch viewModel.status {
        case .failed: "exclamationmark.triangle"
        case .scanning, .repairing: "clock.arrow.circlepath"
        default: (viewModel.scanResult?.hasRepairs ?? false) ? "wrench.adjustable" : "checkmark.circle"
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .failed: DS.warn
        default: (viewModel.scanResult?.hasRepairs ?? false) ? DS.blue : DS.ok
        }
    }

    private func tag(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint == DS.muted ? DS.ink : tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.09), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.18)))
    }

    private func infoItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.muted)
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(DS.ink)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HeaderView: View {
    var title: String
    var subtitle: String

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(DS.ink)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(DS.muted)
            }
            Spacer()
        }
    }
}

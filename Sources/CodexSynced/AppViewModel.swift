import AppKit
import CodexSyncedCore
import Foundation

enum NoticeTone {
    case info
    case success
    case warning
}

struct AppNotice: Identifiable {
    var id = UUID()
    var title: String
    var message: String
    var tone: NoticeTone
    var isLoading: Bool
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            settings.save()
            l10n = L10n(language: settings.language)
        }
    }
    @Published var l10n: L10n
    @Published var scanResult: ScanResult?
    @Published var status: ScanStatus = .idle
    @Published var selectedSection: AppSection = .home
    @Published var selectedBackupMode: BackupMode
    @Published var selectedBackupForRestore: BackupRecord?
    @Published var showingRestoreConfirmation = false
    @Published var showingCodexRunningAlert = false
    @Published var notice: AppNotice?
    @Published var lastScanAt: Date?

    let service = CodexRepairService()
    private var dismissNoticeTask: Task<Void, Never>?

    init() {
        let loadedSettings = AppSettings.load()
        settings = loadedSettings
        l10n = L10n(language: loadedSettings.language)
        selectedBackupMode = loadedSettings.defaultBackupMode
        Task { await scan(showFeedback: false) }
    }

    func scan(showFeedback: Bool = true) async {
        status = .scanning
        if showFeedback {
            showNotice(
                title: l10n.text("正在扫描", "Scanning"),
                message: l10n.text("正在检查本地侧边栏摘要和会话历史。", "Checking local sidebar summaries and conversation history."),
                tone: .info,
                isLoading: true,
                autoDismiss: false
            )
        }
        do {
            scanResult = try service.scan(settings: settings)
            status = .ready
            lastScanAt = Date()
            if showFeedback {
                let count = pendingRepairCount
                showNotice(
                    title: l10n.text("扫描完成", "Scan Complete"),
                    message: count == 0
                        ? l10n.text("侧边栏会话摘要状态正常。", "Sidebar conversation summaries look healthy.")
                        : l10n.text("发现 \(count) 项待处理，请查看修复方案。", "Found \(count) items. Review the repair plan."),
                    tone: count == 0 ? .success : .warning
                )
            }
        } catch {
            status = .failed(error.localizedDescription)
            showNotice(
                title: l10n.text("扫描失败", "Scan Failed"),
                message: error.localizedDescription,
                tone: .warning
            )
        }
    }

    func repairNow() async {
        guard let scanResult else {
            status = .failed(CodexRepairError.noScanResult.localizedDescription)
            return
        }
        do {
            status = .repairing(l10n.text("正在创建备份", "Creating backup"))
            showNotice(
                title: l10n.text("正在备份并修复", "Backing Up and Repairing"),
                message: l10n.text("请稍候，完成前不要退出应用。", "Please wait and keep this app open."),
                tone: .info,
                isLoading: true,
                autoDismiss: false
            )
            _ = try service.repair(scan: scanResult, settings: settings, mode: selectedBackupMode)
            status = .success(l10n.text("修复完成", "Repair complete"))
            self.scanResult = try service.scan(settings: settings)
            lastScanAt = Date()
            showNotice(
                title: l10n.text("修复完成", "Repair Complete"),
                message: l10n.text("侧边栏会话摘要已修复，并已创建备份。", "Sidebar conversation summaries were repaired and backed up."),
                tone: .success
            )
            if settings.openCodexAfterRepair {
                service.openCodex()
            }
        } catch CodexRepairError.codexIsRunning {
            showingCodexRunningAlert = true
            status = .failed(CodexRepairError.codexIsRunning.localizedDescription)
            showNotice(title: l10n.text("需要先退出 Codex", "Quit Codex First"), message: CodexRepairError.codexIsRunning.localizedDescription, tone: .warning)
        } catch {
            status = .failed(error.localizedDescription)
            showNotice(title: l10n.text("修复失败", "Repair Failed"), message: error.localizedDescription, tone: .warning)
        }
    }

    func restore(_ backup: BackupRecord) async {
        do {
            status = .repairing(l10n.text("正在恢复备份", "Restoring backup"))
            showNotice(
                title: l10n.text("正在恢复备份", "Restoring Backup"),
                message: l10n.text("正在恢复状态文件和 rollout metadata。", "Restoring state files and rollout metadata."),
                tone: .info,
                isLoading: true,
                autoDismiss: false
            )
            try service.restore(backup: backup)
            status = .success(l10n.text("备份已恢复", "Backup restored"))
            scanResult = try service.scan(settings: settings)
            lastScanAt = Date()
            showNotice(title: l10n.text("恢复完成", "Restore Complete"), message: l10n.text("备份已经恢复，可以重新打开 Codex。", "The backup is restored. You can reopen Codex."), tone: .success)
        } catch CodexRepairError.codexIsRunning {
            showingCodexRunningAlert = true
            status = .failed(CodexRepairError.codexIsRunning.localizedDescription)
            showNotice(title: l10n.text("需要先退出 Codex", "Quit Codex First"), message: CodexRepairError.codexIsRunning.localizedDescription, tone: .warning)
        } catch {
            status = .failed(error.localizedDescription)
            showNotice(title: l10n.text("恢复失败", "Restore Failed"), message: error.localizedDescription, tone: .warning)
        }
        showingRestoreConfirmation = false
        selectedBackupForRestore = nil
    }

    func openCodex() {
        service.openCodex()
        showNotice(title: l10n.text("正在打开 Codex", "Opening Codex"), message: l10n.text("已向系统发送打开请求。", "The open request was sent to macOS."), tone: .info)
    }

    func openBackupDirectory() {
        let root = service.backupRoot(codexHome: settings.codexHome)
        service.openDirectory(root)
        showNotice(title: l10n.text("已打开备份目录", "Backup Folder Opened"), message: root.path, tone: .info)
    }

    var pendingRepairCount: Int {
        guard let scanResult else { return 0 }
        return scanResult.sqliteProviderUpdates.count
            + scanResult.sqliteCompatibilityUpdates.count
            + scanResult.rolloutRepairs.count
            + scanResult.indexRepairs.count
            + scanResult.sqliteTimestampRepairs.count
            + scanResult.sqliteTitleRepairs.count
            + scanResult.rolloutMtimeRepairs.count
            + (scanResult.globalStateRepair?.changes.count ?? 0)
    }

    var isBusy: Bool {
        switch status {
        case .scanning, .repairing:
            return true
        default:
            return false
        }
    }

    func dismissNotice() {
        dismissNoticeTask?.cancel()
        notice = nil
    }

    private func showNotice(
        title: String,
        message: String,
        tone: NoticeTone,
        isLoading: Bool = false,
        autoDismiss: Bool = true
    ) {
        dismissNoticeTask?.cancel()
        let newNotice = AppNotice(title: title, message: message, tone: tone, isLoading: isLoading)
        notice = newNotice
        guard autoDismiss else { return }
        dismissNoticeTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled, notice?.id == newNotice.id else { return }
            notice = nil
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case home
    case pending
    case backups
    case settings

    var id: String { rawValue }
}

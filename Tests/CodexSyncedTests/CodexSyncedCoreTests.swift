import Foundation
import Testing
@testable import CodexSyncedCore

struct CodexSyncedCoreTests {
    @Test func rootModelProviderIgnoresNestedMCPProvider() throws {
        let directory = try makeTempDirectory()
        let config = directory.appendingPathComponent("config.toml")
        try """
        model = "gpt-5.5"

        [mcp_servers.example]
        model_provider = "openai_http"
        """.write(to: config, atomically: true, encoding: .utf8)

        let parsed = ConfigParser.parse(url: config)

        #expect(parsed.rootValues["model_provider"] == nil)
    }

    @Test func rootModelProviderReadsCustomProvider() throws {
        let directory = try makeTempDirectory()
        let config = directory.appendingPathComponent("config.toml")
        try """
        model_provider = "custom"

        [mcp_servers.example]
        model_provider = "openai_http"
        """.write(to: config, atomically: true, encoding: .utf8)

        let parsed = ConfigParser.parse(url: config)

        #expect(parsed.rootValues["model_provider"] == "custom")
    }

    @Test func sqliteHomePrefersNestedDirectoryWhenPresent() throws {
        let directory = try makeTempDirectory()
        let nested = directory.appendingPathComponent("sqlite")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent("state_5.sqlite"))

        let settings = AppSettings(
            language: .zh,
            codexHome: directory,
            sqliteHome: nil,
            defaultBackupMode: .lightweight,
            lightweightLimit: 5,
            fullLimit: 3,
            openCodexAfterRepair: false
        )
        let parsed = ParsedConfig(rootValues: [:], providerSections: [:])

        #expect(CodexPathResolver.effectiveSQLiteHome(settings: settings, parsedConfig: parsed).path == nested.standardizedFileURL.path)
    }

    @Test func rolloutRepairOnlyChangesSessionMetaProvider() throws {
        let directory = try makeTempDirectory()
        let rollout = directory.appendingPathComponent("rollout-test.jsonl")
        try """
        {"type":"session_meta","payload":{"id":"abc","model_provider":"openai","cwd":"/tmp"}}
        {"type":"user_message","payload":{"text":"keep me"}}
        """.write(to: rollout, atomically: true, encoding: .utf8)

        guard let repair = RolloutRepairer.makeRepair(url: rollout, targetProvider: "custom") else {
            Issue.record("Expected rollout repair")
            return
        }
        try RolloutRepairer.apply(repair)
        let content = try String(contentsOf: rollout, encoding: .utf8)

        #expect(content.contains("\"model_provider\":\"custom\""))
        #expect(content.contains("\"text\":\"keep me\""))
    }

    @Test func rolloutRepairReadsLargeSessionMetaLine() throws {
        let directory = try makeTempDirectory()
        let rollout = directory.appendingPathComponent("rollout-large.jsonl")
        let instructions = String(repeating: "x", count: 160 * 1024)
        try """
        {"type":"session_meta","payload":{"id":"large","model_provider":"custom","base_instructions":{"text":"\(instructions)"}}}
        {"type":"user_message","payload":{"text":"keep me"}}
        """.write(to: rollout, atomically: true, encoding: .utf8)

        guard let repair = RolloutRepairer.makeRepair(url: rollout, targetProvider: "openai") else {
            Issue.record("Expected rollout repair for session metadata larger than 128 KB")
            return
        }
        try RolloutRepairer.apply(repair)
        let content = try String(contentsOf: rollout, encoding: .utf8)

        #expect(content.contains("\"model_provider\":\"openai\""))
        #expect(content.contains("\"text\":\"keep me\""))
    }

    @Test func rolloutRepairDoesNotDecodePastFirstLine() throws {
        let directory = try makeTempDirectory()
        let rollout = directory.appendingPathComponent("rollout-utf8-boundary.jsonl")
        let sessionMeta = #"{"type":"session_meta","payload":{"id":"utf8","model_provider":"custom"}}"#
        let prefixSize = sessionMeta.utf8.count + 1
        let secondLine = String(repeating: "x", count: 128 * 1024 - prefixSize - 1) + "你"
        try "\(sessionMeta)\n\(secondLine)\n".write(to: rollout, atomically: true, encoding: .utf8)

        let repair = RolloutRepairer.makeRepair(url: rollout, targetProvider: "openai")

        #expect(repair != nil)
    }

    @Test func sidebarProviderRepairUsesRolloutAsSourceOfTruth() throws {
        let directory = try makeTempDirectory()
        let rollout = directory.appendingPathComponent("rollout-provider.jsonl")
        try """
        {"timestamp":"2026-06-01T10:00:00.000Z","type":"session_meta","payload":{"id":"provider-test","model_provider":"openai","cwd":"\(directory.path)"}}
        """.write(to: rollout, atomically: true, encoding: .utf8)

        let thread = makeThread(
            id: "provider-test",
            rollout: rollout,
            title: "Provider test",
            provider: "custom",
            cwd: directory.path,
            firstUserMessage: "Provider test"
        )
        let info = SidebarRepairPlanner.rolloutInfoByPath(for: [thread])
        let repairs = SidebarRepairPlanner.providerRepairs(threads: [thread], rollouts: info)

        #expect(repairs.count == 1)
        #expect(repairs.first?.targetProvider == "openai")
    }

    @Test func providerAlignmentTargetsActiveProviderForSQLiteAndRollout() throws {
        let directory = try makeTempDirectory()
        let rollout = directory.appendingPathComponent("rollout-provider-align.jsonl")
        try """
        {"timestamp":"2026-06-01T10:00:00.000Z","type":"session_meta","payload":{"id":"provider-align","model_provider":"openai","cwd":"\(directory.path)"}}
        {"timestamp":"2026-06-01T10:01:00.000Z","type":"user_message","payload":{"text":"keep me"}}
        """.write(to: rollout, atomically: true, encoding: .utf8)

        let thread = makeThread(
            id: "provider-align",
            rollout: rollout,
            title: "Provider align",
            provider: "openai",
            cwd: directory.path,
            firstUserMessage: "Provider align"
        )
        let sqliteRepairs = SidebarRepairPlanner.providerAlignmentRepairs(threads: [thread], targetProvider: "custom")
        let rolloutRepairs = SidebarRepairPlanner.rolloutProviderAlignmentRepairs(threads: [thread], targetProvider: "custom")

        #expect(sqliteRepairs.count == 1)
        #expect(sqliteRepairs.first?.targetProvider == "custom")
        #expect(rolloutRepairs.count == 1)
        #expect(rolloutRepairs.first?.currentProvider == "openai")
        #expect(rolloutRepairs.first?.targetProvider == "custom")

        try RolloutRepairer.apply(rolloutRepairs[0])
        let content = try String(contentsOf: rollout, encoding: .utf8)
        #expect(content.contains("\"model_provider\":\"custom\""))
        #expect(content.contains("\"text\":\"keep me\""))
    }

    @Test func sidebarPlannerDetectsDesktopSummaryRepairs() throws {
        let directory = try makeTempDirectory()
        let project = directory.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let rollout = directory.appendingPathComponent("rollout-sidebar.jsonl")
        try """
        {"timestamp":"2026-06-01T10:00:00.000Z","type":"session_meta","payload":{"id":"sidebar-test","model_provider":"openai","cwd":"\(project.path)"}}
        {"timestamp":"2026-06-01T10:05:00.000Z","type":"event_msg","payload":{"message":"done"}}
        """.write(to: rollout, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: rollout.path)
        try #"{"selected-remote-host-id":"remote-control:bad","electron-saved-workspace-roots":["\#(project.path)"],"project-order":[],"remote-connection-auto-connect-by-host-id":{"remote-control:bad":true},"added-remote-control-env-ids":["stale"],"electron-local-remote-control-environment-id":"local"}"#
            .write(to: directory.appendingPathComponent(".codex-global-state.json"), atomically: true, encoding: .utf8)
        try #"{"id":"sidebar-test","thread_name":"old","updated_at":"2026-06-01T10:00:00.000Z"}"#
            .appending("\n")
            .write(to: directory.appendingPathComponent("session_index.jsonl"), atomically: true, encoding: .utf8)

        let firstMessage = "为什么我的codex左侧的聊天历史有好多都不见了"
        let thread = makeThread(
            id: "sidebar-test",
            rollout: rollout,
            title: firstMessage,
            provider: "openai",
            cwd: project.path,
            updatedAt: 1,
            updatedAtMs: 1000,
            firstUserMessage: firstMessage
        )
        let info = SidebarRepairPlanner.rolloutInfoByPath(for: [thread])
        let titleRepairs = SidebarRepairPlanner.titleRepairs(threads: [thread])
        let timestampRepairs = SidebarRepairPlanner.timestampRepairs(threads: [thread], rollouts: info)
        let mtimeRepairs = SidebarRepairPlanner.rolloutMtimeRepairs(threads: [thread], rollouts: info)
        let projected = SidebarRepairPlanner.projectedThreads(threads: [thread], titleRepairs: titleRepairs, timestampRepairs: timestampRepairs)
        let indexRepairs = SidebarRepairPlanner.indexRepairs(codexHome: directory, threads: projected)
        let globalRepair = SidebarRepairPlanner.globalStateRepair(codexHome: directory, threads: projected)

        #expect(titleRepairs.count == 1)
        #expect(titleRepairs.first?.targetTitle.hasSuffix(" - Project") == true)
        #expect(timestampRepairs.count == 1)
        #expect(mtimeRepairs.count == 1)
        #expect(indexRepairs.count == 1)
        #expect(indexRepairs.first?.title == titleRepairs.first?.targetTitle)
        #expect(globalRepair?.changes.isEmpty == false)
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeThread(
        id: String,
        rollout: URL,
        title: String,
        provider: String,
        cwd: String,
        updatedAt: Int64 = 1,
        updatedAtMs: Int64? = 1000,
        firstUserMessage: String,
        preview: String = ""
    ) -> ThreadRow {
        ThreadRow(
            id: id,
            rolloutPath: rollout.path,
            title: title,
            modelProvider: provider,
            hasUserEvent: true,
            cwd: cwd,
            source: "vscode",
            threadSource: "user",
            archived: false,
            updatedAt: updatedAt,
            updatedAtMs: updatedAtMs,
            firstUserMessage: firstUserMessage,
            preview: preview
        )
    }
}

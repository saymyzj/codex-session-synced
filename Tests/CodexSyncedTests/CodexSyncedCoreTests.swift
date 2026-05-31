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

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

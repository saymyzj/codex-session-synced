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

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

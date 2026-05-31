using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace CodexSynced.Windows;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            if (args.Contains("--self-test", StringComparer.OrdinalIgnoreCase))
                return SelfTest.Run();

            if (args.Contains("--scan", StringComparer.OrdinalIgnoreCase))
            {
                var settings = AppSettings.Load();
                var homeIndex = Array.FindIndex(args, value => value.Equals("--codex-home", StringComparison.OrdinalIgnoreCase));
                if (homeIndex >= 0 && homeIndex + 1 < args.Length)
                    settings.CodexHome = args[homeIndex + 1];
                var scan = new RepairService().Scan(settings);
                Console.WriteLine(JsonSerializer.Serialize(scan.ToSummary(), JsonOptions.Pretty));
                return 0;
            }

            ApplicationConfiguration.Initialize();
            Application.Run(new MainForm());
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex);
            if (!args.Contains("--scan", StringComparer.OrdinalIgnoreCase) &&
                !args.Contains("--self-test", StringComparer.OrdinalIgnoreCase))
                MessageBox.Show(ex.Message, "Codex Synced", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}

internal static class JsonOptions
{
    public static readonly JsonSerializerOptions Pretty = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };
}

internal enum BackupMode
{
    Lightweight,
    Full
}

internal sealed class AppSettings
{
    public string CodexHome { get; set; } = "";
    public string? SqliteHome { get; set; }
    public BackupMode DefaultBackupMode { get; set; } = BackupMode.Lightweight;
    public int LightweightLimit { get; set; } = 5;
    public int FullLimit { get; set; } = 3;
    public bool OpenCodexAfterRepair { get; set; } = true;

    public static string SettingsPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Codex Synced", "settings.json");

    public static AppSettings Load()
    {
        AppSettings settings;
        try
        {
            settings = File.Exists(SettingsPath)
                ? JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(SettingsPath), JsonOptions.Pretty) ?? new()
                : new();
        }
        catch
        {
            settings = new();
        }

        if (string.IsNullOrWhiteSpace(settings.CodexHome))
        {
            settings.CodexHome = Environment.GetEnvironmentVariable("CODEX_HOME")
                ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex");
        }
        settings.SqliteHome ??= Environment.GetEnvironmentVariable("CODEX_SQLITE_HOME");
        settings.LightweightLimit = Math.Clamp(settings.LightweightLimit, 1, 30);
        settings.FullLimit = Math.Clamp(settings.FullLimit, 1, 12);
        return settings;
    }

    public void Save()
    {
        Directory.CreateDirectory(Path.GetDirectoryName(SettingsPath)!);
        File.WriteAllText(SettingsPath, JsonSerializer.Serialize(this, JsonOptions.Pretty));
    }
}

internal sealed record ProviderInfo(string Provider, string AuthLabel, string ConfigPath);
internal sealed record StateDatabase(string Path, DateTime ModifiedAt);
internal sealed record ThreadRow(
    string Id,
    string RolloutPath,
    string Title,
    string ModelProvider,
    bool HasUserEvent,
    string Cwd,
    string? ThreadSource,
    bool Archived,
    long UpdatedAt);
internal sealed record RolloutRepair(
    string Path,
    string SessionId,
    string? CurrentProvider,
    string TargetProvider,
    string OriginalFirstLine,
    string RepairedFirstLine);
internal sealed record IndexRepair(string ThreadId, string Title, long UpdatedAt);
internal sealed record RepairSummary(
    string TargetProvider,
    int SqliteProviderUpdates,
    int SqliteCompatibilityUpdates,
    int RolloutUpdates,
    int IndexInsertions,
    DateTime RepairedAt);
internal sealed record BackupFile(string OriginalPath, string BackupRelativePath);
internal sealed record BackupDirectory(string OriginalPath, string BackupRelativePath);
internal sealed record BackupFirstLine(string OriginalPath, string FirstLine);
internal sealed record BackupRecord(
    string DirectoryName,
    DateTime CreatedAt,
    BackupMode Mode,
    string TargetProvider,
    RepairSummary Summary,
    long SizeBytes,
    string Path);
internal sealed record BackupManifest(
    BackupRecord Record,
    List<BackupFile> Files,
    List<BackupDirectory> Directories,
    List<BackupFirstLine> RolloutFirstLines);

internal sealed class ScanResult
{
    public required ProviderInfo ProviderInfo { get; init; }
    public StateDatabase? StateDatabase { get; init; }
    public required List<ThreadRow> Threads { get; init; }
    public required List<ThreadRow> SqliteProviderUpdates { get; init; }
    public required List<ThreadRow> SqliteCompatibilityUpdates { get; init; }
    public required List<RolloutRepair> RolloutRepairs { get; init; }
    public required List<IndexRepair> IndexRepairs { get; init; }
    public required List<BackupRecord> Backups { get; init; }
    public required string CodexHome { get; init; }
    public required string SqliteHome { get; init; }

    public bool HasRepairs =>
        SqliteProviderUpdates.Count > 0 ||
        SqliteCompatibilityUpdates.Count > 0 ||
        RolloutRepairs.Count > 0 ||
        IndexRepairs.Count > 0;

    public int PendingCount =>
        SqliteProviderUpdates.Count +
        SqliteCompatibilityUpdates.Count +
        RolloutRepairs.Count +
        IndexRepairs.Count;

    public object ToSummary() => new
    {
        provider = ProviderInfo.Provider,
        auth = ProviderInfo.AuthLabel,
        codexHome = CodexHome,
        sqliteHome = SqliteHome,
        stateDatabase = StateDatabase?.Path,
        threads = Threads.Count,
        sqliteProviderUpdates = SqliteProviderUpdates.Count,
        sqliteCompatibilityUpdates = SqliteCompatibilityUpdates.Count,
        rolloutRepairs = RolloutRepairs.Count,
        indexRepairs = IndexRepairs.Count,
        backups = Backups.Count,
        hasRepairs = HasRepairs
    };
}

internal static class ConfigParser
{
    public static (Dictionary<string, string> Root, Dictionary<string, Dictionary<string, string>> Providers) Parse(string path)
    {
        var root = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var providers = new Dictionary<string, Dictionary<string, string>>(StringComparer.OrdinalIgnoreCase);
        if (!File.Exists(path))
            return (root, providers);

        string? section = null;
        foreach (var rawLine in File.ReadLines(path))
        {
            var line = StripComment(rawLine).Trim();
            if (line.Length == 0)
                continue;
            if (line.StartsWith('[') && line.EndsWith(']'))
            {
                section = line[1..^1];
                continue;
            }
            var equals = line.IndexOf('=');
            if (equals < 1)
                continue;
            var key = line[..equals].Trim();
            var value = Unquote(line[(equals + 1)..].Trim());
            if (section is null)
            {
                root[key] = value;
            }
            else if (section.StartsWith("model_providers.", StringComparison.OrdinalIgnoreCase))
            {
                var provider = section["model_providers.".Length..].Trim('"');
                if (!providers.TryGetValue(provider, out var values))
                {
                    values = new(StringComparer.OrdinalIgnoreCase);
                    providers[provider] = values;
                }
                values[key] = value;
            }
        }
        return (root, providers);
    }

    private static string StripComment(string line)
    {
        var inQuote = false;
        var result = new StringBuilder();
        foreach (var character in line)
        {
            if (character == '"')
                inQuote = !inQuote;
            if (character == '#' && !inQuote)
                break;
            result.Append(character);
        }
        return result.ToString();
    }

    private static string Unquote(string value) =>
        value.Length >= 2 && value[0] == '"' && value[^1] == '"' ? value[1..^1] : value;
}

internal sealed class RepairService
{
    public ScanResult Scan(AppSettings settings)
    {
        var codexHome = Path.GetFullPath(settings.CodexHome);
        var configPath = Path.Combine(codexHome, "config.toml");
        var parsed = ConfigParser.Parse(configPath);
        var provider = parsed.Root.TryGetValue("model_provider", out var configured) && !string.IsNullOrWhiteSpace(configured)
            ? configured
            : "openai";
        var providerSection = parsed.Providers.TryGetValue(provider, out var section) ? section : [];
        var authLabel = provider == "openai"
            ? providerSection.TryGetValue("requires_openai_auth", out var auth) && auth.Equals("false", StringComparison.OrdinalIgnoreCase)
                ? "OpenAI API Key"
                : "OpenAI OAuth"
            : providerSection.TryGetValue("requires_openai_auth", out var customAuth) && customAuth.Equals("true", StringComparison.OrdinalIgnoreCase)
                ? "第三方 API"
                : "自定义 Provider";

        var sqliteHome = settings.SqliteHome;
        if (string.IsNullOrWhiteSpace(sqliteHome) && parsed.Root.TryGetValue("sqlite_home", out var configuredSqlite))
            sqliteHome = ExpandPath(configuredSqlite);
        sqliteHome = Path.GetFullPath(string.IsNullOrWhiteSpace(sqliteHome) ? codexHome : sqliteHome);
        var state = LatestStateDatabase(sqliteHome);
        var threads = new List<ThreadRow>();
        if (state is not null)
        {
            using var db = new SqliteDatabase(state.Path, true);
            threads = db.QueryThreads();
        }
        var rolloutRoots = new[]
        {
            Path.Combine(codexHome, "sessions"),
            Path.Combine(codexHome, "archived_sessions")
        };

        return new ScanResult
        {
            ProviderInfo = new(provider, authLabel, configPath),
            StateDatabase = state,
            Threads = threads,
            SqliteProviderUpdates = threads.Where(row => row.ModelProvider != provider).ToList(),
            SqliteCompatibilityUpdates = threads.Where(row => !row.HasUserEvent || string.IsNullOrWhiteSpace(row.Cwd) || string.IsNullOrWhiteSpace(row.ThreadSource)).ToList(),
            RolloutRepairs = FindRolloutFiles(rolloutRoots).Select(path => MakeRolloutRepair(path, provider)).Where(repair => repair is not null).Cast<RolloutRepair>().ToList(),
            IndexRepairs = MissingIndexRepairs(codexHome, threads),
            Backups = LoadBackups(codexHome),
            CodexHome = codexHome,
            SqliteHome = sqliteHome
        };
    }

    public BackupRecord? Repair(ScanResult scan, AppSettings settings, BackupMode mode, bool ignoreCodexRunning = false)
    {
        if (!ignoreCodexRunning && IsCodexRunning())
            throw new InvalidOperationException("检测到 Codex 正在运行。请先退出 Codex，再执行修复。");
        if (scan.StateDatabase is null)
            throw new InvalidOperationException($"未找到状态数据库：{scan.SqliteHome}");
        if (!scan.HasRepairs)
            return null;

        var backup = CreateBackup(scan, mode);
        using (var db = new SqliteDatabase(scan.StateDatabase.Path, false))
        {
            db.UpdateProvider(scan.SqliteProviderUpdates.Select(row => row.Id), scan.ProviderInfo.Provider);
            db.UpdateCompatibility(scan.SqliteCompatibilityUpdates.Select(row => row.Id));
        }
        foreach (var repair in scan.RolloutRepairs)
            ApplyRolloutRepair(repair.Path, repair.RepairedFirstLine);
        AppendMissingIndexEntries(scan.IndexRepairs, scan.CodexHome);
        RotateBackups(scan.CodexHome, mode, mode == BackupMode.Full ? settings.FullLimit : settings.LightweightLimit);
        return backup;
    }

    public void Restore(BackupRecord backup, bool ignoreCodexRunning = false)
    {
        if (!ignoreCodexRunning && IsCodexRunning())
            throw new InvalidOperationException("检测到 Codex 正在运行。请先退出 Codex，再恢复备份。");
        var manifestPath = Path.Combine(backup.Path, "manifest.json");
        var manifest = JsonSerializer.Deserialize<BackupManifest>(File.ReadAllText(manifestPath), JsonOptions.Pretty)
            ?? throw new InvalidOperationException($"无法读取备份清单：{manifestPath}");

        foreach (var item in manifest.Files)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(item.OriginalPath)!);
            File.Copy(Path.Combine(backup.Path, item.BackupRelativePath), item.OriginalPath, true);
        }
        foreach (var item in manifest.Directories)
        {
            if (Directory.Exists(item.OriginalPath))
                Directory.Delete(item.OriginalPath, true);
            CopyDirectory(Path.Combine(backup.Path, item.BackupRelativePath), item.OriginalPath);
        }
        foreach (var item in manifest.RolloutFirstLines)
            ApplyRolloutRepair(item.OriginalPath, item.FirstLine);
    }

    public static bool IsCodexRunning()
    {
        foreach (var process in Process.GetProcesses())
        {
            try
            {
                if (process.ProcessName.Equals("Codex", StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            catch
            {
                // Some system processes deny metadata access.
            }
        }
        return false;
    }

    public static void OpenDirectory(string path)
    {
        Directory.CreateDirectory(path);
        Process.Start(new ProcessStartInfo("explorer.exe", $"\"{path}\"") { UseShellExecute = true });
    }

    public static void OpenCodex()
    {
        try
        {
            Process.Start(new ProcessStartInfo("explorer.exe", @"shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App") { UseShellExecute = true });
        }
        catch
        {
            Process.Start(new ProcessStartInfo("codex://") { UseShellExecute = true });
        }
    }

    public static string BackupRoot(string codexHome) => Path.Combine(codexHome, "codex-synced-backups");

    private static StateDatabase? LatestStateDatabase(string sqliteHome) =>
        Directory.Exists(sqliteHome)
            ? Directory.EnumerateFiles(sqliteHome, "state_*.sqlite", SearchOption.TopDirectoryOnly)
                .Select(path => new StateDatabase(path, File.GetLastWriteTimeUtc(path)))
                .OrderByDescending(state => state.ModifiedAt)
                .FirstOrDefault()
            : null;

    private static IEnumerable<string> FindRolloutFiles(IEnumerable<string> roots) =>
        roots.Where(Directory.Exists)
            .SelectMany(root => Directory.EnumerateFiles(root, "rollout-*.jsonl", SearchOption.AllDirectories))
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase);

    private static RolloutRepair? MakeRolloutRepair(string path, string targetProvider)
    {
        var firstLine = ReadFirstLine(path);
        if (firstLine is null)
            return null;
        JsonObject? root;
        try
        {
            root = JsonNode.Parse(firstLine)?.AsObject();
        }
        catch
        {
            return null;
        }
        if (root?["type"]?.GetValue<string>() != "session_meta" || root["payload"] is not JsonObject payload)
            return null;
        var current = payload["model_provider"]?.GetValue<string>();
        if (current == targetProvider)
            return null;
        payload["model_provider"] = targetProvider;
        var id = payload["id"]?.GetValue<string>() ?? Path.GetFileNameWithoutExtension(path);
        return new(path, id, current, targetProvider, firstLine, root.ToJsonString());
    }

    private static string? ReadFirstLine(string path)
    {
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var buffer = new MemoryStream();
        while (true)
        {
            var value = stream.ReadByte();
            if (value < 0 || value == '\n')
                break;
            buffer.WriteByte((byte)value);
        }
        var bytes = buffer.ToArray();
        if (bytes.Length > 0 && bytes[^1] == '\r')
            bytes = bytes[..^1];
        return bytes.Length == 0 ? null : Encoding.UTF8.GetString(bytes);
    }

    private static void ApplyRolloutRepair(string path, string firstLine)
    {
        var bytes = File.ReadAllBytes(path);
        var newline = Array.IndexOf(bytes, (byte)'\n');
        var suffix = newline >= 0 ? bytes[(newline + 1)..] : [];
        var temp = path + ".codex-synced.tmp";
        using (var stream = File.Create(temp))
        {
            stream.Write(Encoding.UTF8.GetBytes(firstLine));
            stream.WriteByte((byte)'\n');
            stream.Write(suffix);
        }
        File.Move(temp, path, true);
    }

    private static List<IndexRepair> MissingIndexRepairs(string codexHome, List<ThreadRow> threads)
    {
        var indexPath = Path.Combine(codexHome, "session_index.jsonl");
        var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (File.Exists(indexPath))
        {
            foreach (var line in File.ReadLines(indexPath))
            {
                try
                {
                    var id = JsonNode.Parse(line)?["id"]?.GetValue<string>();
                    if (!string.IsNullOrWhiteSpace(id))
                        ids.Add(id);
                }
                catch
                {
                    // Preserve malformed user data and continue checking other entries.
                }
            }
        }
        return threads.Where(row => !ids.Contains(row.Id)).Select(row => new IndexRepair(row.Id, row.Title, row.UpdatedAt)).ToList();
    }

    private static void AppendMissingIndexEntries(List<IndexRepair> repairs, string codexHome)
    {
        if (repairs.Count == 0)
            return;
        var indexPath = Path.Combine(codexHome, "session_index.jsonl");
        Directory.CreateDirectory(codexHome);
        using var writer = new StreamWriter(indexPath, true, new UTF8Encoding(false));
        foreach (var repair in repairs)
        {
            writer.WriteLine(JsonSerializer.Serialize(new
            {
                id = repair.ThreadId,
                thread_name = repair.Title,
                updated_at = DateTimeOffset.FromUnixTimeSeconds(repair.UpdatedAt).UtcDateTime.ToString("O")
            }));
        }
    }

    private static BackupRecord CreateBackup(ScanResult scan, BackupMode mode)
    {
        var now = DateTime.UtcNow;
        var directoryName = $"{mode.ToString().ToLowerInvariant()}-{now:yyyyMMdd-HHmmssfff}";
        var directory = Path.Combine(BackupRoot(scan.CodexHome), directoryName);
        Directory.CreateDirectory(directory);
        var summary = new RepairSummary(
            scan.ProviderInfo.Provider,
            scan.SqliteProviderUpdates.Count,
            scan.SqliteCompatibilityUpdates.Count,
            scan.RolloutRepairs.Count,
            scan.IndexRepairs.Count,
            now);
        var files = new List<BackupFile>();
        var directories = new List<BackupDirectory>();

        void CopyFile(string source, string relative)
        {
            if (!File.Exists(source))
                return;
            var destination = Path.Combine(directory, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            File.Copy(source, destination, true);
            files.Add(new(source, relative));
        }

        if (scan.StateDatabase is not null)
        {
            CopyFile(scan.StateDatabase.Path, Path.Combine("sqlite", Path.GetFileName(scan.StateDatabase.Path)));
            CopyFile(scan.StateDatabase.Path + "-wal", Path.Combine("sqlite", Path.GetFileName(scan.StateDatabase.Path) + "-wal"));
            CopyFile(scan.StateDatabase.Path + "-shm", Path.Combine("sqlite", Path.GetFileName(scan.StateDatabase.Path) + "-shm"));
        }
        CopyFile(Path.Combine(scan.CodexHome, "config.toml"), Path.Combine("codex", "config.toml"));
        CopyFile(Path.Combine(scan.CodexHome, "session_index.jsonl"), Path.Combine("codex", "session_index.jsonl"));
        CopyFile(Path.Combine(scan.CodexHome, ".codex-global-state.json"), Path.Combine("codex", ".codex-global-state.json"));

        void CopyFullDirectory(string name)
        {
            var source = Path.Combine(scan.CodexHome, name);
            if (!Directory.Exists(source))
                return;
            var relative = Path.Combine("codex", name);
            CopyDirectory(source, Path.Combine(directory, relative));
            directories.Add(new(source, relative));
        }
        if (mode == BackupMode.Full)
        {
            CopyFullDirectory("sessions");
            CopyFullDirectory("archived_sessions");
        }

        var firstLines = scan.RolloutRepairs.Select(repair => new BackupFirstLine(repair.Path, repair.OriginalFirstLine)).ToList();
        var record = new BackupRecord(directoryName, now, mode, scan.ProviderInfo.Provider, summary, 0, directory);
        WriteManifest(directory, new(record, files, directories, firstLines));
        record = record with { SizeBytes = DirectorySize(directory) };
        WriteManifest(directory, new(record, files, directories, firstLines));
        return record;
    }

    private static void WriteManifest(string directory, BackupManifest manifest) =>
        File.WriteAllText(Path.Combine(directory, "manifest.json"), JsonSerializer.Serialize(manifest, JsonOptions.Pretty));

    private static List<BackupRecord> LoadBackups(string codexHome)
    {
        var root = BackupRoot(codexHome);
        if (!Directory.Exists(root))
            return [];
        var backups = new List<BackupRecord>();
        foreach (var directory in Directory.EnumerateDirectories(root))
        {
            try
            {
                var manifest = JsonSerializer.Deserialize<BackupManifest>(File.ReadAllText(Path.Combine(directory, "manifest.json")), JsonOptions.Pretty);
                if (manifest is not null)
                    backups.Add(manifest.Record with { Path = directory, SizeBytes = DirectorySize(directory) });
            }
            catch
            {
                // Ignore incomplete backup directories.
            }
        }
        return backups.OrderByDescending(backup => backup.CreatedAt).ToList();
    }

    private static void RotateBackups(string codexHome, BackupMode mode, int limit)
    {
        foreach (var backup in LoadBackups(codexHome).Where(backup => backup.Mode == mode).Skip(limit))
            Directory.Delete(backup.Path, true);
    }

    private static void CopyDirectory(string source, string destination)
    {
        Directory.CreateDirectory(destination);
        foreach (var file in Directory.EnumerateFiles(source))
            File.Copy(file, Path.Combine(destination, Path.GetFileName(file)), true);
        foreach (var directory in Directory.EnumerateDirectories(source))
            CopyDirectory(directory, Path.Combine(destination, Path.GetFileName(directory)));
    }

    private static long DirectorySize(string directory) =>
        Directory.Exists(directory) ? Directory.EnumerateFiles(directory, "*", SearchOption.AllDirectories).Sum(path => new FileInfo(path).Length) : 0;

    private static string ExpandPath(string path)
    {
        if (path == "~")
            return Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (path.StartsWith("~/") || path.StartsWith("~\\"))
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), path[2..]);
        return Environment.ExpandEnvironmentVariables(path);
    }
}

internal sealed class SqliteDatabase : IDisposable
{
    private IntPtr _handle;

    public SqliteDatabase(string path, bool readOnly)
    {
        var flags = readOnly ? NativeSqlite.SQLITE_OPEN_READONLY : NativeSqlite.SQLITE_OPEN_READWRITE | NativeSqlite.SQLITE_OPEN_CREATE;
        var result = NativeSqlite.sqlite3_open_v2(path, out _handle, flags, IntPtr.Zero);
        if (result != NativeSqlite.SQLITE_OK)
            throw new InvalidOperationException($"无法打开 SQLite：{ErrorMessage}");
    }

    public List<ThreadRow> QueryThreads()
    {
        const string sql = """
            SELECT id, rollout_path, title, model_provider, has_user_event, cwd, thread_source, archived, updated_at
            FROM threads
            ORDER BY updated_at DESC
            """;
        using var statement = Prepare(sql);
        var rows = new List<ThreadRow>();
        while (NativeSqlite.sqlite3_step(statement.Handle) == NativeSqlite.SQLITE_ROW)
        {
            rows.Add(new(
                statement.Text(0),
                statement.Text(1),
                statement.Text(2),
                statement.Text(3),
                NativeSqlite.sqlite3_column_int(statement.Handle, 4) != 0,
                statement.Text(5),
                statement.NullableText(6),
                NativeSqlite.sqlite3_column_int(statement.Handle, 7) != 0,
                NativeSqlite.sqlite3_column_int64(statement.Handle, 8)));
        }
        return rows;
    }

    public void UpdateProvider(IEnumerable<string> threadIds, string provider) =>
        UpdateMany("UPDATE threads SET model_provider = ? WHERE id = ?", threadIds, statement =>
        {
            statement.BindText(1, provider);
            statement.BindText(2, statement.CurrentId!);
        });

    public void UpdateCompatibility(IEnumerable<string> threadIds) =>
        UpdateMany("""
            UPDATE threads
            SET has_user_event = CASE WHEN has_user_event = 0 THEN 1 ELSE has_user_event END,
                cwd = CASE WHEN cwd = '' THEN '~' ELSE cwd END,
                thread_source = CASE WHEN thread_source IS NULL OR thread_source = '' THEN 'user' ELSE thread_source END
            WHERE id = ?
            """, threadIds, statement => statement.BindText(1, statement.CurrentId!));

    public void Execute(string sql)
    {
        var result = NativeSqlite.sqlite3_exec(_handle, sql, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
        if (result != NativeSqlite.SQLITE_OK)
            throw new InvalidOperationException($"SQLite 执行失败：{ErrorMessage}");
    }

    private void UpdateMany(string sql, IEnumerable<string> ids, Action<SqliteStatement> bind)
    {
        var values = ids.ToList();
        if (values.Count == 0)
            return;
        Execute("BEGIN IMMEDIATE");
        try
        {
            using var statement = Prepare(sql);
            foreach (var id in values)
            {
                statement.Reset();
                statement.CurrentId = id;
                bind(statement);
                if (NativeSqlite.sqlite3_step(statement.Handle) != NativeSqlite.SQLITE_DONE)
                    throw new InvalidOperationException($"SQLite 更新失败：{ErrorMessage}");
            }
            Execute("COMMIT");
        }
        catch
        {
            try { Execute("ROLLBACK"); } catch { }
            throw;
        }
    }

    private SqliteStatement Prepare(string sql)
    {
        if (NativeSqlite.sqlite3_prepare_v2(_handle, sql, -1, out var statement, IntPtr.Zero) != NativeSqlite.SQLITE_OK)
            throw new InvalidOperationException($"SQLite 查询准备失败：{ErrorMessage}");
        return new(statement);
    }

    private string ErrorMessage => Marshal.PtrToStringUTF8(NativeSqlite.sqlite3_errmsg(_handle)) ?? "unknown";

    public void Dispose()
    {
        if (_handle != IntPtr.Zero)
        {
            NativeSqlite.sqlite3_close(_handle);
            _handle = IntPtr.Zero;
        }
    }
}

internal sealed class SqliteStatement(IntPtr handle) : IDisposable
{
    public IntPtr Handle { get; private set; } = handle;
    public string? CurrentId { get; set; }

    public string Text(int index) => NullableText(index) ?? "";
    public string? NullableText(int index)
    {
        var value = NativeSqlite.sqlite3_column_text(Handle, index);
        return value == IntPtr.Zero ? null : Marshal.PtrToStringUTF8(value);
    }
    public void BindText(int index, string value) => NativeSqlite.sqlite3_bind_text(Handle, index, value, -1, new IntPtr(-1));
    public void Reset()
    {
        NativeSqlite.sqlite3_reset(Handle);
        NativeSqlite.sqlite3_clear_bindings(Handle);
    }
    public void Dispose()
    {
        if (Handle != IntPtr.Zero)
        {
            NativeSqlite.sqlite3_finalize(Handle);
            Handle = IntPtr.Zero;
        }
    }
}

internal static class NativeSqlite
{
    private const string Library = "winsqlite3";
    public const int SQLITE_OK = 0;
    public const int SQLITE_ROW = 100;
    public const int SQLITE_DONE = 101;
    public const int SQLITE_OPEN_READONLY = 0x00000001;
    public const int SQLITE_OPEN_READWRITE = 0x00000002;
    public const int SQLITE_OPEN_CREATE = 0x00000004;

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_open_v2([MarshalAs(UnmanagedType.LPUTF8Str)] string filename, out IntPtr db, int flags, IntPtr vfs);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_close(IntPtr db);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr sqlite3_errmsg(IntPtr db);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_prepare_v2(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string sql, int bytes, out IntPtr statement, IntPtr tail);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_step(IntPtr statement);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_finalize(IntPtr statement);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_reset(IntPtr statement);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_clear_bindings(IntPtr statement);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr sqlite3_column_text(IntPtr statement, int index);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_column_int(IntPtr statement, int index);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    public static extern long sqlite3_column_int64(IntPtr statement, int index);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_bind_text(IntPtr statement, int index, [MarshalAs(UnmanagedType.LPUTF8Str)] string value, int bytes, IntPtr destructor);
    [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_exec(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string sql, IntPtr callback, IntPtr callbackArg, IntPtr errorMessage);
}

internal sealed class MainForm : Form
{
    private readonly RepairService _service = new();
    private readonly AppSettings _settings = AppSettings.Load();
    private ScanResult? _scan;
    private readonly Label _status = LabelWithFont(20, FontStyle.Bold);
    private readonly Label _detail = LabelWithFont(10);
    private readonly Label _provider = LabelWithFont(10, FontStyle.Bold);
    private readonly Label _database = LabelWithFont(9);
    private readonly Label[] _metrics = [LabelWithFont(24, FontStyle.Bold), LabelWithFont(24, FontStyle.Bold), LabelWithFont(24, FontStyle.Bold), LabelWithFont(24, FontStyle.Bold)];
    private readonly DataGridView _pendingGrid = CreateGrid();
    private readonly DataGridView _backupGrid = CreateGrid();
    private readonly RadioButton _lightweight = new() { Text = "轻简备份", AutoSize = true, Checked = true };
    private readonly RadioButton _full = new() { Text = "全量备份", AutoSize = true };
    private readonly TextBox _codexHome = new() { Dock = DockStyle.Fill };
    private readonly TextBox _sqliteHome = new() { Dock = DockStyle.Fill };
    private readonly NumericUpDown _lightweightLimit = new() { Minimum = 1, Maximum = 30, Width = 72 };
    private readonly NumericUpDown _fullLimit = new() { Minimum = 1, Maximum = 12, Width = 72 };
    private readonly CheckBox _openAfterRepair = new() { Text = "修复完成后自动打开 Codex", AutoSize = true };
    private readonly TabControl _pages = new() { Dock = DockStyle.Fill, Appearance = TabAppearance.FlatButtons, ItemSize = new Size(0, 1), SizeMode = TabSizeMode.Fixed };

    public MainForm()
    {
        Text = "Codex Synced";
        MinimumSize = new Size(920, 640);
        Size = new Size(1120, 760);
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = Color.FromArgb(246, 248, 251);
        Font = new Font("Microsoft YaHei UI", 9F);

        var root = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2 };
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 190));
        root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        Controls.Add(root);
        root.Controls.Add(BuildSidebar(), 0, 0);
        root.Controls.Add(_pages, 1, 0);
        _pages.TabPages.Add(BuildHomePage());
        _pages.TabPages.Add(BuildPendingPage());
        _pages.TabPages.Add(BuildBackupsPage());
        _pages.TabPages.Add(BuildSettingsPage());

        _codexHome.Text = _settings.CodexHome;
        _sqliteHome.Text = _settings.SqliteHome ?? "";
        _lightweightLimit.Value = _settings.LightweightLimit;
        _fullLimit.Value = _settings.FullLimit;
        _openAfterRepair.Checked = _settings.OpenCodexAfterRepair;
        _lightweight.Checked = _settings.DefaultBackupMode == BackupMode.Lightweight;
        _full.Checked = _settings.DefaultBackupMode == BackupMode.Full;
        Shown += async (_, _) => await ScanAsync();
    }

    private Control BuildSidebar()
    {
        var panel = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            Padding = new Padding(14, 22, 14, 14),
            BackColor = Color.FromArgb(27, 35, 48)
        };
        var title = LabelWithFont(15, FontStyle.Bold);
        title.Text = "Codex Synced";
        title.ForeColor = Color.White;
        title.Margin = new Padding(8, 0, 0, 20);
        title.AutoSize = true;
        panel.Controls.Add(title);
        panel.Controls.Add(NavigationButton("修复状态", 0));
        panel.Controls.Add(NavigationButton("待修复项", 1));
        panel.Controls.Add(NavigationButton("备份", 2));
        panel.Controls.Add(NavigationButton("设置", 3));
        return panel;
    }

    private Button NavigationButton(string text, int page)
    {
        var button = new Button
        {
            Text = text,
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(39, 50, 66),
            ForeColor = Color.White,
            Width = 155,
            Height = 42,
            Margin = new Padding(2, 0, 2, 8),
            TextAlign = ContentAlignment.MiddleLeft,
            Padding = new Padding(14, 0, 0, 0)
        };
        button.FlatAppearance.BorderSize = 0;
        button.Click += (_, _) => _pages.SelectedIndex = page;
        return button;
    }

    private TabPage BuildHomePage()
    {
        var page = Page("会话历史修复", "根据当前 Codex Provider 动态对齐本地历史。");
        var body = (FlowLayoutPanel)page.Controls[0];
        var statusCard = Card(860, 142);
        _status.Text = "正在识别当前环境";
        _status.Location = new Point(22, 18);
        _status.AutoSize = true;
        _detail.Text = "不会修改 Token、API Key、第三方 URL 或会话正文。";
        _detail.ForeColor = Color.DimGray;
        _detail.Location = new Point(24, 55);
        _detail.AutoSize = true;
        _provider.Location = new Point(24, 94);
        _provider.AutoSize = true;
        _database.Location = new Point(320, 96);
        _database.AutoSize = true;
        statusCard.Controls.AddRange([_status, _detail, _provider, _database]);
        body.Controls.Add(statusCard);

        var metricRow = new FlowLayoutPanel { Width = 880, Height = 118, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        var labels = new[] { "SQLite Provider", "Rollout Metadata", "索引补齐", "兼容字段" };
        for (var index = 0; index < labels.Length; index++)
        {
            var metric = Card(205, 96);
            _metrics[index].Text = "0";
            _metrics[index].Location = new Point(16, 17);
            _metrics[index].AutoSize = true;
            var caption = new Label { Text = labels[index], Location = new Point(18, 62), AutoSize = true, ForeColor = Color.DimGray };
            metric.Controls.AddRange([_metrics[index], caption]);
            metricRow.Controls.Add(metric);
        }
        body.Controls.Add(metricRow);

        var actions = Card(860, 112);
        actions.Controls.Add(ActionButton("重新扫描", 18, 20, async () => await ScanAsync()));
        actions.Controls.Add(ActionButton("查看待修复项", 154, 20, () => _pages.SelectedIndex = 1));
        actions.Controls.Add(ActionButton("打开备份目录", 330, 20, () => RepairService.OpenDirectory(RepairService.BackupRoot(_settings.CodexHome))));
        actions.Controls.Add(ActionButton("打开 Codex", 498, 20, RepairService.OpenCodex));
        var note = new Label { Text = "请在修复或恢复前退出 Codex。扫描是只读操作。", Location = new Point(20, 76), AutoSize = true, ForeColor = Color.DimGray };
        actions.Controls.Add(note);
        body.Controls.Add(actions);
        return page;
    }

    private TabPage BuildPendingPage()
    {
        var page = Page("待修复项", "修复前预览。确认后先备份，再写入必要的可见性字段。");
        var body = (FlowLayoutPanel)page.Controls[0];
        var choice = Card(860, 72);
        _lightweight.Location = new Point(20, 25);
        _full.Location = new Point(120, 25);
        var repair = ActionButton("备份并修复", 690, 18, RepairAsync);
        choice.Controls.AddRange([_lightweight, _full, repair]);
        body.Controls.Add(choice);
        var gridCard = Card(860, 420);
        _pendingGrid.Dock = DockStyle.Fill;
        gridCard.Controls.Add(_pendingGrid);
        body.Controls.Add(gridCard);
        return page;
    }

    private TabPage BuildBackupsPage()
    {
        var page = Page("备份", "每次写入前都会创建可恢复备份。");
        var body = (FlowLayoutPanel)page.Controls[0];
        var actions = Card(860, 62);
        actions.Controls.Add(ActionButton("恢复选中备份", 18, 12, RestoreSelectedAsync));
        actions.Controls.Add(ActionButton("打开备份目录", 176, 12, () => RepairService.OpenDirectory(RepairService.BackupRoot(_settings.CodexHome))));
        body.Controls.Add(actions);
        var gridCard = Card(860, 430);
        _backupGrid.Dock = DockStyle.Fill;
        gridCard.Controls.Add(_backupGrid);
        body.Controls.Add(gridCard);
        return page;
    }

    private TabPage BuildSettingsPage()
    {
        var page = Page("设置", "Windows 版默认读取 %USERPROFILE%\\.codex。");
        var body = (FlowLayoutPanel)page.Controls[0];
        var card = Card(860, 302);
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(16), ColumnCount = 3, RowCount = 6 };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 145));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 94));
        AddSettingsRow(layout, 0, "Codex Home", _codexHome, ChooseCodexHome);
        AddSettingsRow(layout, 1, "SQLite Home", _sqliteHome, ChooseSqliteHome);
        layout.Controls.Add(new Label { Text = "轻简备份上限", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft }, 0, 2);
        layout.Controls.Add(_lightweightLimit, 1, 2);
        layout.Controls.Add(new Label { Text = "全量备份上限", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft }, 0, 3);
        layout.Controls.Add(_fullLimit, 1, 3);
        layout.Controls.Add(_openAfterRepair, 0, 4);
        layout.SetColumnSpan(_openAfterRepair, 2);
        layout.Controls.Add(ActionButton("保存设置", 0, 0, SaveSettings), 0, 5);
        card.Controls.Add(layout);
        body.Controls.Add(card);
        return page;
    }

    private static TabPage Page(string title, string subtitle)
    {
        var page = new TabPage { BackColor = Color.FromArgb(246, 248, 251), Padding = new Padding(22) };
        var body = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true };
        var header = new Panel { Width = 880, Height = 70 };
        var heading = LabelWithFont(22, FontStyle.Bold);
        heading.Text = title;
        heading.AutoSize = true;
        heading.Location = new Point(0, 2);
        var detail = LabelWithFont(10);
        detail.Text = subtitle;
        detail.ForeColor = Color.DimGray;
        detail.AutoSize = true;
        detail.Location = new Point(2, 40);
        header.Controls.AddRange([heading, detail]);
        body.Controls.Add(header);
        page.Controls.Add(body);
        return page;
    }

    private static Panel Card(int width, int height) => new()
    {
        Width = width,
        Height = height,
        BackColor = Color.White,
        Margin = new Padding(0, 0, 0, 12),
        Padding = new Padding(10)
    };

    private static Label LabelWithFont(float size, FontStyle style = FontStyle.Regular) => new()
    {
        Font = new Font("Microsoft YaHei UI", size, style)
    };

    private static DataGridView CreateGrid() => new()
    {
        ReadOnly = true,
        AllowUserToAddRows = false,
        AllowUserToDeleteRows = false,
        AllowUserToResizeRows = false,
        AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill,
        BackgroundColor = Color.White,
        BorderStyle = BorderStyle.None,
        RowHeadersVisible = false,
        SelectionMode = DataGridViewSelectionMode.FullRowSelect
    };

    private static Button ActionButton(string text, int left, int top, Action action)
    {
        var button = new Button
        {
            Text = text,
            Location = new Point(left, top),
            AutoSize = true,
            Height = 34,
            FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(31, 111, 235),
            ForeColor = Color.White,
            Padding = new Padding(8, 0, 8, 0)
        };
        button.FlatAppearance.BorderSize = 0;
        button.Click += (_, _) => action();
        return button;
    }

    private static void AddSettingsRow(TableLayoutPanel layout, int row, string title, TextBox box, Action choose)
    {
        layout.Controls.Add(new Label { Text = title, Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft }, 0, row);
        layout.Controls.Add(box, 1, row);
        layout.Controls.Add(ActionButton("选择", 0, 0, choose), 2, row);
    }

    private async Task ScanAsync()
    {
        SetBusy("正在扫描本地历史...");
        await Task.Yield();
        try
        {
            ApplySettings();
            _scan = _service.Scan(_settings);
            _status.Text = _scan.HasRepairs ? $"发现 {_scan.PendingCount} 项待处理" : "会话历史已对齐";
            _detail.Text = _scan.HasRepairs ? "请查看待修复项，确认变更后执行备份并修复。" : "当前没有待处理项。切换 Provider 后可重新扫描。";
            _provider.Text = $"Provider: {_scan.ProviderInfo.Provider}  ·  {_scan.ProviderInfo.AuthLabel}";
            _database.Text = $"状态库: {_scan.StateDatabase?.Path ?? "未找到"}";
            _metrics[0].Text = _scan.SqliteProviderUpdates.Count.ToString();
            _metrics[1].Text = _scan.RolloutRepairs.Count.ToString();
            _metrics[2].Text = _scan.IndexRepairs.Count.ToString();
            _metrics[3].Text = _scan.SqliteCompatibilityUpdates.Count.ToString();
            _pendingGrid.DataSource = _scan.SqliteProviderUpdates.Select(row => new { 标题 = row.Title, 会话 = row.Id, 当前Provider = row.ModelProvider, 目标Provider = _scan.ProviderInfo.Provider, 工作目录 = row.Cwd }).ToList();
            _backupGrid.DataSource = _scan.Backups.Select(backup => new { 时间 = backup.CreatedAt.ToLocalTime(), 模式 = backup.Mode, Provider = backup.TargetProvider, 大小KB = backup.SizeBytes / 1024, 路径 = backup.Path }).ToList();
        }
        catch (Exception ex)
        {
            _status.Text = "扫描失败";
            _detail.Text = ex.Message;
            MessageBox.Show(ex.Message, "扫描失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private async void RepairAsync()
    {
        if (_scan is null || !_scan.HasRepairs)
        {
            MessageBox.Show("当前没有待修复项。", "Codex Synced");
            return;
        }
        if (MessageBox.Show($"即将创建备份并修复 {_scan.PendingCount} 项。继续吗？", "确认修复", MessageBoxButtons.OKCancel, MessageBoxIcon.Question) != DialogResult.OK)
            return;
        SetBusy("正在备份并修复...");
        await Task.Yield();
        try
        {
            _service.Repair(_scan, _settings, _full.Checked ? BackupMode.Full : BackupMode.Lightweight);
            MessageBox.Show("修复完成。会话历史已经与当前 Provider 对齐。", "Codex Synced", MessageBoxButtons.OK, MessageBoxIcon.Information);
            await ScanAsync();
            if (_settings.OpenCodexAfterRepair)
                RepairService.OpenCodex();
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "修复失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private async void RestoreSelectedAsync()
    {
        if (_scan is null || _backupGrid.SelectedRows.Count == 0)
        {
            MessageBox.Show("请先选择一个备份。", "Codex Synced");
            return;
        }
        var index = _backupGrid.SelectedRows[0].Index;
        if (index < 0 || index >= _scan.Backups.Count)
            return;
        var backup = _scan.Backups[index];
        if (MessageBox.Show($"将恢复备份 {backup.DirectoryName}。请确认 Codex 已退出。", "确认恢复", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) != DialogResult.OK)
            return;
        try
        {
            _service.Restore(backup);
            MessageBox.Show("备份恢复完成。", "Codex Synced", MessageBoxButtons.OK, MessageBoxIcon.Information);
            await ScanAsync();
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "恢复失败", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private void SetBusy(string message)
    {
        _status.Text = message;
        _detail.Text = "请稍候。";
        Refresh();
    }

    private void ApplySettings()
    {
        _settings.CodexHome = _codexHome.Text.Trim();
        _settings.SqliteHome = string.IsNullOrWhiteSpace(_sqliteHome.Text) ? null : _sqliteHome.Text.Trim();
        _settings.LightweightLimit = (int)_lightweightLimit.Value;
        _settings.FullLimit = (int)_fullLimit.Value;
        _settings.OpenCodexAfterRepair = _openAfterRepair.Checked;
        _settings.DefaultBackupMode = _full.Checked ? BackupMode.Full : BackupMode.Lightweight;
    }

    private async void SaveSettings()
    {
        ApplySettings();
        _settings.Save();
        MessageBox.Show("设置已保存。", "Codex Synced");
        await ScanAsync();
    }

    private void ChooseCodexHome() => ChooseFolder(_codexHome);
    private void ChooseSqliteHome() => ChooseFolder(_sqliteHome);
    private static void ChooseFolder(TextBox target)
    {
        using var dialog = new FolderBrowserDialog { SelectedPath = target.Text };
        if (dialog.ShowDialog() == DialogResult.OK)
            target.Text = dialog.SelectedPath;
    }
}

internal static class SelfTest
{
    public static int Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "codex-synced-self-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            File.WriteAllText(Path.Combine(root, "config.toml"), """
                model_provider = "custom"

                [mcp_servers.example]
                model_provider = "ignored"
                """);
            var rolloutDirectory = Path.Combine(root, "sessions", "2026", "06", "01");
            Directory.CreateDirectory(rolloutDirectory);
            var rollout = Path.Combine(rolloutDirectory, "rollout-self-test.jsonl");
            File.WriteAllText(rollout, """
                {"type":"session_meta","payload":{"id":"self-test","model_provider":"openai","cwd":"C:\\work"}}
                {"type":"event_msg","payload":{"message":"keep me"}}
                """);
            var state = Path.Combine(root, "state_5.sqlite");
            using (var db = new SqliteDatabase(state, false))
            {
                db.Execute("""
                    CREATE TABLE threads (
                        id TEXT PRIMARY KEY,
                        rollout_path TEXT,
                        title TEXT,
                        model_provider TEXT,
                        has_user_event INTEGER,
                        cwd TEXT,
                        thread_source TEXT,
                        archived INTEGER,
                        updated_at INTEGER
                    )
                    """);
                db.Execute("""
                    INSERT INTO threads VALUES (
                        'self-test',
                        'rollout-self-test.jsonl',
                        'Self test',
                        'openai',
                        0,
                        '',
                        NULL,
                        0,
                        1780257600
                    )
                    """);
            }
            var settings = new AppSettings { CodexHome = root, OpenCodexAfterRepair = false };
            var service = new RepairService();
            var scan = service.Scan(settings);
            Assert(scan.SqliteProviderUpdates.Count == 1, "SQLite provider repair was not detected.");
            Assert(scan.SqliteCompatibilityUpdates.Count == 1, "Compatibility repair was not detected.");
            Assert(scan.RolloutRepairs.Count == 1, "Rollout repair was not detected.");
            Assert(scan.IndexRepairs.Count == 1, "Index repair was not detected.");
            var backup = service.Repair(scan, settings, BackupMode.Lightweight, true);
            Assert(backup is not null, "Backup was not created.");
            var repaired = service.Scan(settings);
            Assert(!repaired.HasRepairs, "Repairs did not converge.");
            Assert(File.ReadAllText(rollout).Contains("\"message\":\"keep me\""), "Rollout body changed unexpectedly.");
            service.Restore(backup!, true);
            var restored = service.Scan(settings);
            Assert(restored.SqliteProviderUpdates.Count == 1, "Restore did not return SQLite provider metadata.");
            Console.WriteLine("Codex Synced Windows self-test passed.");
            return 0;
        }
        finally
        {
            if (Directory.Exists(root))
                Directory.Delete(root, true);
        }
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition)
            throw new InvalidOperationException(message);
    }
}

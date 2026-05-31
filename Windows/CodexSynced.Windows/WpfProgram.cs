using System.IO;
using System.Text.Json;

namespace CodexSynced.Windows;

internal static class WpfProgram
{
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            if (args.Contains("--self-test", StringComparer.OrdinalIgnoreCase))
                return SelfTest.Run();

            if (args.Contains("--ui-snapshot", StringComparer.OrdinalIgnoreCase))
            {
                var outputIndex = Array.FindIndex(args, value => value.Equals("--output", StringComparison.OrdinalIgnoreCase));
                var output = outputIndex >= 0 && outputIndex + 1 < args.Length
                    ? args[outputIndex + 1]
                    : Path.Combine(Environment.CurrentDirectory, "codex-synced-ui.png");
                var homeIndex = Array.FindIndex(args, value => value.Equals("--codex-home", StringComparison.OrdinalIgnoreCase));
                var codexHome = homeIndex >= 0 && homeIndex + 1 < args.Length ? args[homeIndex + 1] : null;
                var window = new MainWindow();
                window.SaveSnapshot(output, codexHome);
                window.Close();
                System.Windows.Threading.Dispatcher.CurrentDispatcher.InvokeShutdown();
                Environment.Exit(0);
                return 0;
            }

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

            var app = new System.Windows.Application
            {
                ShutdownMode = System.Windows.ShutdownMode.OnMainWindowClose
            };
            app.Run(new MainWindow());
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex);
            if (!args.Contains("--scan", StringComparer.OrdinalIgnoreCase) &&
                !args.Contains("--self-test", StringComparer.OrdinalIgnoreCase) &&
                !args.Contains("--ui-snapshot", StringComparer.OrdinalIgnoreCase))
                System.Windows.MessageBox.Show(ex.Message, "Codex Synced", System.Windows.MessageBoxButton.OK, System.Windows.MessageBoxImage.Error);
            return 1;
        }
    }
}

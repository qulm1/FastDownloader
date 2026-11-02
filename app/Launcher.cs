using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
internal static class Launcher {
    [STAThread]
    private static int Main(string[] args) {
        bool verify = args.Length == 1 && args[0] == "--verify-startup";
        try {
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(root, "app", "FastDownloadGui.ps1");
            if (!File.Exists(script)) throw new FileNotFoundException("Missing app folder. Keep FastDownloader.exe and app together.", script);
            if (!File.Exists(Path.Combine(root, "app", "bin", "aria2c.exe"))) throw new FileNotFoundException("Missing bundled download engine in app\\bin. Extract the complete portable package.");
            string shell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
            var start = new ProcessStartInfo(shell);
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.WorkingDirectory = Path.Combine(root, "app");
            start.Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + script + "\" -StateDir \"" + Path.Combine(root, "state") + "\"" + (verify ? " -LibraryOnly" : "");
            using (Process child = Process.Start(start)) {
                child.WaitForExit();
                if (child.ExitCode != 0) throw new InvalidOperationException("The application could not start (exit " + child.ExitCode + ").");
            }
            return 0;
        } catch (Exception error) {
            if (!verify) MessageBox.Show(error.Message, "FastDownloader", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
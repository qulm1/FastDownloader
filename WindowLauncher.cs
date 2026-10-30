using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Windows.Forms;

internal static class WindowLauncher {
    [STAThread]
    private static void Main(string[] args) {
        Application.EnableVisualStyles();
        bool check = Array.IndexOf(args,"--check") >= 0;
        string report = null;
        try {
            int reportIndex=Array.IndexOf(args,"--check-report");
            if(reportIndex>=0) {
                if(reportIndex+1>=args.Length||!check)throw new ArgumentException("--check-report 必须与 --check 和报告文件路径一起使用。");
                report=Path.GetFullPath(args[reportIndex+1]);
            }
            string root = Directory.GetParent(AppDomain.CurrentDomain.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar)).FullName;
            string script = Path.Combine(root, "DownloadWindow.ps1");
            if (!File.Exists(script)) throw new FileNotFoundException("缺少 DownloadWindow.ps1，请完整解压便携包。删减文件会导致无法启动。");
            // Process-only policy, equivalent to the existing .cmd launcher.
            // Machine/User group policies still take precedence.
            Environment.SetEnvironmentVariable("PSExecutionPolicyPreference", "Bypass", EnvironmentVariableTarget.Process);
            using (var runspace = RunspaceFactory.CreateRunspace()) {
                runspace.ApartmentState = ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                runspace.Open();
                using (var ps = PowerShell.Create()) {
                    ps.Runspace = runspace;
                    ps.AddCommand(script);
                    if(check)ps.AddParameter("LayoutOnly",true);
                    for (int i = 0; i < args.Length; i++) {
                        if(args[i]=="--check")continue;
                        if(args[i]=="--check-report"){i++;continue;}
                        if (i + 1 >= args.Length || (args[i] != "--state-dir" && args[i] != "--download-dir"))
                            throw new ArgumentException("支持参数：--state-dir 目录、--download-dir 目录。");
                        ps.AddParameter(args[i] == "--state-dir" ? "StateDir" : "DownloadDir", args[i + 1]);
                        i++;
                    }
                    ps.Invoke();
                    if (ps.HadErrors) throw new InvalidOperationException(ps.Streams.Error[0].ToString());
                }
            }
            if(check && report!=null)File.WriteAllText(report,"PASS: packaged launcher loaded all window modules without showing a window.");
        } catch (Exception error) {
            if(check) {
                if(report!=null)try{File.WriteAllText(report,"FAIL: "+error.Message);}catch{}
            } else MessageBox.Show(error.Message, "极速下载助手：启动失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
            Environment.ExitCode = 1;
        }
    }
}

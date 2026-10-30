// Local engine control for the Windows UI. No listening service is installed.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace FastDownloader {
    public sealed class RpcReply {
        public bool Success;
        public string Json;
        public string Error;
    }

    public sealed class WindowEngine : IDisposable {
        private readonly HttpClient http;
        private readonly string secret;
        private readonly string endpoint;
        public readonly Process Process;
        public readonly int Port;

        public static int FindPort() {
            var listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            int port = ((IPEndPoint)listener.LocalEndpoint).Port;
            listener.Stop();
            return port;
        }

        // Windows CommandLineToArgvW quoting, including trailing backslashes.
        public static string Quote(string value) {
            var result = new StringBuilder("\"");
            int slashes = 0;
            foreach (char ch in value) {
                if (ch == '\\') { slashes++; continue; }
                if (ch == '"') {
                    result.Append('\\', slashes * 2 + 1).Append('"');
                } else {
                    result.Append('\\', slashes).Append(ch);
                }
                slashes = 0;
            }
            return result.Append('\\', slashes * 2).Append('"').ToString();
        }

        public WindowEngine(string executable, string[] arguments, int port, string token) {
            Port = port;
            secret = token;
            endpoint = "http://127.0.0.1:" + port + "/jsonrpc";
            var handler = new HttpClientHandler { UseProxy = false };
            http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(2) };
            var quoted = new List<string>();
            foreach (string argument in arguments) quoted.Add(Quote(argument));
            Process = new Process { StartInfo = new ProcessStartInfo {
                FileName = executable, Arguments = string.Join(" ", quoted),
                UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true
            }};
            // Drain both pipes without accumulating URLs, tokens or unbounded output.
            Process.OutputDataReceived += delegate { };
            Process.ErrorDataReceived += delegate { };
            try {
                Process.Start();
                Process.BeginOutputReadLine();
                Process.BeginErrorReadLine();
            } catch { Process.Dispose(); http.Dispose(); throw; }
        }

        private async Task<RpcReply> Send(string method, object[] parameters) {
            try {
                var serializer = new JavaScriptSerializer { MaxJsonLength = 4 * 1024 * 1024 };
                string body = serializer.Serialize(new Dictionary<string, object> {
                    { "jsonrpc", "2.0" }, { "id", "window" },
                    { "method", method }, { "params", parameters }
                });
                using (var content = new StringContent(body, Encoding.UTF8, "application/json"))
                using (var response = await http.PostAsync(endpoint, content).ConfigureAwait(false)) {
                    string json = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                    if (!response.IsSuccessStatusCode) return new RpcReply { Error = "引擎控制请求失败（HTTP " + (int)response.StatusCode + "）" };
                    var root = serializer.Deserialize<Dictionary<string, object>>(json);
                    if (root.ContainsKey("error")) return new RpcReply { Error = "引擎拒绝了控制请求，请停止后重试。" };
                    return new RpcReply { Success = true, Json = json };
                }
            } catch { return new RpcReply { Error = "暂时无法连接本机下载引擎。" }; }
        }

        public Task<RpcReply> CommandAsync(string method) {
            if (method != "aria2.pauseAll" && method != "aria2.unpauseAll" &&
                method != "aria2.shutdown" && method != "aria2.forceShutdown")
                throw new ArgumentException("Unsupported command");
            return Send(method, new object[] { "token:" + secret });
        }

        public Task<RpcReply> PollAsync() {
            var calls = new object[] {
                new { methodName = "aria2.getGlobalStat", @params = new object[] { "token:" + secret } },
                new { methodName = "aria2.tellActive", @params = new object[] { "token:" + secret } },
                new { methodName = "aria2.tellWaiting", @params = new object[] { "token:" + secret, 0, 1000 } },
                new { methodName = "aria2.tellStopped", @params = new object[] { "token:" + secret, 0, 1000 } }
            };
            return Send("system.multicall", new object[] { calls });
        }

        public void Dispose() {
            http.Dispose();
            Process.Dispose();
        }
    }
}

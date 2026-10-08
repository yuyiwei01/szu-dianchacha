using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Collections.Generic;
using System.Windows.Forms;

[assembly: AssemblyTitle("SZU电查查")]
[assembly: AssemblyDescription("深大宿舍电量查询 · 免安装本地网页版")]
[assembly: AssemblyProduct("SZU电查查")]
[assembly: AssemblyVersion("1.3.0.0")]
[assembly: AssemblyFileVersion("1.3.0.0")]

internal static class Launcher
{
    private static readonly string BuildId = "__BUILD_ID__";
    private static readonly string Root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SzuElectricity");
    private static readonly JavaScriptSerializer Json = new JavaScriptSerializer();

    [STAThread]
    private static void Main(string[] args)
    {
        bool openBrowser = Array.IndexOf(args, "--no-browser") < 0;
        Process service = null;
        try
        {
            // Serialize startup only. Later launches reuse the running matching build.
            using (Mutex mutex = new Mutex(false, "Local\\SzuElectricity.Portable.Startup"))
            {
                bool acquired;
                try { acquired = mutex.WaitOne(TimeSpan.FromSeconds(30)); }
                catch (AbandonedMutexException) { acquired = true; }
                if (!acquired) throw new Exception("另一个窗口正在启动查询服务，请稍后重试。");
                try
                {
                    for (int port = 18765; port < 18775; port++)
                    {
                        if (Healthy(port)) { if (openBrowser) Browse(port); return; }
                    }
                    string folder = Extract();
                    int selectedPort = FreePort();
                    string shell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
                    if (!File.Exists(shell)) throw new Exception("未找到 Windows PowerShell。请在 Windows 10 或 Windows 11 上运行。");
                    Directory.CreateDirectory(Path.Combine(Root, "logs"));
                    string log = Path.Combine(Root, "logs", "portable-" + Process.GetCurrentProcess().Id + ".log");
                    using (StreamWriter writer = new StreamWriter(log, false, new UTF8Encoding(false)))
                    {
                        writer.AutoFlush = true;
                        ProcessStartInfo info = new ProcessStartInfo(shell);
                        info.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + Path.Combine(folder, "server.ps1") + "\" -Port " + selectedPort + " -BuildId " + BuildId;
                        info.WorkingDirectory = folder;
                        info.UseShellExecute = false;
                        info.CreateNoWindow = true;
                        info.WindowStyle = ProcessWindowStyle.Hidden;
                        info.RedirectStandardOutput = true;
                        info.RedirectStandardError = true;
                        service = new Process();
                        service.StartInfo = info;
                        service.OutputDataReceived += (sender, e) => { if (e.Data != null) lock (writer) writer.WriteLine(e.Data); };
                        service.ErrorDataReceived += (sender, e) => { if (e.Data != null) lock (writer) writer.WriteLine(e.Data); };
                        service.Start();
                        service.BeginOutputReadLine();
                        service.BeginErrorReadLine();
                        bool ready = false;
                        for (int i = 0; i < 60; i++)
                        {
                            if (service.HasExited) break;
                            if (Healthy(selectedPort)) { ready = true; break; }
                            Thread.Sleep(200);
                        }
                        if (!ready)
                        {
                            if (!service.HasExited) service.Kill();
                            service.WaitForExit();
                            throw new Exception("查询服务启动失败。日志位置：\n" + log);
                        }
                        if (openBrowser)
                        {
                            try { Browse(selectedPort); }
                            catch
                            {
                                if (!service.HasExited) service.Kill();
                                service.WaitForExit();
                                throw new Exception("无法打开默认浏览器。请设置默认浏览器后重新启动。");
                            }
                        }
                        mutex.ReleaseMutex();
                        acquired = false;
                        // Stay hidden to collect logs until the user closes the service in the page.
                        service.WaitForExit();
                    }
                }
                finally { if (acquired) mutex.ReleaseMutex(); }
            }
        }
        catch (Exception e)
        {
            if (service != null)
            {
                try { if (!service.HasExited) service.Kill(); service.WaitForExit(); } catch { }
            }
            MessageBox.Show(e.Message, "SZU电查查 · 启动失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
            Environment.ExitCode = 1;
        }
    }

    private static bool Healthy(int port)
    {
        try
        {
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create("http://127.0.0.1:" + port + "/api/health");
            request.Proxy = null;
            request.Timeout = 500;
            request.ReadWriteTimeout = 500;
            using (WebResponse response = request.GetResponse())
            using (StreamReader reader = new StreamReader(response.GetResponseStream(), Encoding.UTF8))
            {
                Dictionary<string, object> data = Json.Deserialize<Dictionary<string, object>>(reader.ReadToEnd());
                return data.ContainsKey("app") && (string)data["app"] == "szu-electricity-local" && data.ContainsKey("buildId") && (string)data["buildId"] == BuildId;
            }
        }
        catch { return false; }
    }

    private static int FreePort()
    {
        for (int port = 18765; port < 18775; port++)
        {
            TcpListener listener = new TcpListener(IPAddress.Loopback, port);
            try { listener.Start(); return port; }
            catch (SocketException) { }
            finally { listener.Stop(); }
        }
        throw new Exception("本地查询端口均被占用，请关闭已有查询服务后重试。");
    }

    private static string Extract()
    {
        string target = Path.Combine(Root, "app", BuildId);
        Directory.CreateDirectory(target);
        using (Stream payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("app.zip"))
        using (ZipArchive archive = new ZipArchive(payload, ZipArchiveMode.Read))
        {
            foreach (ZipArchiveEntry entry in archive.Entries)
            {
                string file = Path.GetFullPath(Path.Combine(target, entry.FullName.Replace('/', Path.DirectorySeparatorChar)));
                if (!file.StartsWith(target + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new Exception("内置资源路径无效。");
                Directory.CreateDirectory(Path.GetDirectoryName(file));
                using (Stream input = entry.Open())
                using (FileStream output = new FileStream(file, FileMode.Create, FileAccess.Write, FileShare.Read)) input.CopyTo(output);
            }
        }
        return target;
    }

    private static void Browse(int port)
    {
        Process.Start(new ProcessStartInfo("http://127.0.0.1:" + port) { UseShellExecute = true });
    }
}

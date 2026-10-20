using Microsoft.Win32;

namespace BatteriesPC;

static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        bool fromStartup = args.Contains("--tray");
        var mutex = new Mutex(false, @"Local\BatteriesPC");
        if (!TryOwn(mutex, TimeSpan.Zero))
        {
            if (fromStartup)
            {
                // Windows の起動時：すでに動いているならそのまま任せる
                return;
            }
            // 手で起動したとき：古い版が動いている可能性があるので、止めて入れ替わる
            StopOtherInstances();
            if (!TryOwn(mutex, TimeSpan.FromSeconds(10)))
            {
                Signal.Raise();
                return;
            }
        }
        ApplicationConfiguration.Initialize();
        Application.Run(new TrayContext(startHidden: fromStartup));
        GC.KeepAlive(mutex);
    }

    static bool TryOwn(Mutex mutex, TimeSpan timeout)
    {
        try { return mutex.WaitOne(timeout); }
        catch (AbandonedMutexException) { return true; } // 前のものが止められた
    }

    /// <summary>ほかに動いているバッテリー送信（古い版を含む）を止める</summary>
    static void StopOtherInstances()
    {
        var me = Environment.ProcessId;
        foreach (var p in System.Diagnostics.Process.GetProcesses())
        {
            try
            {
                if (p.Id != me && p.ProcessName.StartsWith("BatteriesPC", StringComparison.OrdinalIgnoreCase))
                {
                    p.Kill();
                    p.WaitForExit(5000);
                }
            }
            catch
            {
                // 止められないものは飛ばす
            }
            finally
            {
                p.Dispose();
            }
        }
    }
}

/// <summary>2つ目を起動したとき、1つ目に画面を開かせる合図</summary>
static class Signal
{
    const string Name = @"Local\BatteriesPC-show";

    public static void Raise()
    {
        try
        {
            using var e = EventWaitHandle.OpenExisting(Name);
            e.Set();
        }
        catch
        {
        }
    }

    public static EventWaitHandle Create() => new(false, EventResetMode.AutoReset, Name);
}

/// <summary>Windows の起動時に自動で起動する設定（レジストリの Run）</summary>
static class Startup
{
    const string Key = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const string Value = "BatteriesPC";

    static string Command => $"\"{Environment.ProcessPath}\" --tray";

    public static bool Enabled
    {
        get
        {
            using var k = Registry.CurrentUser.OpenSubKey(Key);
            return k?.GetValue(Value) is string s && s.Equals(Command, StringComparison.OrdinalIgnoreCase);
        }
        set
        {
            using var k = Registry.CurrentUser.CreateSubKey(Key);
            if (value) k.SetValue(Value, Command);
            else k.DeleteValue(Value, throwOnMissingValue: false);
        }
    }

    public static bool Registered
    {
        get
        {
            using var k = Registry.CurrentUser.OpenSubKey(Key);
            return k?.GetValue(Value) != null;
        }
    }
}

static class AppInfo
{
    public static string Version
    {
        get
        {
            var v = typeof(AppInfo).Assembly.GetName().Version;
            return v == null ? "?" : $"{v.Major}.{v.Minor}.{v.Build}";
        }
    }
}

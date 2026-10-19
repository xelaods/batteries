using Microsoft.Win32;

namespace BatteriesPC;

static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        using var mutex = new Mutex(true, @"Local\BatteriesPC", out bool first);
        if (!first)
        {
            // すでに起動している：もう一方に画面を開いてもらう
            Signal.Raise();
            return;
        }
        ApplicationConfiguration.Initialize();
        Application.Run(new TrayContext(startHidden: args.Contains("--tray")));
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

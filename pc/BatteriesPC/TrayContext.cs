using System.Diagnostics;
using System.Reflection;

namespace BatteriesPC;

/// <summary>タスクトレイに常駐し、定期的に読み取って送る</summary>
public sealed class TrayContext : ApplicationContext
{
    /// <summary>値が変わったときでも、これより短い間隔では送らない（ntfy.sh の無料枠を守るため）</summary>
    static readonly TimeSpan MinInterval = TimeSpan.FromMinutes(10);
    /// <summary>値が変わらなくても、この間隔で送る（PC が動いていることを知らせる）</summary>
    static readonly TimeSpan Heartbeat = TimeSpan.FromMinutes(60);

    readonly Config _config;
    readonly AirPodsWatcher _airPods;
    readonly NotifyIcon _tray;
    readonly System.Windows.Forms.Timer _timer;
    readonly EventWaitHandle _showSignal;
    readonly Icon _icon;
    /// <summary>ほかのスレッドから画面側の処理を呼ぶための見えない部品</summary>
    readonly Control _ui = new();
    StatusForm? _form;

    string _lastSignature = "";
    DateTime _lastSentAt = DateTime.MinValue;
    bool _sending;

    public DateTime? LastSentAt => _lastSentAt == DateTime.MinValue ? null : _lastSentAt;
    public string LastResult { get; private set; } = "まだ送っていません";
    public bool LastOk { get; private set; } = true;
    public Config Config => _config;
    public AirPodsWatcher AirPods => _airPods;
    public Icon AppIcon => _icon;

    public TrayContext(bool startHidden)
    {
        _ = _ui.Handle; // 先に作っておく
        _config = Config.Load();
        _icon = LoadIcon();

        _airPods = new AirPodsWatcher(_config);
        _airPods.Changed += () => _ui.BeginInvoke(new Action(() => _form?.RequestRefresh()));
        _airPods.Start();

        var menu = new ContextMenuStrip();
        menu.Items.Add("状態と iPhone 連携を開く", null, (_, _) => ShowForm());
        menu.Items.Add("今すぐ送る", null, async (_, _) => await SendAsync(force: true));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("マウスの情報を書き出す", null, (_, _) => DumpHid());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("終了", null, (_, _) => Quit());

        _tray = new NotifyIcon
        {
            Icon = _icon,
            Text = "バッテリー送信",
            ContextMenuStrip = menu,
            Visible = true,
        };
        _tray.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) ShowForm(); };

        // 初めて起動したときは、Windows の起動時に自動で起動するようにしておく
        if (_config.IsNew && !Startup.Registered)
        {
            try { Startup.Enabled = true; } catch { }
        }

        _timer = new System.Windows.Forms.Timer { Interval = 60_000 };
        _timer.Tick += async (_, _) => await SendAsync(force: false);
        _timer.Start();

        // 2つ目を起動されたら画面を開く
        _showSignal = Signal.Create();
        ThreadPool.RegisterWaitForSingleObject(_showSignal, (_, _) =>
        {
            _ui.BeginInvoke(new Action(ShowForm));
        }, null, Timeout.Infinite, executeOnlyOnce: false);

        // 起動して少ししたら1回送る（Bluetooth の電波を少し集めてから）
        _ = Task.Delay(TimeSpan.FromSeconds(20)).ContinueWith(_ =>
            _ui.BeginInvoke(new Action(async () => await SendAsync(force: true))));

        if (!startHidden || _config.IsNew)
        {
            // 最初は画面を開いて、iPhone とつなぐ QR コードを見せる
            Application.Idle += ShowOnce;
        }
        UpdateTrayText();
    }

    void ShowOnce(object? sender, EventArgs e)
    {
        Application.Idle -= ShowOnce;
        ShowForm();
    }

    static Icon LoadIcon()
    {
        try
        {
            using var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("app.ico");
            if (s != null) return new Icon(s);
        }
        catch { }
        return SystemIcons.Application;
    }

    public void ShowForm()
    {
        if (_form == null || _form.IsDisposed)
        {
            _form = new StatusForm(this);
        }
        _form.Show();
        if (_form.WindowState == FormWindowState.Minimized) _form.WindowState = FormWindowState.Normal;
        _form.Activate();
        _form.RequestRefresh();
    }

    public RelayMessage CurrentMessage() => Collector.Build(_config, _airPods.Snapshot());

    public async Task SendAsync(bool force)
    {
        if (_sending) return;
        var message = CurrentMessage();
        var signature = Collector.Signature(message);
        var since = DateTime.Now - _lastSentAt;
        bool due = force
            || since >= Heartbeat
            || (signature != _lastSignature && since >= MinInterval);
        UpdateTrayText(message);
        if (!due || message.Devices.Count == 0)
        {
            _form?.RequestRefresh();
            return;
        }

        _sending = true;
        try
        {
            var (ok, detail) = await Relay.SendAsync(_config.Topic, message);
            LastOk = ok;
            LastResult = detail;
            if (ok)
            {
                _lastSentAt = DateTime.Now;
                _lastSignature = signature;
                _config.Save(); // AirPods の最後の値も残す
            }
        }
        finally
        {
            _sending = false;
            _form?.RequestRefresh();
        }
    }

    void UpdateTrayText(RelayMessage? message = null)
    {
        message ??= CurrentMessage();
        var parts = new List<string>();
        foreach (var d in message.Devices)
        {
            if (d.Kind == "computer") parts.Add($"PC {d.Parts[0].Level}%");
            else if (d.Kind == "airpods")
            {
                var buds = d.Parts.Where(p => p.Id is "left" or "right").Select(p => p.Level).DefaultIfEmpty(-1).Min();
                if (buds >= 0) parts.Add($"AirPods {buds}%");
            }
        }
        var text = "バッテリー送信" + (parts.Count > 0 ? "\n" + string.Join(" / ", parts) : "");
        _tray.Text = text.Length > 120 ? text[..120] : text;
    }

    public void ApplyTopic(string topic)
    {
        _config.Topic = topic;
        _config.Save();
        _lastSignature = "";
        _ = SendAsync(force: true);
    }

    public void ApplyPcName(string name)
    {
        name = name.Trim();
        if (name.Length == 0 || name == _config.PcName) return;
        var old = _config.PcName;
        _config.PcName = name;
        _config.RememberFormer(null, old);
        _config.Save();
        _lastSignature = "";
        _ = SendAsync(force: true);
    }

    public void DumpHid()
    {
        try
        {
            var path = HidDump.Write();
            Process.Start(new ProcessStartInfo("notepad.exe", $"\"{path}\"") { UseShellExecute = true });
        }
        catch (Exception e)
        {
            MessageBox.Show("書き出せませんでした：" + e.Message, "バッテリー送信");
        }
    }

    void Quit()
    {
        _timer.Stop();
        _airPods.Dispose();
        _config.Save();
        _tray.Visible = false;
        _form?.Dispose();
        ExitThread();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _tray.Dispose();
            _timer.Dispose();
            _showSignal.Dispose();
            _ui.Dispose();
        }
        base.Dispose(disposing);
    }
}

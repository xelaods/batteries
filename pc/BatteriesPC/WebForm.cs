using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using QRCoder;

namespace BatteriesPC;

/// <summary>
/// EasyUI（React）で作った画面を WebView2 で表示する。
/// 画面（pc/ui）とは postMessage で JSON をやりとりする（形は pc/ui/src/bridge.ts と同じ）。
/// </summary>
public sealed class WebForm : Form
{
    static readonly Color Background = Color.FromArgb(17, 17, 19); // EasyUI の --bg

    readonly TrayContext _app;
    readonly WebView2 _web;
    readonly System.Windows.Forms.Timer _timer;
    bool _ready;
    string _qrTopic = "";
    string _qrDataUrl = "";

    /// <summary>この PC で WebView2（Edge の部品）が使えるか。Windows 10/11 には普通入っている</summary>
    public static bool IsAvailable()
    {
        try
        {
            if (LoadHtml() == null) return false;
            return !string.IsNullOrEmpty(CoreWebView2Environment.GetAvailableBrowserVersionString());
        }
        catch
        {
            return false;
        }
    }

    static string? LoadHtml()
    {
        using var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("ui.html");
        if (s == null) return null;
        using var r = new StreamReader(s);
        return r.ReadToEnd();
    }

    public WebForm(TrayContext app)
    {
        _app = app;
        Text = $"バッテリー送信 {AppInfo.Version}";
        Icon = app.AppIcon;
        BackColor = Background;
        AutoScaleMode = AutoScaleMode.Dpi;
        AutoScaleDimensions = new SizeF(96f, 96f);
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(940, 680);
        MinimumSize = new Size(820, 560);

        _web = new WebView2
        {
            Dock = DockStyle.Fill,
            DefaultBackgroundColor = Background,
        };
        Controls.Add(_web);

        _timer = new System.Windows.Forms.Timer { Interval = 2000 };
        _timer.Tick += (_, _) => { if (Visible) PushState(); };
        _timer.Start();

        Load += async (_, _) => await InitAsync();
    }

    async Task InitAsync()
    {
        try
        {
            var folder = Path.Combine(Config.Folder, "WebView2");
            var env = await CoreWebView2Environment.CreateAsync(null, folder);
            await _web.EnsureCoreWebView2Async(env);
            var core = _web.CoreWebView2;
            core.Settings.AreDefaultContextMenusEnabled = false;
            core.Settings.AreDevToolsEnabled = false;
            core.Settings.IsZoomControlEnabled = false;
            core.Settings.IsStatusBarEnabled = false;
            core.Settings.AreBrowserAcceleratorKeysEnabled = false;
            core.Settings.IsSwipeNavigationEnabled = false;
            core.WebMessageReceived += OnMessage;
            // 画面の中のリンクなどで別のページに移らないようにする
            core.NewWindowRequested += (_, e) => e.Handled = true;
            core.NavigateToString(LoadHtml() ?? "<p>画面を読み込めませんでした</p>");
        }
        catch (Exception e)
        {
            Debug.WriteLine(e);
            // WebView2 が動かないときは従来の画面に切り替える
            BeginInvoke(new Action(_app.FallBackToClassic));
        }
    }

    public void RequestRefresh()
    {
        if (IsDisposed || !IsHandleCreated) return;
        if (InvokeRequired) BeginInvoke(new Action(PushState));
        else PushState();
    }

    // ---------------------------------------------------------------- 画面へ送る

    void Post(object message)
    {
        if (!_ready || _web.CoreWebView2 == null) return;
        try
        {
            _web.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(message));
        }
        catch
        {
            // 閉じている途中など
        }
    }

    void Toast(string text, string tone = "neutral") => Post(new { type = "toast", text, tone });

    static long? Unix(DateTime? local) =>
        local is { } t ? new DateTimeOffset(t.ToUniversalTime()).ToUnixTimeSeconds() : null;

    void PushState()
    {
        if (!_ready) return;
        var config = _app.Config;
        var message = _app.CurrentMessage();
        var pc = PcBattery.Read();
        var air = _app.AirPods;

        if (_qrTopic != config.Topic)
        {
            _qrTopic = config.Topic;
            _qrDataUrl = MakeQr($"batteries://pair?code={config.Topic}");
        }

        bool startup;
        try { startup = Startup.Enabled; } catch { startup = false; }

        var state = new
        {
            version = AppInfo.Version,
            pcName = config.PcName,
            topic = config.Topic,
            topicGrouped = Config.Grouped(config.Topic),
            qr = _qrDataUrl,
            pc = pc == null ? null : new { level = pc.Level, charging = pc.Charging, plugged = pc.PluggedIn },
            airpods = message.Devices
                .Where(d => d.Kind == "airpods")
                .Select(d => new
                {
                    model = d.Model ?? 0,
                    name = ProximityPairing.ModelName(d.Model ?? 0),
                    parts = d.Parts.Select(p => new { id = p.Id, level = p.Level, charging = p.Charging, at = p.At }),
                }),
            bluetooth = new
            {
                status = air.Status,
                lastSignalAt = Unix(air.LastSignalAt),
                lastRssi = air.LastRssi,
                signals = air.SignalsSeen,
            },
            send = new
            {
                lastSentAt = Unix(_app.LastSentAt),
                result = _app.LastResult,
                ok = _app.LastOk,
                sending = _app.IsSending,
            },
            settings = new
            {
                startup,
                readAirPods = config.ReadAirPods,
                swapSides = config.SwapSides,
                rssi = config.RssiThreshold,
            },
            dataFolder = Config.Folder,
            now = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
        };
        Post(new { type = "state", state });
    }

    static string MakeQr(string text)
    {
        using var gen = new QRCodeGenerator();
        using var data = gen.CreateQrCode(text, QRCodeGenerator.ECCLevel.M);
        var png = new PngByteQRCode(data).GetGraphic(12, drawQuietZones: false);
        return "data:image/png;base64," + Convert.ToBase64String(png);
    }

    // ---------------------------------------------------------------- 画面から受け取る

    async void OnMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        JsonElement m;
        try
        {
            m = JsonDocument.Parse(e.WebMessageAsJson).RootElement;
        }
        catch
        {
            return;
        }
        string type = m.TryGetProperty("type", out var t) ? t.GetString() ?? "" : "";
        var config = _app.Config;

        switch (type)
        {
            case "ready":
                _ready = true;
                PushState();
                break;

            case "send":
                await _app.SendAsync(force: true);
                if (_app.LastOk) Toast("iPhone に送りました", "success");
                else Toast(_app.LastResult, "danger");
                break;

            case "copy":
                try
                {
                    Clipboard.SetText(config.Topic);
                    Toast("合言葉をコピーしました", "success");
                }
                catch
                {
                    Toast("コピーできませんでした", "danger");
                }
                break;

            case "join":
                var topic = Config.NormalizeTopic(m.TryGetProperty("topic", out var tp) ? tp.GetString() ?? "" : "");
                if (topic == null)
                {
                    Toast("合言葉の形が違います", "danger");
                    break;
                }
                _app.ApplyTopic(topic);
                Toast("合言葉を変えました", "success");
                break;

            case "rename":
                var name = m.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                if (name.Trim().Length == 0) break;
                _app.ApplyPcName(name);
                Toast("名前を変えました", "success");
                break;

            case "setting":
                var key = m.TryGetProperty("key", out var k) ? k.GetString() : null;
                if (!m.TryGetProperty("value", out var v)) break;
                try
                {
                    switch (key)
                    {
                        case "startup":
                            Startup.Enabled = v.GetBoolean();
                            break;
                        case "readAirPods":
                            config.ReadAirPods = v.GetBoolean();
                            break;
                        case "swapSides":
                            config.SwapSides = v.GetBoolean();
                            break;
                        case "rssi":
                            config.RssiThreshold = Math.Clamp(v.GetInt32(), -100, -30);
                            break;
                    }
                    config.Save();
                }
                catch (Exception ex)
                {
                    Toast("設定できませんでした：" + ex.Message, "danger");
                }
                break;

            case "dumpHid":
                _app.DumpHid();
                Toast("デスクトップに batteries-hid.txt を作りました");
                break;

            case "openFolder":
                try
                {
                    Directory.CreateDirectory(Config.Folder);
                    Process.Start(new ProcessStartInfo("explorer.exe", $"\"{Config.Folder}\"") { UseShellExecute = true });
                }
                catch { }
                break;
        }
        PushState();
    }

    // ---------------------------------------------------------------- ウィンドウ

    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        // タイトルバーも暗い色にする（Windows 10 20H1 以降・11）
        try
        {
            int on = 1;
            DwmSetWindowAttribute(Handle, 20, ref on, sizeof(int));
            // Windows 11：タイトルバーの色を画面の背景に合わせる（COLORREF は 0x00BBGGRR）
            int caption = Background.R | (Background.G << 8) | (Background.B << 16);
            DwmSetWindowAttribute(Handle, 35, ref caption, sizeof(int));
        }
        catch { }
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        // 閉じるボタンでは隠すだけ（タスクトレイで動き続ける）
        if (e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            Hide();
            return;
        }
        base.OnFormClosing(e);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _timer.Dispose();
            _web.Dispose();
        }
        base.Dispose(disposing);
    }
}

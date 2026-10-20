using QRCoder;

namespace BatteriesPC;

/// <summary>状態の表示と、iPhone とつなぐための QR コード</summary>
public sealed class StatusForm : Form
{
    readonly TrayContext _app;
    readonly Label _values = new() { AutoSize = true, Font = new Font("Yu Gothic UI", 10.5f) };
    readonly Label _airStatus = new() { AutoSize = true, ForeColor = SystemColors.GrayText };
    readonly Label _sendStatus = new() { AutoSize = true };
    readonly PictureBox _qr = new() { Size = new Size(200, 200), SizeMode = PictureBoxSizeMode.Zoom, Margin = new Padding(0, 4, 12, 4) };
    readonly Label _topic = new() { AutoSize = true, Font = new Font("Consolas", 15f, FontStyle.Bold), Margin = new Padding(0, 8, 0, 4) };
    readonly TextBox _joinBox = new() { Width = 260, PlaceholderText = "例：bat-7k2m 9qx4 vd8p n3hr" };
    readonly TextBox _nameBox = new() { Width = 200 };
    readonly CheckBox _startup = new() { Text = "Windows の起動時に自動で起動する", AutoSize = true };
    readonly CheckBox _readAirPods = new() { Text = "AirPods を読み取る", AutoSize = true };
    readonly CheckBox _swap = new() { Text = "AirPods の左右を入れ替える", AutoSize = true };
    readonly NumericUpDown _rssi = new() { Minimum = -100, Maximum = -30, Width = 70 };
    string _qrTopic = "";
    bool _loading;

    public StatusForm(TrayContext app)
    {
        _app = app;
        Text = $"バッテリー送信 {AppInfo.Version}";
        Icon = app.AppIcon;
        Font = new Font("Yu Gothic UI", 9.5f);
        AutoScaleMode = AutoScaleMode.Dpi;
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        Padding = new Padding(16);

        var root = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            AutoSize = true,
            Dock = DockStyle.Fill,
        };

        // いまの値
        root.Controls.Add(Header("いまの値"));
        root.Controls.Add(_values);
        root.Controls.Add(_airStatus);

        // iPhone とつなぐ
        root.Controls.Add(Header("iPhone とつなぐ"));
        var pair = new FlowLayoutPanel { FlowDirection = FlowDirection.LeftToRight, AutoSize = true, WrapContents = false };
        pair.Controls.Add(_qr);
        var pairText = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false };
        pairText.Controls.Add(new Label
        {
            Text = "iPhone のカメラでこの QR コードを読み取ると、\nバッテリーアプリに登録されます。\n読み取れないときは、アプリの「PC 連携」に\n下の合言葉を入力してください。",
            AutoSize = true,
        });
        pairText.Controls.Add(_topic);
        var copy = new Button { Text = "合言葉をコピー", AutoSize = true };
        copy.Click += (_, _) => Clipboard.SetText(_app.Config.Topic);
        pairText.Controls.Add(copy);
        pair.Controls.Add(pairText);
        root.Controls.Add(pair);

        var joinRow = Row();
        joinRow.Controls.Add(new Label { Text = "ほかの PC の合言葉を使う：", AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 6, 4, 0) });
        joinRow.Controls.Add(_joinBox);
        var join = new Button { Text = "この合言葉にする", AutoSize = true };
        join.Click += (_, _) => Join();
        joinRow.Controls.Add(join);
        root.Controls.Add(joinRow);
        root.Controls.Add(new Label
        {
            Text = "2台目以降の PC は、1台目の合言葉を入れると同じ iPhone に届きます。",
            AutoSize = true,
            ForeColor = SystemColors.GrayText,
        });

        // 設定
        root.Controls.Add(Header("設定"));
        var nameRow = Row();
        nameRow.Controls.Add(new Label { Text = "iPhone に表示する名前：", AutoSize = true, Margin = new Padding(0, 6, 4, 0) });
        nameRow.Controls.Add(_nameBox);
        var saveName = new Button { Text = "変更", AutoSize = true };
        saveName.Click += (_, _) => _app.ApplyPcName(_nameBox.Text);
        nameRow.Controls.Add(saveName);
        root.Controls.Add(nameRow);
        root.Controls.Add(_startup);
        root.Controls.Add(_readAirPods);
        root.Controls.Add(_swap);
        var rssiRow = Row();
        rssiRow.Controls.Add(new Label { Text = "AirPods の電波の強さの基準（dBm）：", AutoSize = true, Margin = new Padding(0, 6, 4, 0) });
        rssiRow.Controls.Add(_rssi);
        rssiRow.Controls.Add(new Label { Text = "小さくすると遠くまで拾う", AutoSize = true, ForeColor = SystemColors.GrayText, Margin = new Padding(8, 6, 0, 0) });
        root.Controls.Add(rssiRow);

        _startup.CheckedChanged += (_, _) =>
        {
            if (_loading) return;
            try { Startup.Enabled = _startup.Checked; }
            catch (Exception e) { MessageBox.Show("設定できませんでした：" + e.Message, Text); }
        };
        _readAirPods.CheckedChanged += (_, _) => { if (!_loading) { _app.Config.ReadAirPods = _readAirPods.Checked; _app.Config.Save(); } };
        _swap.CheckedChanged += (_, _) => { if (!_loading) { _app.Config.SwapSides = _swap.Checked; _app.Config.Save(); } };
        _rssi.ValueChanged += (_, _) => { if (!_loading) { _app.Config.RssiThreshold = (int)_rssi.Value; _app.Config.Save(); } };

        // 送信
        root.Controls.Add(Header("送信"));
        root.Controls.Add(_sendStatus);
        var buttons = Row();
        var send = new Button { Text = "今すぐ送る", AutoSize = true };
        send.Click += async (_, _) => await _app.SendAsync(force: true);
        var dump = new Button { Text = "マウスの情報を書き出す", AutoSize = true };
        dump.Click += (_, _) => _app.DumpHid();
        buttons.Controls.Add(send);
        buttons.Controls.Add(dump);
        root.Controls.Add(buttons);
        root.Controls.Add(new Label
        {
            Text = "値が変わったときは10分ごと、変わらなくても1時間ごとに送ります。\n画面を閉じてもタスクトレイで動き続けます（終了はトレイのアイコンを右クリック）。",
            AutoSize = true,
            ForeColor = SystemColors.GrayText,
        });

        Controls.Add(root);
        LoadSettings();
        RefreshValues();

        var timer = new System.Windows.Forms.Timer { Interval = 5000 };
        timer.Tick += (_, _) => { if (Visible) RefreshValues(); };
        timer.Start();
        FormClosed += (_, _) => timer.Dispose();
    }

    static Label Header(string text) => new()
    {
        Text = text,
        AutoSize = true,
        Font = new Font("Yu Gothic UI", 11f, FontStyle.Bold),
        Margin = new Padding(0, 14, 0, 4),
    };

    static FlowLayoutPanel Row() => new()
    {
        FlowDirection = FlowDirection.LeftToRight,
        AutoSize = true,
        WrapContents = false,
        Margin = new Padding(0, 2, 0, 2),
    };

    void LoadSettings()
    {
        _loading = true;
        _nameBox.Text = _app.Config.PcName;
        try { _startup.Checked = Startup.Enabled; } catch { }
        _readAirPods.Checked = _app.Config.ReadAirPods;
        _swap.Checked = _app.Config.SwapSides;
        _rssi.Value = Math.Clamp(_app.Config.RssiThreshold, -100, -30);
        _loading = false;
    }

    void Join()
    {
        var topic = Config.NormalizeTopic(_joinBox.Text);
        if (topic == null)
        {
            MessageBox.Show("合言葉の形が違います（英小文字・数字・ハイフンの8文字以上）。", Text);
            return;
        }
        if (MessageBox.Show($"合言葉を {Config.Grouped(topic)} に変えますか？\n今の合言葉で連携している iPhone には届かなくなります。", Text,
                MessageBoxButtons.OKCancel) != DialogResult.OK) return;
        _joinBox.Text = "";
        _app.ApplyTopic(topic);
        RefreshValues();
    }

    public void RequestRefresh()
    {
        if (IsDisposed || !IsHandleCreated) return;
        if (InvokeRequired) BeginInvoke(new Action(RefreshValues));
        else RefreshValues();
    }

    void RefreshValues()
    {
        var message = _app.CurrentMessage();
        var lines = new List<string>();
        long now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        foreach (var d in message.Devices)
        {
            if (d.Kind == "computer")
            {
                var p = d.Parts[0];
                lines.Add($"💻  {d.Name}　{p.Level}%{(p.Charging ? "（充電中）" : "")}");
            }
            else if (d.Kind == "airpods")
            {
                string Part(string id, string label)
                {
                    var p = d.Parts.FirstOrDefault(x => x.Id == id);
                    return p == null ? $"{label} —" : $"{label} {p.Level}%{(p.Charging ? "⚡" : "")}";
                }
                var latest = d.Parts.Max(p => p.At);
                lines.Add($"🎧  {ProximityPairing.ModelName(d.Model ?? 0)}　{Part("left", "左")}　{Part("right", "右")}　{Part("case", "ケース")}　（{Ago(now - latest)}）");
            }
        }
        if (PcBattery.Read() == null) lines.Insert(0, "💻  この PC には電池がありません（デスクトップ PC）");
        if (!message.Devices.Any(d => d.Kind == "airpods")) lines.Add("🎧  AirPods はまだ見つかっていません（ケースを開けて PC の近くに置いてください）");
        lines.Add("🖱  マウスは次の段階で対応します");
        _values.Text = string.Join("\n", lines);

        var air = _app.AirPods;
        _airStatus.Text = $"Bluetooth：{air.Status}" + (air.LastSignalAt is { } t ? $"　最後の AirPods 信号 {t:HH:mm:ss}（{air.LastRssi} dBm）" : "");

        var sent = _app.LastSentAt is { } s ? $"最後に送った時刻：{s:M/d HH:mm}" : "まだ送っていません";
        _sendStatus.Text = $"{sent}　{_app.LastResult}";
        _sendStatus.ForeColor = _app.LastOk ? SystemColors.ControlText : Color.Firebrick;

        if (_qrTopic != _app.Config.Topic)
        {
            _qrTopic = _app.Config.Topic;
            _topic.Text = Config.Grouped(_qrTopic);
            _qr.Image?.Dispose();
            _qr.Image = MakeQr($"batteries://pair?code={_qrTopic}");
        }
    }

    static string Ago(long seconds) => seconds switch
    {
        < 60 => "たった今",
        < 3600 => $"{seconds / 60}分前",
        < 86400 => $"{seconds / 3600}時間前",
        _ => $"{seconds / 86400}日前",
    };

    static Image MakeQr(string text)
    {
        using var gen = new QRCodeGenerator();
        using var data = gen.CreateQrCode(text, QRCodeGenerator.ECCLevel.M);
        var png = new PngByteQRCode(data).GetGraphic(10);
        using var ms = new MemoryStream(png);
        using var img = Image.FromStream(ms);
        return new Bitmap(img);
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
}

using HidSharp;
using HidSharp.Reports;

namespace BatteriesPC;

/// <summary>マウスの最後の値</summary>
public sealed class MouseRecord
{
    public int Vid { get; set; }
    public int Pid { get; set; }
    public string Name { get; set; } = "";
    public int Level { get; set; }
    /// <summary>ケーブルがつながっている（充電中）</summary>
    public bool Charging { get; set; }
    public int Millivolts { get; set; }
    /// <summary>実際に読み取った時刻（Unix 秒）</summary>
    public long At { get; set; }

    public string DeviceId => $"mouse-{Vid:x4}-{Pid:x4}";
}

/// <summary>
/// Compx 製チップの無線マウス（ATK・VXE・Pulsar など）の電池をレシーバーから読む。
///
/// 読み方は公開されている調査結果による（MIT の HaloBattery の docs/protocols.md、
/// andrewrabert/python-pulsar-mouse-tool、OpenMouse の ATK/VXE ドライバ）。
/// 17バイト・レポート ID 0x08 のフレームで、コマンド 0x04（電源の情報）を送ると、
///   [6] 電池 %、[7] ケーブル接続中、[8-9] ミリボルト（ビッグエンディアン）、[16] チェックサム
/// が返ってくる。チェックサムは 0x55 − 先頭16バイトの合計。
/// 使う窓口は usage page 0xFF02・usage 0x0002 のコレクション。
/// マウスが止まっていると数秒で応答しなくなるので、応答がないのは普通のこと（最後の値を残す）。
/// </summary>
public sealed class MouseReader
{
    const byte Header = 0x08;
    const byte CmdPower = 0x04;
    const int FrameLength = 17;
    const uint ControlUsage = 0xFF020002;

    /// <summary>この読み方で読めるレシーバー・ケーブル（VID, PID → 名前）</summary>
    static readonly Dictionary<(int Vid, int Pid), string> Known = new()
    {
        [(0x3554, 0xF58A)] = "VXE マウス",           // VXE R1 Pro Max など（1K レシーバー）
        [(0x3554, 0xF58C)] = "VXE マウス",           // 同（ケーブル）
        [(0x3554, 0xF58F)] = "ATK VXE R1 SE+",       // ケーブル
        [(0x373B, 0x1085)] = "ATK VXE R1 SE+",       // 2.4 GHz
        [(0x3554, 0xF508)] = "Pulsar X2 V2 Mini",
        [(0x3554, 0xF507)] = "Pulsar X2 V2 Mini",
        [(0x3710, 0x5406)] = "Pulsar X2 CrazyLight Mini",
        [(0x3710, 0x3414)] = "Pulsar X2 CrazyLight Mini",
        [(0x3770, 0x0200)] = "Hitscan Hyperlight",
        [(0x3770, 0x0100)] = "Hitscan Hyperlight",
    };

    readonly Config _config;
    readonly object _lock = new();

    public string Status { get; private set; } = "まだ調べていません";

    public MouseReader(Config config) => _config = config;

    public static byte Checksum(ReadOnlySpan<byte> bytes)
    {
        int sum = 0;
        foreach (var b in bytes) sum += b;
        return (byte)((0x55 - sum) & 0xFF);
    }

    public static byte[] PowerRequest()
    {
        var f = new byte[FrameLength];
        f[0] = Header;
        f[1] = CmdPower;
        f[16] = Checksum(f.AsSpan(0, 16));
        return f;
    }

    /// <summary>電源の情報の返事を読む。違う返事なら null</summary>
    public static (int Level, bool Cable, int Millivolts)? ParsePower(ReadOnlySpan<byte> r)
    {
        if (r.Length < FrameLength) return null;
        if (r[0] != Header || r[1] != CmdPower) return null;
        if (r[16] != Checksum(r[..16])) return null;
        int level = r[6];
        if (level > 100) return null;
        return (level, r[7] != 0, (r[8] << 8) | r[9]);
    }

    static bool HasUsage(HidDevice d, uint usage)
    {
        try
        {
            return d.GetReportDescriptor().DeviceItems.Any(i => i.Usages.GetAllValues().Contains(usage));
        }
        catch
        {
            return false;
        }
    }

    static int OutputLength(HidDevice d)
    {
        try { return d.GetMaxOutputReportLength(); } catch { return 0; }
    }

    /// <summary>レシーバーに問い合わせる。値が変わったら true</summary>
    public bool Poll()
    {
        lock (_lock)
        {
            List<HidDevice> all;
            try
            {
                all = DeviceList.Local.GetHidDevices().ToList();
            }
            catch (Exception e)
            {
                Status = "USB 機器の一覧を取れませんでした：" + e.Message;
                return false;
            }

            var mine = all.Where(d => Known.ContainsKey((d.VendorID, d.ProductID))).ToList();
            if (mine.Count == 0)
            {
                bool remapper = all.Any(d => d.VendorID == 0xCAFE && d.ProductID == 0xBAF2);
                Status = remapper
                    ? "レシーバーが HID Remapper の先にあるため読めません（PC に直接挿すと読めます）"
                    : "対応しているマウスのレシーバーが見つかりません";
                return false;
            }

            // 0xFF02/0x0002 の窓口を優先し、17バイトを送れない窓口は飛ばす
            var candidates = mine
                .Where(d => OutputLength(d) >= FrameLength)
                .OrderByDescending(d => HasUsage(d, ControlUsage))
                .ToList();

            foreach (var d in candidates)
            {
                var result = Ask(d);
                if (result is not { } r) continue;
                var name = Known[(d.VendorID, d.ProductID)];
                var old = _config.Mouse;
                bool changed = old == null || old.Level != r.Level || old.Charging != r.Cable;
                _config.Mouse = new MouseRecord
                {
                    Vid = d.VendorID,
                    Pid = d.ProductID,
                    Name = name,
                    Level = r.Level,
                    Charging = r.Cable,
                    Millivolts = r.Millivolts,
                    At = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
                };
                Status = "読み取りました";
                return changed;
            }

            Status = "マウスが応答しません（止まっていると眠ります。少し動かすと読めます）";
            return false;
        }
    }

    static (int Level, bool Cable, int Millivolts)? Ask(HidDevice d)
    {
        try
        {
            using var stream = d.Open();
            stream.WriteTimeout = 500;
            stream.ReadTimeout = 250;
            stream.Write(PowerRequest());
            var buf = new byte[Math.Max(FrameLength, d.GetMaxInputReportLength())];
            // 同じ窓口にはほかの知らせ（コマンド 0x0a など）も来るので、何回か読む
            for (int i = 0; i < 6; i++)
            {
                int n;
                try
                {
                    n = stream.Read(buf, 0, buf.Length);
                }
                catch (TimeoutException)
                {
                    break;
                }
                var parsed = ParsePower(buf.AsSpan(0, n));
                if (parsed != null) return parsed;
            }
        }
        catch
        {
            // 開けない・送れない窓口は飛ばす
        }
        return null;
    }
}

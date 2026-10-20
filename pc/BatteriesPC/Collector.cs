using System.Text;
using HidSharp;

namespace BatteriesPC;

/// <summary>PC 本体の電池</summary>
public static class PcBattery
{
    public sealed record Reading(int Level, bool Charging, bool PluggedIn);

    /// <summary>電池のない PC（デスクトップ）なら null</summary>
    public static Reading? Read()
    {
        var s = SystemInformation.PowerStatus;
        if (s.BatteryChargeStatus.HasFlag(BatteryChargeStatus.NoSystemBattery)) return null;
        if (s.BatteryChargeStatus == BatteryChargeStatus.Unknown && s.BatteryLifePercent > 1f) return null;
        if (s.BatteryLifePercent is < 0f or > 1f) return null;
        int level = (int)Math.Round(s.BatteryLifePercent * 100);
        bool plugged = s.PowerLineStatus == PowerLineStatus.Online;
        bool charging = s.BatteryChargeStatus.HasFlag(BatteryChargeStatus.Charging) || (plugged && level < 100);
        return new Reading(level, charging, plugged);
    }
}

/// <summary>送る中身を組み立てる</summary>
public static class Collector
{
    public static string Slug(string name)
    {
        var sb = new StringBuilder();
        foreach (var c in name.ToLowerInvariant())
            sb.Append(char.IsLetterOrDigit(c) ? c : '-');
        var s = sb.ToString().Trim('-');
        return s.Length == 0 ? "pc" : s;
    }

    public static RelayMessage Build(Config config, IEnumerable<AirPodsRecord> airPods)
    {
        long now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var devices = new List<RelayDevice>();

        if (PcBattery.Read() is { } pc)
        {
            devices.Add(new RelayDevice(
                config.DeviceId, config.PcName, "computer", "laptopcomputer", null,
                [new RelayPart("main", "本体", pc.Level, pc.Charging, now)]));
        }

        // 1週間以内に読み取った AirPods だけ送る（電池ごとに読み取った時刻をつけるので、古い値は iPhone 側で無視される）
        long weekAgo = now - 7 * 24 * 3600;
        foreach (var a in airPods)
        {
            if (!ProximityPairing.IsKnownModel(a.Model)) continue;
            var parts = a.Parts
                .Where(p => p.Value.At >= weekAgo)
                .Select(p => new RelayPart(p.Key, null, p.Value.Level, p.Value.Charging, p.Value.At))
                .OrderBy(p => p.Id switch { "left" => 0, "right" => 1, "case" => 2, _ => 3 })
                .ToList();
            if (parts.Count == 0) continue;
            devices.Add(new RelayDevice($"airpods-{a.Model:X4}", null, "airpods", null, a.Model, parts));
        }

        return new RelayMessage(1, config.PcName, now, devices)
        {
            PcId = config.PcId,
            FormerIds = config.FormerIds.Count > 0 ? config.FormerIds.ToList() : null,
            FormerNames = config.FormerNames.Count > 0 ? config.FormerNames.ToList() : null,
        };
    }

    /// <summary>送るかどうかの判断に使う「中身の要約」（時刻を除いた値）</summary>
    public static string Signature(RelayMessage m) =>
        string.Join("|", m.Devices.Select(d => d.Id + ":" + string.Join(",", d.Parts.Select(p => $"{p.Id}={p.Level}{(p.Charging ? "+" : "")}"))));
}

/// <summary>マウスの電池の読み方を調べるため、つながっている HID 機器の一覧を書き出す</summary>
public static class HidDump
{
    public static string Write()
    {
        var sb = new StringBuilder();
        sb.AppendLine("バッテリー送信：HID 機器の一覧");
        sb.AppendLine($"作成：{DateTime.Now:yyyy-MM-dd HH:mm:ss}  PC：{Environment.MachineName}");
        sb.AppendLine("（VXE マウスのレシーバーを挿した状態で作ってください。このファイルをそのまま送ってもらえれば、電池の読み方を調べます）");
        sb.AppendLine();
        try
        {
            var devices = DeviceList.Local.GetHidDevices()
                .OrderBy(d => d.VendorID).ThenBy(d => d.ProductID).ToList();
            foreach (var d in devices)
            {
                string Safe(Func<string> f) { try { return f(); } catch { return "?"; } }
                sb.AppendLine($"VID {d.VendorID:X4}  PID {d.ProductID:X4}  {Safe(d.GetManufacturer)} / {Safe(d.GetProductName)}");
                sb.AppendLine($"  入力 {Safe(() => d.GetMaxInputReportLength().ToString())}  出力 {Safe(() => d.GetMaxOutputReportLength().ToString())}  機能 {Safe(() => d.GetMaxFeatureReportLength().ToString())} バイト");
                sb.AppendLine($"  {d.DevicePath}");
                try
                {
                    var desc = d.GetReportDescriptor();
                    foreach (var item in desc.DeviceItems)
                    {
                        var usages = string.Join(", ", item.Usages.GetAllValues().Take(6).Select(u => $"0x{u:X8}"));
                        sb.AppendLine($"  使い方：{usages}");
                    }
                }
                catch
                {
                    // 読めない機器もある
                }
                sb.AppendLine();
            }
        }
        catch (Exception e)
        {
            sb.AppendLine("一覧を作れませんでした：" + e.Message);
        }

        var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "batteries-hid.txt");
        File.WriteAllText(path, sb.ToString(), Encoding.UTF8);
        return path;
    }
}

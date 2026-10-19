using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace BatteriesPC;

/// <summary>AirPods の1つの電池の最後の値</summary>
public sealed class PartRecord
{
    public int Level { get; set; }
    public bool Charging { get; set; }
    /// <summary>実際に読み取った時刻（Unix 秒）</summary>
    public long At { get; set; }
}

/// <summary>AirPods 1台分の最後の値（左・右・ケース）</summary>
public sealed class AirPodsRecord
{
    public int Model { get; set; }
    public Dictionary<string, PartRecord> Parts { get; set; } = new();
}

/// <summary>設定（%AppData%\BatteriesPC\config.json）</summary>
public sealed class Config
{
    /// <summary>iPhone と共有する合言葉（ntfy.sh のトピック名）</summary>
    public string Topic { get; set; } = "";
    /// <summary>iPhone に表示する PC の名前</summary>
    public string PcName { get; set; } = Environment.MachineName;
    /// <summary>この強さ（dBm）より弱い AirPods の電波は他人のものとして無視する</summary>
    public int RssiThreshold { get; set; } = -70;
    /// <summary>左右が逆に表示されるときの切り替え</summary>
    public bool SwapSides { get; set; }
    /// <summary>AirPods を読み取るか</summary>
    public bool ReadAirPods { get; set; } = true;
    /// <summary>最後に読み取った AirPods の値（再起動しても送れるように残す）</summary>
    public Dictionary<string, AirPodsRecord> AirPods { get; set; } = new();

    [JsonIgnore] public bool IsNew { get; private set; }

    public static string Folder =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "BatteriesPC");

    static string FilePath => Path.Combine(Folder, "config.json");

    static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public static Config Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                var c = JsonSerializer.Deserialize<Config>(File.ReadAllText(FilePath), Options);
                if (c != null)
                {
                    if (!IsValidTopic(c.Topic)) c.Topic = NewTopic();
                    if (string.IsNullOrWhiteSpace(c.PcName)) c.PcName = Environment.MachineName;
                    return c;
                }
            }
        }
        catch
        {
            // 壊れていたら作り直す
        }
        var fresh = new Config { Topic = NewTopic(), IsNew = true };
        fresh.Save();
        return fresh;
    }

    readonly object _saveLock = new();

    public void Save()
    {
        lock (_saveLock)
        {
            try
            {
                Directory.CreateDirectory(Folder);
                var tmp = FilePath + ".tmp";
                File.WriteAllText(tmp, JsonSerializer.Serialize(this, Options));
                File.Move(tmp, FilePath, overwrite: true);
            }
            catch
            {
                // 保存できなくても動き続ける
            }
        }
    }

    const string Alphabet = "abcdefghijkmnpqrstuvwxyz23456789"; // 見間違えやすい l・o・0・1 を除く

    public static string NewTopic()
    {
        Span<byte> bytes = stackalloc byte[16];
        RandomNumberGenerator.Fill(bytes);
        var chars = new char[16];
        for (int i = 0; i < 16; i++) chars[i] = Alphabet[bytes[i] % Alphabet.Length];
        return "bat-" + new string(chars);
    }

    public static bool IsValidTopic(string? topic)
    {
        if (string.IsNullOrEmpty(topic) || topic.Length < 8 || topic.Length > 64) return false;
        return topic.All(c => c is >= 'a' and <= 'z' or >= '0' and <= '9' or '-' or '_');
    }

    /// <summary>入力された合言葉や iPhone 用の URL から合言葉を取り出す</summary>
    public static string? NormalizeTopic(string input)
    {
        var text = input.Trim();
        var idx = text.IndexOf("code=", StringComparison.OrdinalIgnoreCase);
        if (idx >= 0) text = text[(idx + 5)..];
        text = text.Replace(" ", "").Replace("　", "").ToLowerInvariant();
        return IsValidTopic(text) ? text : null;
    }

    /// <summary>読みやすいように4文字ずつ区切る</summary>
    public static string Grouped(string topic)
    {
        if (!topic.StartsWith("bat-")) return topic;
        var body = topic[4..];
        var chunks = Enumerable.Range(0, (body.Length + 3) / 4)
            .Select(i => body.Substring(i * 4, Math.Min(4, body.Length - i * 4)));
        return "bat-" + string.Join(" ", chunks);
    }
}

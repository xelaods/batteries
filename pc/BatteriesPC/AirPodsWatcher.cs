using Windows.Devices.Bluetooth.Advertisement;
using Windows.Storage.Streams;

namespace BatteriesPC;

/// <summary>
/// AirPods・Beats が周りに発信している「近接ペアリング」信号（Apple の製造者データ、種類 0x07）から電池を読む。
/// iPhone アプリの ProximityPairing.swift と同じ読み方。
///
/// 種類 0x07 の中身：
///   [0] 前置き  [1-2] 機種  [3] 状態（0x20 で左右の向き）
///   [4] 電池（上位4bit・下位4bit が左右。0〜10 が 0〜100%、15 は不明）
///   [5] 上位4bit が充電中（bit0/1 が左右、bit2 がケース）、下位4bit がケースの電池
/// </summary>
public static class ProximityPairing
{
    public sealed record Reading(int Model, int? Left, int? Right, int? Case,
                                 bool LeftCharging, bool RightCharging, bool CaseCharging)
    {
        public bool HasAnyLevel => Left != null || Right != null || Case != null;
    }

    /// <summary>Apple の製造者データ（会社番号を除いた中身）から、種類と中身の組を取り出す</summary>
    public static IEnumerable<(byte Type, byte[] Payload)> Messages(byte[] data)
    {
        int i = 0;
        while (i + 1 < data.Length)
        {
            byte type = data[i];
            int length = data[i + 1];
            int start = i + 2;
            int end = Math.Min(start + length, data.Length);
            yield return (type, data[start..end]);
            if (start + length > data.Length) yield break;
            i = start + length;
        }
    }

    public static Reading? Parse(byte[] appleData, bool swapSides)
    {
        foreach (var (type, payload) in Messages(appleData))
        {
            if (type != 0x07) continue;
            var r = ParsePayload(payload, swapSides);
            if (r != null) return r;
        }
        return null;
    }

    public static Reading? ParsePayload(byte[] p, bool swapSides)
    {
        if (p.Length < 6) return null;
        int model = (p[1] << 8) | p[2];
        // 種類 0x07 は AirPods 以外の Apple 製品も使う。実在する機種番号のものだけ読む
        if (!IsKnownModel(model)) return null;
        byte status = p[3];
        bool flipped = (status & 0x20) == 0;
        if (swapSides) flipped = !flipped;

        int high = p[4] >> 4, low = p[4] & 0x0F;
        int leftRaw = flipped ? high : low;
        int rightRaw = flipped ? low : high;
        int charge = p[5] >> 4;
        int caseRaw = p[5] & 0x0F;

        bool leftCharging = (charge & (flipped ? 0b010 : 0b001)) != 0;
        bool rightCharging = (charge & (flipped ? 0b001 : 0b010)) != 0;
        bool caseCharging = (charge & 0b100) != 0;

        return new Reading(model, Percent(leftRaw), Percent(rightRaw), Percent(caseRaw),
                           leftCharging, rightCharging, caseCharging);
    }

    static int? Percent(int raw) => raw is >= 0 and <= 10 ? raw * 10 : null;

    /// <summary>実在する AirPods・Beats の機種番号。これ以外は別の Apple 製品の電波なので無視する</summary>
    static readonly Dictionary<int, string> Models = new()
    {
        [0x0220] = "AirPods",
        [0x0F20] = "AirPods（第2世代）",
        [0x1320] = "AirPods（第3世代）",
        [0x1920] = "AirPods 4",
        [0x1B20] = "AirPods 4（ANC）",
        [0x0E20] = "AirPods Pro",
        [0x1420] = "AirPods Pro（第2世代）",
        [0x2420] = "AirPods Pro（第2世代・USB-C）",
        [0x2720] = "AirPods Pro 3",
        [0x0A20] = "AirPods Max",
        [0x1F20] = "AirPods Max（USB-C）",
        [0x0320] = "Powerbeats3",
        [0x0B20] = "Powerbeats Pro",
        [0x0C20] = "Beats Solo Pro",
        [0x1120] = "Beats Studio Buds",
        [0x1020] = "Beats Flex",
        [0x0520] = "BeatsX",
        [0x0620] = "Beats Solo3",
        [0x0920] = "Beats Studio3",
        [0x1720] = "Beats Studio Buds +",
        [0x1220] = "Beats Fit Pro",
        [0x1620] = "Beats Studio Pro",
    };

    public static bool IsKnownModel(int model) => Models.ContainsKey(model);

    public static string ModelName(int model) =>
        Models.TryGetValue(model, out var name) ? name : $"不明な機種（{model:X4}）";
}

/// <summary>Bluetooth の電波を受け取り続け、AirPods の電池を Config.AirPods に記録する</summary>
public sealed class AirPodsWatcher : IDisposable
{
    readonly Config _config;
    readonly object _lock = new();
    BluetoothLEAdvertisementWatcher? _watcher;
    /// <summary>機種ごとに、最近いちばん強かった電波（他人の AirPods を混ぜないため）</summary>
    readonly Dictionary<int, (ulong Address, short Rssi, DateTime At)> _strongest = new();
    bool _running;

    public event Action? Changed;
    public string Status { get; private set; } = "停止中";
    public int SignalsSeen { get; private set; }
    public DateTime? LastSignalAt { get; private set; }
    public short? LastRssi { get; private set; }

    public AirPodsWatcher(Config config) => _config = config;

    public void Start()
    {
        _running = true;
        try
        {
            _watcher = new BluetoothLEAdvertisementWatcher { ScanningMode = BluetoothLEScanningMode.Passive };
            _watcher.Received += OnReceived;
            _watcher.Stopped += OnStopped;
            _watcher.Start();
            Status = "AirPods を探しています";
        }
        catch (Exception e)
        {
            Status = "Bluetooth を使えません：" + e.Message;
        }
    }

    void OnStopped(BluetoothLEAdvertisementWatcher sender, BluetoothLEAdvertisementWatcherStoppedEventArgs args)
    {
        if (!_running) return;
        Status = args.Error switch
        {
            Windows.Devices.Bluetooth.BluetoothError.RadioNotAvailable => "Bluetooth がオフです",
            Windows.Devices.Bluetooth.BluetoothError.DisabledByUser => "Bluetooth が使えない設定です",
            _ => "Bluetooth の読み取りが止まりました（再開します）",
        };
        Changed?.Invoke();
        // Bluetooth をオンにし直したときなどに、少し待ってから再開する
        Task.Delay(TimeSpan.FromSeconds(30)).ContinueWith(_ =>
        {
            if (!_running) return;
            try
            {
                sender.Start();
                Status = "AirPods を探しています";
                Changed?.Invoke();
            }
            catch
            {
                // 次の Stopped でまた試す
            }
        });
    }

    void OnReceived(BluetoothLEAdvertisementWatcher sender, BluetoothLEAdvertisementReceivedEventArgs args)
    {
        if (!_config.ReadAirPods) return;
        foreach (var md in args.Advertisement.ManufacturerData)
        {
            if (md.CompanyId != 0x004C) continue;
            var data = new byte[md.Data.Length];
            using (var reader = DataReader.FromBuffer(md.Data)) reader.ReadBytes(data);
            var reading = ProximityPairing.Parse(data, _config.SwapSides);
            if (reading == null) continue;
            Handle(reading, args.BluetoothAddress, args.RawSignalStrengthInDBm);
        }
    }

    void Handle(ProximityPairing.Reading r, ulong address, short rssi)
    {
        SignalsSeen++;
        LastSignalAt = DateTime.Now;
        LastRssi = rssi;
        if (rssi < _config.RssiThreshold || !r.HasAnyLevel) return;

        var now = DateTime.UtcNow;
        lock (_lock)
        {
            // 同じ機種で、ここ15秒により強い電波を出している別の機器があれば、そちらを自分のものとみなす
            if (_strongest.TryGetValue(r.Model, out var best) && best.Address != address
                && best.Rssi > rssi + 3 && now - best.At < TimeSpan.FromSeconds(15))
            {
                return;
            }
            _strongest[r.Model] = (address, rssi, now);

            var key = r.Model.ToString("X4");
            if (!_config.AirPods.TryGetValue(key, out var rec))
            {
                rec = new AirPodsRecord { Model = r.Model };
                _config.AirPods[key] = rec;
            }
            long at = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            bool changed = false;
            changed |= Set(rec, "left", r.Left, r.LeftCharging, at);
            changed |= Set(rec, "right", r.Right, r.RightCharging, at);
            changed |= Set(rec, "case", r.Case, r.CaseCharging, at);
            Status = "AirPods を受信中";
            if (changed) Changed?.Invoke();
        }
    }

    static bool Set(AirPodsRecord rec, string part, int? level, bool charging, long at)
    {
        if (level == null) return false;
        if (rec.Parts.TryGetValue(part, out var old))
        {
            bool changed = old.Level != level || old.Charging != charging;
            old.Level = level.Value;
            old.Charging = charging;
            old.At = at;
            return changed;
        }
        rec.Parts[part] = new PartRecord { Level = level.Value, Charging = charging, At = at };
        return true;
    }

    /// <summary>今の AirPods の記録の写し（送信用）</summary>
    public List<AirPodsRecord> Snapshot()
    {
        lock (_lock)
        {
            return _config.AirPods.Values.Select(a => new AirPodsRecord
            {
                Model = a.Model,
                Parts = a.Parts.ToDictionary(p => p.Key, p => new PartRecord { Level = p.Value.Level, Charging = p.Value.Charging, At = p.Value.At }),
            }).ToList();
        }
    }

    public void Dispose()
    {
        _running = false;
        try { _watcher?.Stop(); } catch { }
    }
}

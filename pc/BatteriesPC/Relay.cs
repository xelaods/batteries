using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace BatteriesPC;

// iPhone アプリの RelayMessage（Shared/Relay.swift）と同じ形。時刻は Unix 秒。
public sealed record RelayPart(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("label")] string? Label,
    [property: JsonPropertyName("level")] int Level,
    [property: JsonPropertyName("charging")] bool Charging,
    [property: JsonPropertyName("at")] long At);

public sealed record RelayDevice(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("name")] string? Name,
    [property: JsonPropertyName("kind")] string Kind,
    [property: JsonPropertyName("symbol")] string? Symbol,
    [property: JsonPropertyName("model")] int? Model,
    [property: JsonPropertyName("parts")] List<RelayPart> Parts);

public sealed record RelayMessage(
    [property: JsonPropertyName("v")] int V,
    [property: JsonPropertyName("pc")] string Pc,
    [property: JsonPropertyName("at")] long At,
    [property: JsonPropertyName("devices")] List<RelayDevice> Devices);

/// <summary>ntfy.sh に送る</summary>
public sealed class Relay
{
    public const string Server = "https://ntfy.sh";

    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(20) };
    static readonly JsonSerializerOptions Options = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    static Relay()
    {
        Http.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("BatteriesPC", "1.0"));
    }

    public static string Serialize(RelayMessage message) => JsonSerializer.Serialize(message, Options);

    public static async Task<(bool Ok, string Detail)> SendAsync(string topic, RelayMessage message)
    {
        try
        {
            var json = Serialize(message);
            using var request = new HttpRequestMessage(HttpMethod.Post, $"{Server}/{topic}")
            {
                Content = new StringContent(json, Encoding.UTF8, "text/plain"),
            };
            // ntfy のアプリで同じトピックを購読していても鳴らないように、いちばん低い優先度にする
            request.Headers.Add("X-Priority", "1");
            request.Headers.Add("X-Title", "batteries");
            using var response = await Http.SendAsync(request);
            if (response.IsSuccessStatusCode) return (true, "送信しました");
            if ((int)response.StatusCode == 429) return (false, "送りすぎで一時的に止められています（しばらく待ちます）");
            return (false, $"中継サーバーのエラー（{(int)response.StatusCode}）");
        }
        catch (TaskCanceledException)
        {
            return (false, "時間内に送れませんでした");
        }
        catch (HttpRequestException e)
        {
            return (false, "ネットにつながっていません：" + e.Message);
        }
    }
}

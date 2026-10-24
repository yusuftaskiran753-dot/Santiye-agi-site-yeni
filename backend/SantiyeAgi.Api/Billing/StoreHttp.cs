using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.Billing;

public static class StoreHttp
{
    public static string Base64Url(byte[] value) => Convert.ToBase64String(value).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    public static byte[] Decode(string value) => Convert.FromBase64String(value.Replace('-', '+').Replace('_', '/') + new string('=', (4 - value.Length % 4) % 4));
    public static string Jwt(object header, object payload, Func<byte[], byte[]> sign)
    {
        var unsigned = Base64Url(JsonSerializer.SerializeToUtf8Bytes(header)) + "." + Base64Url(JsonSerializer.SerializeToUtf8Bytes(payload));
        return unsigned + "." + Base64Url(sign(Encoding.ASCII.GetBytes(unsigned)));
    }
    public static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
    public static async Task<JsonObject> Send(HttpClient http, HttpRequestMessage request, CancellationToken ct, bool receipt = true)
    {
        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
        if (!response.IsSuccessStatusCode)
        {
            if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
                throw new ApiError("CONFIG", 503, "Mağaza servis hesabı veya erişim izinleri eksik.");
            if (receipt && response.StatusCode is HttpStatusCode.BadRequest or HttpStatusCode.NotFound or HttpStatusCode.Gone)
                throw new ApiError("INVALID", 422, "Mağaza işlemi doğrulayamadı.");
            throw new ApiError("SERVER", 503, "Mağaza servisine geçici olarak ulaşılamıyor.");
        }
        if (response.StatusCode == HttpStatusCode.NoContent || response.Content.Headers.ContentLength == 0) return new();
        // Never include store bodies, tokens, or account credentials in error logs.
        await using var stream = await response.Content.ReadAsStreamAsync(ct);
        using var buffer = new MemoryStream();
        var bytes = new byte[8192]; int count;
        while ((count = await stream.ReadAsync(bytes, ct)) > 0)
        {
            if (buffer.Length + count > 1024 * 1024) throw new ApiError("SERVER", 503);
            buffer.Write(bytes, 0, count);
        }
        if (buffer.Length == 0) return new();
        try { return JsonNode.Parse(buffer.ToArray())?.AsObject() ?? throw new ApiError("SERVER", 503); }
        catch (JsonException) { throw new ApiError("SERVER", 503); }
    }
    public static HttpRequestMessage Request(HttpMethod method, string url, string token, HttpContent? body = null)
    {
        var request = new HttpRequestMessage(method, url) { Content = body };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return request;
    }
    public static long Long(JsonNode? n, long fallback = 0) => long.TryParse(n?.ToString(), out var x) ? x : fallback;
    public static DateTimeOffset? Millis(JsonNode? n) => Long(n) is > 0 and var value ? DateTimeOffset.FromUnixTimeMilliseconds(value) : null;
    public static DateTimeOffset? Date(JsonNode? n) => DateTimeOffset.TryParse(n?.ToString(), System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out var date) ? date : null;
}

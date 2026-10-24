using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

using var handler = new HttpClientHandler { AllowAutoRedirect = false };
using var http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(30), MaxResponseContentBufferSize = 65536 };
if (args.Contains("--audit"))
{
    var audit = await AppleAuthAudit.Run(args.FirstOrDefault(x => !x.StartsWith("--", StringComparison.Ordinal)) ?? @"C:\ProgramData\santiye\keys\AuthKey_CY8L78UR5Q.p8", http,
        sandboxHistory: args.Contains("--sandbox-history"));
    Console.WriteLine(JsonSerializer.Serialize(audit));
    return audit.ApiAccessVerified ? 0 : 1;
}
var result = await AppleAccessProbe.Check(args.FirstOrDefault() ?? @"C:\ProgramData\santiye\keys\AuthKey_CY8L78UR5Q.p8", http);
Console.WriteLine(JsonSerializer.Serialize(result));
return result.ApiAccessVerified ? 0 : 1;

public sealed record AppleProbeResult(string Stage, string Code, int? AppleHttpStatus = null, bool ApiAccessVerified = false);

public static class AppleAccessProbe
{
    public static async Task<AppleProbeResult> Check(string keyFile, HttpClient http)
    {
        using var key = ECDsa.Create();
        string pem;
        try
        {
            var file = new FileInfo(keyFile);
            if (!file.Exists) return new("READ_KEY", "KEY_FILE_MISSING");
            if (file.Length > 16384) return new("READ_KEY", "KEY_FILE_TOO_LARGE");
            pem = await File.ReadAllTextAsync(keyFile);
        }
        catch (UnauthorizedAccessException) { return new("READ_KEY", "KEY_FILE_ACCESS_DENIED"); }
        catch (Exception e) when (e is IOException or ArgumentException or NotSupportedException) { return new("READ_KEY", "KEY_FILE_READ_FAILED"); }
        try
        {
            key.ImportFromPem(pem);
            if (key.KeySize != 256 || key.ExportParameters(false).Curve.Oid.Value != "1.2.840.10045.3.1.7")
                return new("SIGN_TOKEN", "KEY_MUST_BE_P256");
        }
        catch (Exception e) when (e is ArgumentException or CryptographicException) { return new("SIGN_TOKEN", "KEY_FORMAT_OR_PRIVATE_KEY_INVALID"); }
        finally { pem = ""; }
        string token;
        try
        {
            var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            static string Encode(byte[] bytes) => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
            var data = Encode(JsonSerializer.SerializeToUtf8Bytes(new { alg = "ES256", kid = "CY8L78UR5Q", typ = "JWT" })) + "." +
                Encode(JsonSerializer.SerializeToUtf8Bytes(new { iss = "e0061e2a-caf2-40d0-81f4-21d2ead8c973", iat = now, exp = now + 300,
                    aud = "appstoreconnect-v1", bid = "com.yusuftaskiran.santiyeagi.pro" }));
            token = data + "." + Encode(key.SignData(Encoding.ASCII.GetBytes(data), HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation));
        }
        catch (CryptographicException) { return new("SIGN_TOKEN", "PRIVATE_KEY_CANNOT_SIGN"); }
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.storekit.apple.com/inApps/v1/notifications/test");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            using var response = await http.SendAsync(request);
            var status = (int)response.StatusCode;
            if (!response.IsSuccessStatusCode) return new("APPLE_HTTP", status switch {
                401 => "APPLE_AUTH_REJECTED", 403 => "APPLE_ACCESS_FORBIDDEN", 404 => "APPLE_APP_OR_ENDPOINT_NOT_FOUND",
                429 => "APPLE_RATE_LIMITED", _ => "APPLE_REQUEST_REJECTED" }, status);
            try
            {
                using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
                if (!body.RootElement.TryGetProperty("testNotificationToken", out var nonce) || nonce.ValueKind != JsonValueKind.String ||
                    !System.Text.RegularExpressions.Regex.IsMatch(nonce.GetString() ?? "", @"\A[A-Za-z0-9_-]{1,256}\z"))
                    return new("APPLE_HTTP", "APPLE_RESPONSE_UNEXPECTED", status);
            }
            catch (JsonException) { return new("APPLE_HTTP", "APPLE_RESPONSE_UNEXPECTED", status); }
            return new("APPLE_HTTP", "APPLE_API_ACCESS_CONFIRMED", status, true);
        }
        catch (HttpRequestException e) { return new("APPLE_HTTP", e.HttpRequestError switch {
            HttpRequestError.NameResolutionError => "DNS_FAILED", HttpRequestError.SecureConnectionError => "TLS_FAILED", _ => "NETWORK_FAILED" }); }
        catch (OperationCanceledException) { return new("APPLE_HTTP", "NETWORK_TIMEOUT"); }
        finally { token = ""; }
    }
}

using System.Diagnostics;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

public sealed record AppleAuthAuditResult
{
    public int AuditVersion { get; init; } = 1;
    public string? KeySha256 { get; set; }
    public bool KeyHashMatches { get; set; }
    public DateTimeOffset ServerUtc { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? AppleDateUtc { get; set; }
    public double? ServerMinusAppleSeconds { get; set; }
    public double? TimeMeasurementRttMs { get; set; }
    public bool JwtHeaderMatches { get; set; }
    public bool JwtPayloadMatches { get; set; }
    public bool JwtSignatureValid { get; set; }
    public int JwtSignatureBytes { get; set; }
    public int JwtLifetimeSeconds { get; set; }
    public string Endpoint { get; init; } = "https://api.storekit.apple.com/inApps/v1/notifications/test";
    public int? AppleHttpStatus { get; set; }
    public string Code { get; set; } = "NOT_CHECKED";
    public bool ApiAccessVerified { get; set; }
}

public static class AppleAuthAudit
{
    public const string ExpectedHash = "0a969ec424de180b72a7dcbf7e7b3f39ff954d47397cbb382a4c0b560820f9c2";
    public static async Task<AppleAuthAuditResult> Run(string path, HttpClient http, string expectedHash = ExpectedHash, bool sandboxHistory = false)
    {
        var result = sandboxHistory ? new AppleAuthAuditResult { Endpoint = "https://api.storekit-sandbox.apple.com/inApps/v1/notifications/history" } : new AppleAuthAuditResult();
        using var key = ECDsa.Create();
        byte[]? bytes = null;
        try
        {
            var file = new FileInfo(path);
            if (!file.Exists) { result.Code = "KEY_FILE_MISSING"; return result; }
            if (file.Length > 16384) { result.Code = "KEY_FILE_TOO_LARGE"; return result; }
            bytes = await File.ReadAllBytesAsync(path);
            result.KeySha256 = Convert.ToHexStringLower(SHA256.HashData(bytes));
            result.KeyHashMatches = string.Equals(result.KeySha256, expectedHash, StringComparison.OrdinalIgnoreCase);
            // Hash comparison reports transport equality only; it doesn't prove Apple's authorization.
            key.ImportFromPem(Encoding.UTF8.GetString(bytes).AsSpan().TrimStart('\uFEFF'));
            if (key.KeySize != 256 || key.ExportParameters(false).Curve.Oid.Value != "1.2.840.10045.3.1.7")
            { result.Code = "KEY_MUST_BE_P256"; return result; }
        }
        catch (UnauthorizedAccessException) { result.Code = "KEY_FILE_ACCESS_DENIED"; return result; }
        catch (Exception e) when (e is IOException or ArgumentException or CryptographicException or NotSupportedException)
        { result.Code = "KEY_READ_OR_FORMAT_FAILED"; return result; }
        finally { if (bytes is not null) CryptographicOperations.ZeroMemory(bytes); }

        string? token = null;
        try
        {
            var iat = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            var exp = iat + 300;
            static string Encode(byte[] value) => Convert.ToBase64String(value).TrimEnd('=').Replace('+', '-').Replace('/', '_');
            static byte[] Decode(string value) => Convert.FromBase64String(value.Replace('-', '+').Replace('_', '/') + new string('=', (4-value.Length%4)%4));
            var unsigned = Encode(JsonSerializer.SerializeToUtf8Bytes(new { alg = "ES256", kid = "CY8L78UR5Q", typ = "JWT" })) + "." +
                Encode(JsonSerializer.SerializeToUtf8Bytes(new { iss = "e0061e2a-caf2-40d0-81f4-21d2ead8c973", iat, exp,
                    aud = "appstoreconnect-v1", bid = "com.yusuftaskiran.santiyeagi.pro" }));
            var signature = key.SignData(Encoding.ASCII.GetBytes(unsigned), HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
            token = unsigned + "." + Encode(signature);
            var parts = token.Split('.');
            using var header = JsonDocument.Parse(Decode(parts[0]));
            using var payload = JsonDocument.Parse(Decode(parts[1]));
            result.JwtHeaderMatches = header.RootElement.GetProperty("alg").GetString() == "ES256" &&
                header.RootElement.GetProperty("kid").GetString() == "CY8L78UR5Q" && header.RootElement.GetProperty("typ").GetString() == "JWT";
            result.JwtPayloadMatches = payload.RootElement.GetProperty("iss").GetString() == "e0061e2a-caf2-40d0-81f4-21d2ead8c973" &&
                payload.RootElement.GetProperty("aud").GetString() == "appstoreconnect-v1" &&
                payload.RootElement.GetProperty("bid").GetString() == "com.yusuftaskiran.santiyeagi.pro" &&
                payload.RootElement.GetProperty("iat").GetInt64() == iat && payload.RootElement.GetProperty("exp").GetInt64() == exp;
            result.JwtLifetimeSeconds = checked((int)(exp - iat));
            result.JwtSignatureBytes = Decode(parts[2]).Length;
            using var publicKey = ECDsa.Create();
            publicKey.ImportSubjectPublicKeyInfo(key.ExportSubjectPublicKeyInfo(), out _);
            result.JwtSignatureValid = result.JwtSignatureBytes == 64 && publicKey.VerifyData(Encoding.ASCII.GetBytes(parts[0] + "." + parts[1]),
                Decode(parts[2]), HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
            if (!result.JwtHeaderMatches || !result.JwtPayloadMatches || !result.JwtSignatureValid)
            { result.Code = "LOCAL_JWT_CHECK_FAILED"; return result; }

            using var request = new HttpRequestMessage(HttpMethod.Post, result.Endpoint);
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            if (sandboxHistory)
            {
                // Read-only history query: no TEST callback, transaction or entitlement mutation.
                var end = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
                request.Content = new StringContent(JsonSerializer.Serialize(new { startDate = end - 60000, endDate = end }), Encoding.UTF8, "application/json");
            }
            var start = DateTimeOffset.UtcNow;
            var elapsed = Stopwatch.StartNew();
            using var response = await http.SendAsync(request);
            elapsed.Stop();
            result.ServerUtc = start;
            result.TimeMeasurementRttMs = Math.Round(elapsed.Elapsed.TotalMilliseconds, 1);
            result.AppleDateUtc = response.Headers.Date?.ToUniversalTime();
            if (result.AppleDateUtc is not null)
                result.ServerMinusAppleSeconds = Math.Round((start.AddTicks(elapsed.Elapsed.Ticks / 2) - result.AppleDateUtc.Value).TotalSeconds, 1);
            result.AppleHttpStatus = (int)response.StatusCode;
            if (!response.IsSuccessStatusCode)
            {
                result.Code = result.AppleHttpStatus switch { 401 => "APPLE_AUTH_REJECTED", 403 => "APPLE_ACCESS_FORBIDDEN",
                    >= 300 and < 400 => "UNEXPECTED_REDIRECT", 429 => "APPLE_RATE_LIMITED", _ => "APPLE_REQUEST_REJECTED" };
                return result;
            }
            using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            if (sandboxHistory)
            {
                // Discard all history/JWS content. HTTP 200 authenticates this app/key in Sandbox.
                result.ApiAccessVerified = body.RootElement.ValueKind == JsonValueKind.Object;
                result.Code = result.ApiAccessVerified ? "APPLE_API_ACCESS_CONFIRMED" : "APPLE_RESPONSE_UNEXPECTED";
                return result;
            }
            result.ApiAccessVerified = body.RootElement.TryGetProperty("testNotificationToken", out var nonce) && nonce.ValueKind == JsonValueKind.String &&
                System.Text.RegularExpressions.Regex.IsMatch(nonce.GetString() ?? "", @"\A[A-Za-z0-9_-]{1,256}\z");
            result.Code = result.ApiAccessVerified ? "APPLE_API_ACCESS_CONFIRMED" : "APPLE_RESPONSE_UNEXPECTED";
        }
        catch (HttpRequestException e) { result.Code = e.HttpRequestError switch {
            HttpRequestError.NameResolutionError => "DNS_FAILED", HttpRequestError.SecureConnectionError => "TLS_FAILED", _ => "NETWORK_FAILED" }; }
        catch (OperationCanceledException) { result.Code = "NETWORK_TIMEOUT"; }
        catch (CryptographicException) { result.Code = "PRIVATE_KEY_CANNOT_SIGN"; }
        catch (Exception e) when (e is JsonException or InvalidOperationException or FormatException) { result.Code = "APPLE_RESPONSE_UNEXPECTED"; }
        finally { token = null; }
        return result;
    }
}

using System.Net;
using System.Security.Cryptography;
using System.Text.Json;

public sealed class AppleAuthAuditTests
{
    [Theory]
    [InlineData(200, true)]
    [InlineData(401, false)]
    public async Task AuditChecksExactBytesClaimsSignatureEndpointAndClockWithoutOutputtingSecrets(int status, bool success)
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".p8");
        await File.WriteAllTextAsync(path, key.ExportPkcs8PrivateKeyPem());
        try
        {
            var hash = Convert.ToHexStringLower(SHA256.HashData(await File.ReadAllBytesAsync(path)));
            using var http = new HttpClient(new AuditHandler(request => {
                Assert.Equal(HttpMethod.Post, request.Method);
                Assert.Equal("https://api.storekit.apple.com/inApps/v1/notifications/test", request.RequestUri!.AbsoluteUri);
                Assert.Equal("Bearer", request.Headers.Authorization!.Scheme);
                var response = new HttpResponseMessage((HttpStatusCode)status) { Content = new StringContent("{\"testNotificationToken\":\"PRIVATE-NONCE\",\"other\":\"CANARY\"}") };
                response.Headers.Date = DateTimeOffset.UtcNow.AddSeconds(-900);
                return response;
            }));
            var result = await AppleAuthAudit.Run(path, http, hash);
            Assert.True(result.KeyHashMatches); Assert.Equal(hash, result.KeySha256);
            Assert.True(result.JwtSignatureValid); Assert.True(result.JwtHeaderMatches); Assert.True(result.JwtPayloadMatches);
            Assert.Equal(64, result.JwtSignatureBytes); Assert.Equal(300, result.JwtLifetimeSeconds);
            Assert.Equal(status, result.AppleHttpStatus); Assert.Equal(success, result.ApiAccessVerified);
            Assert.InRange(result.ServerMinusAppleSeconds!.Value, 899, 902);
            var output = JsonSerializer.Serialize(result);
            Assert.DoesNotContain("PRIVATE", output); Assert.DoesNotContain("CANARY", output); Assert.DoesNotContain("eyJ", output);
        }
        finally { File.Delete(path); }
    }
    [Fact]
    public async Task SandboxProbeOnlyReadsRecentHistoryAndNeverRequestsCallbackOrExposesJws()
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".p8");
        await File.WriteAllTextAsync(path, key.ExportPkcs8PrivateKeyPem());
        try
        {
            var count = 0;
            using var http = new HttpClient(new AuditHandler(request => {
                count++;
                Assert.Equal("https://api.storekit-sandbox.apple.com/inApps/v1/notifications/history", request.RequestUri!.AbsoluteUri);
                Assert.Equal(HttpMethod.Post, request.Method);
                using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
                var start = body.RootElement.GetProperty("startDate").GetInt64();
                var end = body.RootElement.GetProperty("endDate").GetInt64();
                Assert.Equal(60000, end - start);
                Assert.InRange(Math.Abs(DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() - end), 0, 5000);
                return new(HttpStatusCode.OK) { Content = new StringContent("{\"hasMore\":false,\"notificationHistory\":[{\"signedPayload\":\"CANARY-JWS\"}]}") };
            }));
            var result = await AppleAuthAudit.Run(path, http, sandboxHistory: true);
            Assert.Equal(1, count); Assert.True(result.ApiAccessVerified);
            Assert.DoesNotContain("CANARY", JsonSerializer.Serialize(result)); Assert.DoesNotContain("signedPayload", JsonSerializer.Serialize(result));
        }
        finally { File.Delete(path); }
    }
    [Fact]
    public async Task HashMismatchIsReportedIndependentlyOfApiRejection()
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".p8");
        await File.WriteAllTextAsync(path, key.ExportPkcs8PrivateKeyPem());
        try
        {
            using var http = new HttpClient(new AuditHandler(_ => new(HttpStatusCode.Unauthorized)));
            var result = await AppleAuthAudit.Run(path, http);
            Assert.False(result.KeyHashMatches); Assert.True(result.JwtSignatureValid);
            Assert.Null(result.AppleDateUtc); Assert.Null(result.ServerMinusAppleSeconds);
            Assert.Equal("APPLE_AUTH_REJECTED", result.Code);
        }
        finally { File.Delete(path); }
    }
    private sealed class AuditHandler(Func<HttpRequestMessage, HttpResponseMessage> response) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct) => Task.FromResult(response(request));
    }
}

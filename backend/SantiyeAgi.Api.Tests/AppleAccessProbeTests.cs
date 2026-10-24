using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

public sealed class AppleAccessProbeTests
{
    [Theory]
    [InlineData(200, "APPLE_API_ACCESS_CONFIRMED", true)]
    [InlineData(401, "APPLE_AUTH_REJECTED", false)]
    [InlineData(403, "APPLE_ACCESS_FORBIDDEN", false)]
    [InlineData(429, "APPLE_RATE_LIMITED", false)]
    [InlineData(500, "APPLE_REQUEST_REJECTED", false)]
    public async Task ProbeSignsCorrectAppAndOnlyReturnsSafeStatus(int status, string code, bool success)
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".p8");
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        await File.WriteAllTextAsync(path, key.ExportPkcs8PrivateKeyPem());
        try
        {
            var handler = new Handler(request => {
                Assert.Equal(HttpMethod.Post, request.Method);
                Assert.Equal("https://api.storekit.apple.com/inApps/v1/notifications/test", request.RequestUri!.AbsoluteUri);
                var jwt = request.Headers.Authorization!.Parameter!.Split('.');
                static byte[] Decode(string value) => Convert.FromBase64String(value.Replace('-', '+').Replace('_', '/') + new string('=', (4-value.Length%4)%4));
                using var header = JsonDocument.Parse(Decode(jwt[0]));
                using var payload = JsonDocument.Parse(Decode(jwt[1]));
                Assert.Equal("CY8L78UR5Q", header.RootElement.GetProperty("kid").GetString());
                Assert.Equal("e0061e2a-caf2-40d0-81f4-21d2ead8c973", payload.RootElement.GetProperty("iss").GetString());
                Assert.Equal("com.yusuftaskiran.santiyeagi.pro", payload.RootElement.GetProperty("bid").GetString());
                Assert.True(key.VerifyData(Encoding.ASCII.GetBytes(jwt[0]+"."+jwt[1]), Decode(jwt[2]), HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation));
                return new((HttpStatusCode)status) { Content = new StringContent("{\"testNotificationToken\":\"PRIVATE-TEST-TOKEN\",\"detail\":\"CANARY-PRIVATE\"}") };
            });
            using var http = new HttpClient(handler);
            var result = await AppleAccessProbe.Check(path, http);
            Assert.Equal(code, result.Code); Assert.Equal(status, result.AppleHttpStatus); Assert.Equal(success, result.ApiAccessVerified);
            var output = JsonSerializer.Serialize(result);
            Assert.DoesNotContain("PRIVATE", output); Assert.DoesNotContain("eyJ", output); Assert.Equal(1, handler.Calls);
        }
        finally { File.Delete(path); }
    }
    [Fact]
    public async Task InvalidPrivateKeyNeverCallsAppleOrLeaksInput()
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".p8");
        await File.WriteAllTextAsync(path, "CANARY-PRIVATE-INVALID-KEY");
        try
        {
            var handler = new Handler(_ => throw new Exception("Network forbidden"));
            using var http = new HttpClient(handler);
            var result = await AppleAccessProbe.Check(path, http);
            Assert.Equal("SIGN_TOKEN", result.Stage); Assert.False(result.ApiAccessVerified); Assert.Equal(0, handler.Calls);
            Assert.DoesNotContain("CANARY", JsonSerializer.Serialize(result));
        }
        finally { File.Delete(path); }
    }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> reply) : HttpMessageHandler
    {
        public int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        { Calls++; return Task.FromResult(reply(request)); }
    }
}

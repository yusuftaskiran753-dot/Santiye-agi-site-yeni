using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Options;
using SantiyeAgi.Api.Billing;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.Tests;

public class BillingStoreTests
{
    private const string Monthly = "santiye_premium_aylik";
    private const string Credits = "santiye_kredi_5";
    private static readonly Guid User = Guid.NewGuid();
    private static JsonObject Subscription(string state, int days) => new()
    {
        ["subscriptionState"] = state,
        ["externalAccountIdentifiers"] = new JsonObject { ["obfuscatedExternalAccountId"] = User.ToString() },
        ["lineItems"] = new JsonArray(new JsonObject { ["productId"] = Monthly, ["expiryTime"] = DateTimeOffset.UtcNow.AddDays(days).ToString("O") }),
        ["acknowledgementState"] = "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED"
    };
    [Theory]
    [InlineData("SUBSCRIPTION_STATE_ACTIVE", 5, true)]
    [InlineData("SUBSCRIPTION_STATE_CANCELED", 5, true)]
    [InlineData("SUBSCRIPTION_STATE_CANCELED", -1, false)]
    [InlineData("SUBSCRIPTION_STATE_IN_GRACE_PERIOD", 2, true)]
    [InlineData("SUBSCRIPTION_STATE_ON_HOLD", 5, false)]
    [InlineData("SUBSCRIPTION_STATE_PAUSED", 5, false)]
    [InlineData("SUBSCRIPTION_STATE_PENDING", 5, false)]
    [InlineData("SUBSCRIPTION_STATE_EXPIRED", -1, false)]
    public void GoogleSubscriptionUsesCurrentStoreState(string state, int days, bool entitled)
    {
        var parsed = GoogleStoreClient.Parse(Monthly, "token", Subscription(state, days), false);
        Assert.Equal(entitled, parsed.EntitledUntil is not null);
        Assert.Equal(User.ToString(), parsed.AccountId);
        Assert.Equal("token", parsed.PurchaseKey);
    }
    [Fact]
    public void GooglePendingUnknownProductAndWrongProductNeverGrant()
    {
        Assert.Equal("PENDING", Assert.Throws<ApiError>(() => GoogleStoreClient.Parse(Credits, "token", new() { ["purchaseState"] = 2 }, false)).Code);
        Assert.Throws<ApiError>(() => GoogleStoreClient.Parse("wrong", "token", new(), false));
        Assert.Throws<ApiError>(() => GoogleStoreClient.Parse(Credits, "token", new() { ["productId"] = "another", ["purchaseState"] = 0 }, false));
        Assert.Throws<ApiError>(() => GoogleStoreClient.Parse(Monthly, "token", new() { ["lineItems"] = new JsonArray() }, false));
    }
    [Fact]
    public void GoogleQuantityPartialRefundAndConsumedStateArePreserved()
    {
        var parsed = GoogleStoreClient.Parse(Credits, "token", new()
        {
            ["purchaseState"] = 0, ["quantity"] = 3, ["refundableQuantity"] = 2, ["consumptionState"] = 1,
            ["obfuscatedExternalAccountId"] = User.ToString()
        }, false);
        Assert.Equal(15, parsed.Credits); Assert.Equal(5, parsed.RefundedCredits); Assert.True(parsed.Acknowledged);
        var refunded = GoogleStoreClient.Parse(Credits, "token", new() { ["purchaseState"] = 1, ["quantity"] = 3 }, false);
        Assert.Equal(15, refunded.RefundedCredits);
    }
    [Theory]
    [InlineData(0)] [InlineData(-1)] [InlineData(10001)]
    public void GoogleRejectsInvalidQuantity(int amount) => Assert.Throws<ApiError>(() => GoogleStoreClient.Parse(Credits, "t", new() { ["purchaseState"] = 0, ["quantity"] = amount }, false));
    [Fact]
    public void SandboxMustBeExplicitlyEnabled()
    {
        var data = Subscription("SUBSCRIPTION_STATE_ACTIVE", 5); data["testPurchase"] = new JsonObject();
        Assert.Throws<ApiError>(() => GoogleStoreClient.Parse(Monthly, "token", data, false));
        Assert.Equal("Sandbox", GoogleStoreClient.Parse(Monthly, "token", data, true).Environment);
    }
    [Fact]
    public void AppleDoesNotAcceptUnsignedOrArbitraryCertificateData()
    {
        var verifier = new AppleSignedDataVerifier(Options.Create(new StoreBillingOptions()));
        var fake = StoreHttp.Base64Url(Encoding.UTF8.GetBytes("{\"alg\":\"none\"}")) + "." + StoreHttp.Base64Url(Encoding.UTF8.GetBytes("{\"environment\":\"Production\"}")) + ".";
        Assert.Throws<ApiError>(() => verifier.Verify(fake, "Production"));
        Assert.Throws<ApiError>(() => verifier.Verify("not-a-jws", "Production"));
    }
    [Theory]
    [InlineData(1, true)] [InlineData(4, true)] [InlineData(3, false)] [InlineData(5, false)] [InlineData(2, false)]
    public async Task AppleRestoredOriginalUsesLatestRenewalAndGracePeriod(long status, bool active)
    {
        var root = Path.Combine(Path.GetTempPath(), "santiye-billing-test-" + Guid.NewGuid().ToString("N") + ".p8");
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256); await File.WriteAllTextAsync(root, key.ExportPkcs8PrivateKeyPem());
        try
        {
            var original = AppleTransaction("1", -30); var current = AppleTransaction("2", status == 4 ? -1 : 10);
            var renewal = new JsonObject { ["environment"] = "Production", ["originalTransactionId"] = "1", ["gracePeriodExpiresDate"] = DateTimeOffset.UtcNow.AddDays(2).ToUnixTimeMilliseconds() };
            var handler = new StubHandler(request => request.RequestUri!.AbsolutePath.Contains("/subscriptions/")
                ? new JsonObject { ["bundleId"] = "test.bundle", ["environment"] = "Production", ["appAppleId"] = 123,
                    ["data"] = new JsonArray(new JsonObject { ["lastTransactions"] = new JsonArray(new JsonObject { ["status"] = status, ["signedTransactionInfo"] = "current", ["signedRenewalInfo"] = "renewal" }) }) }
                : new JsonObject { ["signedTransactionInfo"] = "original" });
            var signature = new StubSignature(new() { ["original"] = original, ["current"] = current, ["renewal"] = renewal });
            using var http = new HttpClient(handler);
            var client = new AppleStoreClient(http, Options.Create(new StoreBillingOptions
            {
                Enabled = true, AppleBundleId = "test.bundle", AppleAppId = 123, AppleIssuerId = "issuer", AppleKeyId = "key", ApplePrivateKeyFile = root,
                AppleRootCertificateFiles = ["not-used-by-mock"]
            }), signature);
            var result = await client.Verify(Monthly, "1", default);
            Assert.Equal(active, result.EntitledUntil is not null); Assert.Equal("1", result.PurchaseKey);
            Assert.Equal(2, handler.Requests.Count);
            Assert.All(handler.Requests, x => Assert.Equal("api.storekit.apple.com", x.Host));
        }
        finally { File.Delete(root); }
    }
    [Theory]
    [InlineData(false, "api.storekit.apple.com")]
    [InlineData(true, "api.storekit-sandbox.apple.com")]
    public async Task AppleTestNotificationUsesSelectedHostAndDoesNotExposePayload(bool sandbox, string host)
    {
        var path = Path.Combine(Path.GetTempPath(), "santiye-test-" + Guid.NewGuid().ToString("N") + ".p8");
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        await File.WriteAllTextAsync(path, key.ExportPkcs8PrivateKeyPem());
        try
        {
            var nonce = Guid.NewGuid().ToString();
            var handler = new StubHandler(request => request.Method == HttpMethod.Post
                ? new JsonObject { ["testNotificationToken"] = nonce }
                : new JsonObject { ["signedPayload"] = "PRIVATE-JWS-MUST-NOT-RETURN",
                    ["sendAttempts"] = new JsonArray(new JsonObject { ["sendAttemptResult"] = "SUCCESS" }) });
            using var http = new HttpClient(handler);
            var client = new AppleStoreClient(http, Options.Create(new StoreBillingOptions {
                Enabled = true, AllowSandbox = sandbox, AppleBundleId = "test.bundle", AppleIssuerId = "issuer", AppleKeyId = "key",
                ApplePrivateKeyFile = path, AppleRootCertificateFiles = ["mock-root"] }), new StubSignature(new()));
            var result = await client.CheckTestNotification(sandbox, default);
            Assert.True(result["delivered"]!.GetValue<bool>());
            Assert.DoesNotContain(nonce, result.ToJsonString());
            Assert.DoesNotContain("PRIVATE-JWS", result.ToJsonString());
            Assert.Equal(2, handler.Requests.Count);
            Assert.All(handler.Requests, x => Assert.Equal(host, x.Host));
            Assert.Equal("/inApps/v1/notifications/test", handler.Requests[0].AbsolutePath);
            Assert.EndsWith("/" + nonce, handler.Requests[1].AbsolutePath);
        }
        finally { File.Delete(path); }
    }
    [Fact]
    public async Task AppleAccessProbeRequiresSuccessfulServerApiResponseAndKeepsTokenPrivate()
    {
        var path = Path.Combine(Path.GetTempPath(), "santiye-test-" + Guid.NewGuid().ToString("N") + ".p8");
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        await File.WriteAllTextAsync(path, key.ExportPkcs8PrivateKeyPem());
        try
        {
            var options = Options.Create(new StoreBillingOptions { Enabled = true, AppleBundleId = "test.bundle",
                AppleIssuerId = "issuer", AppleKeyId = "key", ApplePrivateKeyFile = path, AppleRootCertificateFiles = ["mock-root"] });
            foreach (var status in new[] { HttpStatusCode.OK, HttpStatusCode.Unauthorized, HttpStatusCode.Forbidden })
            {
                var handler = new StubHandler(_ => new JsonObject { ["testNotificationToken"] = "PRIVATE-TOKEN" }, status);
                using var http = new HttpClient(handler);
                var client = new AppleStoreClient(http, options, new StubSignature(new()));
                if (status == HttpStatusCode.OK)
                {
                    var result = await client.CheckTestNotification(false, default, accessOnly: true);
                    Assert.True(result["api_access_verified"]!.GetValue<bool>());
                    Assert.DoesNotContain("PRIVATE-TOKEN", result.ToJsonString());
                    Assert.Null(result["delivered"]);
                }
                else await Assert.ThrowsAsync<ApiError>(() => client.CheckTestNotification(false, default, accessOnly: true));
                Assert.Single(handler.Requests);
                Assert.Equal("api.storekit.apple.com", handler.Requests[0].Host);
                Assert.Equal("/inApps/v1/notifications/test", handler.Requests[0].AbsolutePath);
            }
            var invalid = new StubHandler(_ => new JsonObject { ["testNotificationToken"] = "invalid/token" });
            using var invalidHttp = new HttpClient(invalid);
            var invalidClient = new AppleStoreClient(invalidHttp, options, new StubSignature(new()));
            await Assert.ThrowsAsync<ApiError>(() => invalidClient.CheckTestNotification(false, default, accessOnly: true));
        }
        finally { File.Delete(path); }
    }
    [Fact]
    public async Task ProductionAppleCheckCannotEnableSandboxOrCallNetwork()
    {
        var handler = new StubHandler(_ => throw new Exception("Must not call Apple"));
        using var http = new HttpClient(handler);
        var client = new AppleStoreClient(http, Options.Create(new StoreBillingOptions { Enabled = true, AllowSandbox = false }), new StubSignature(new()));
        Assert.Equal("CONFIG", (await Assert.ThrowsAsync<ApiError>(() => client.CheckTestNotification(true, default))).Code);
        Assert.Empty(handler.Requests);
    }

    private static JsonObject AppleTransaction(string id, int expiryDays) => new()
    {
        ["bundleId"] = "test.bundle", ["productId"] = Monthly, ["environment"] = "Production", ["transactionId"] = id,
        ["originalTransactionId"] = "1", ["type"] = "Auto-Renewable Subscription", ["appAccountToken"] = User.ToString(),
        ["expiresDate"] = DateTimeOffset.UtcNow.AddDays(expiryDays).ToUnixTimeMilliseconds(),
        ["purchaseDate"] = DateTimeOffset.UtcNow.AddDays(id == "1" ? -60 : -2).ToUnixTimeMilliseconds()
    };
    private sealed class StubSignature(Dictionary<string, JsonObject> values) : IAppleSignedDataVerifier
    {
        public JsonObject Verify(string signed, string? environment) => values[signed];
    }
    private sealed class StubHandler(Func<HttpRequestMessage, JsonObject> reply, HttpStatusCode status = HttpStatusCode.OK) : HttpMessageHandler
    {
        public List<Uri> Requests { get; } = [];
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Requests.Add(request.RequestUri!);
            return Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent(reply(request).ToJsonString(), Encoding.UTF8, "application/json") });
        }
    }
}

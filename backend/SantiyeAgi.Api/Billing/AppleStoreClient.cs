using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Options;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.Billing;

public interface IAppleSignedDataVerifier
{
    JsonObject Verify(string signed, string? environment);
}

public sealed class AppleSignedDataVerifier(IOptions<StoreBillingOptions> options) : IAppleSignedDataVerifier
{
    public JsonObject Verify(string signed, string? environment)
    {
        try
        {
            var parts = signed.Split('.');
            if (parts.Length != 3 || signed.Length > 131072) throw new ApiError("INVALID", 422);
            var header = JsonNode.Parse(StoreHttp.Decode(parts[0]))!.AsObject();
            if (header["alg"]?.ToString() != "ES256" || header["x5c"] is not JsonArray certs || certs.Count != 3)
                throw new ApiError("INVALID", 422);
            using var leaf = X509CertificateLoader.LoadCertificate(Convert.FromBase64String(certs[0]!.GetValue<string>()));
            using var intermediate = X509CertificateLoader.LoadCertificate(Convert.FromBase64String(certs[1]!.GetValue<string>()));
            // Apple App Store signing certificate and WWDR intermediate markers.
            if (!leaf.Extensions.Any(x => x.Oid?.Value == "1.2.840.113635.100.6.11.1") ||
                !intermediate.Extensions.Any(x => x.Oid?.Value == "1.2.840.113635.100.6.2.1")) throw new ApiError("INVALID", 422);
            if (options.Value.AppleRootCertificateFiles.Length == 0) throw new ApiError("CONFIG", 503, "Apple güven kökleri yapılandırılmadı.");
            using var chain = new X509Chain();
            chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
            chain.ChainPolicy.RevocationMode = X509RevocationMode.Online;
            chain.ChainPolicy.RevocationFlag = X509RevocationFlag.ExcludeRoot;
            chain.ChainPolicy.UrlRetrievalTimeout = TimeSpan.FromSeconds(10);
            chain.ChainPolicy.ExtraStore.Add(intermediate);
            var roots = new List<X509Certificate2>();
            try
            {
                foreach (var path in options.Value.AppleRootCertificateFiles)
                {
                    var root = X509CertificateLoader.LoadCertificateFromFile(path);
                    roots.Add(root); chain.ChainPolicy.CustomTrustStore.Add(root);
                }
                // x5c's claimed root is deliberately not trusted. Only operator-installed
                // Apple public roots can terminate the chain.
                if (!chain.Build(leaf))
                {
                    if (chain.ChainStatus.Any(x => (x.Status & (X509ChainStatusFlags.OfflineRevocation | X509ChainStatusFlags.RevocationStatusUnknown)) != 0))
                        throw new ApiError("SERVER", 503, "Apple sertifikasının iptal durumu şu anda kontrol edilemiyor.");
                    throw new ApiError("INVALID", 422, "Apple imza zinciri doğrulanamadı.");
                }
                if (chain.ChainElements.Count != 3) throw new ApiError("INVALID", 422);
                using var key = leaf.GetECDsaPublicKey();
                if (key is null || !key.VerifyData(Encoding.ASCII.GetBytes(parts[0] + "." + parts[1]), StoreHttp.Decode(parts[2]),
                    HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation)) throw new ApiError("INVALID", 422);
            }
            finally { foreach (var root in roots) root.Dispose(); }
            var data = JsonNode.Parse(StoreHttp.Decode(parts[1]))!.AsObject();
            if (environment is not null && data["environment"]?.ToString() != environment) throw new ApiError("INVALID", 422);
            return data;
        }
        catch (ApiError) { throw; }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { throw new ApiError("CONFIG", 503); }
        catch (Exception e) when (e is CryptographicException or FormatException or System.Text.Json.JsonException or InvalidOperationException or ArgumentException)
        { throw new ApiError("INVALID", 422, "Apple imzası doğrulanamadı."); }
    }
}

public sealed class AppleStoreClient(HttpClient http, IOptions<StoreBillingOptions> options, IAppleSignedDataVerifier signedData)
{
    private StoreBillingOptions Config => options.Value;
    private async Task<string> Token(CancellationToken ct)
    {
        if (!Config.Enabled || string.IsNullOrWhiteSpace(Config.AppleBundleId) || string.IsNullOrWhiteSpace(Config.AppleIssuerId) ||
            string.IsNullOrWhiteSpace(Config.AppleKeyId) || string.IsNullOrWhiteSpace(Config.ApplePrivateKeyFile) || Config.AppleRootCertificateFiles.Length == 0)
            throw new ApiError("CONFIG", 503, "App Store doğrulaması henüz yapılandırılmadı.");
        using var key = ECDsa.Create();
        try { key.ImportFromPem(await File.ReadAllTextAsync(Config.ApplePrivateKeyFile, ct)); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException or CryptographicException) { throw new ApiError("CONFIG", 503); }
        var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        return StoreHttp.Jwt(new { alg = "ES256", kid = Config.AppleKeyId, typ = "JWT" }, new
        { iss = Config.AppleIssuerId, iat = now, exp = now + 300, aud = "appstoreconnect-v1", bid = Config.AppleBundleId },
            b => key.SignData(b, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation));
    }
    private static string Host(string environment) => environment == "Sandbox" ? "https://api.storekit-sandbox.apple.com" : "https://api.storekit.apple.com";
    private async Task<JsonObject> Get(string path, string environment, string token, CancellationToken ct)
    {
        using var request = StoreHttp.Request(HttpMethod.Get, Host(environment) + path, token);
        return await StoreHttp.Send(http, request, ct);
    }
    // Operational CLI only: request Apple's TEST notification. No receipt is applied.
    // Return only bounded status codes, never the test token, JWT or signedPayload.
    public async Task<JsonObject> CheckTestNotification(bool sandbox, CancellationToken ct, bool accessOnly = false)
    {
        if (sandbox && !Config.AllowSandbox) throw new ApiError("CONFIG", 503, "Sandbox bu ortamda kapalı.");
        var environment = sandbox ? "Sandbox" : "Production";
        var token = await Token(ct);
        using var request = StoreHttp.Request(HttpMethod.Post, Host(environment) + "/inApps/v1/notifications/test", token);
        var sent = await StoreHttp.Send(http, request, ct, receipt: false);
        var testToken = sent["testNotificationToken"]?.ToString() ?? "";
        if (!System.Text.RegularExpressions.Regex.IsMatch(testToken, @"\A[A-Za-z0-9_-]{1,256}\z")) throw new ApiError("SERVER", 503);
        // A successful request proves access to this app's Server API, independently
        // of callback delivery. Never expose the returned opaque token.
        if (accessOnly) return new JsonObject { ["environment"] = environment, ["api_access_verified"] = true };
        var results = new JsonArray();
        for (var poll = 0; poll < 5; poll++)
        {
            var status = await Get("/inApps/v1/notifications/test/" + Uri.EscapeDataString(testToken), environment, token, ct);
            foreach (var attempt in status["sendAttempts"]?.AsArray().OfType<JsonObject>().Take(6) ?? [])
            {
                var result = attempt["sendAttemptResult"]?.ToString() ?? "UNKNOWN";
                if (!System.Text.RegularExpressions.Regex.IsMatch(result, @"\A[A-Z0-9_]{1,80}\z")) result = "UNKNOWN";
                results.Add(result);
            }
            if (results.Count > 0 || poll == 4) break;
            await Task.Delay(TimeSpan.FromSeconds(2), ct);
        }
        return new JsonObject { ["environment"] = environment, ["requested"] = true,
            ["delivered"] = results.Any(x => x?.ToString() == "SUCCESS"), ["attempt_results"] = results };
    }

    public async Task<VerifiedStorePurchase> Verify(string productId, string transactionId, CancellationToken ct)
    {
        if (!StoreCatalog.Products.TryGetValue(productId, out var product)) throw new ApiError("UNKNOWN_PRODUCT", 422);
        if (transactionId.Length > 100 || transactionId.Any(x => !char.IsAsciiDigit(x))) throw new ApiError("INVALID", 422);
        var token = await Token(ct); var environment = "Production"; JsonObject response;
        try { response = await Get("/inApps/v1/transactions/" + transactionId, environment, token, ct); }
        catch (ApiError e) when (e.Code == "INVALID" && Config.AllowSandbox)
        { environment = "Sandbox"; response = await Get("/inApps/v1/transactions/" + transactionId, environment, token, ct); }
        var tx = signedData.Verify(response["signedTransactionInfo"]?.ToString() ?? "", environment);
        ValidateTransaction(tx, productId, Config.AppleBundleId);
        var original = tx["originalTransactionId"]?.ToString() ?? transactionId;
        var state = tx["revocationDate"] is null ? "purchased" : "refunded";
        if (product.Kind == "premium")
        {
            // A restored original transaction is NOT the current renewal. Ask the
            // server for the latest status in the same original transaction chain.
            var statuses = await Get("/inApps/v1/subscriptions/" + transactionId, environment, token, ct);
            if (statuses["bundleId"]?.ToString() != Config.AppleBundleId || statuses["environment"]?.ToString() != environment ||
                environment == "Production" && Config.AppleAppId > 0 && StoreHttp.Long(statuses["appAppleId"]) != Config.AppleAppId) throw new ApiError("INVALID", 422);
            var candidates = new List<(JsonObject Transaction, JsonObject? Renewal, long Status)>();
            foreach (var group in statuses["data"]?.AsArray().OfType<JsonObject>() ?? [])
                foreach (var row in group["lastTransactions"]?.AsArray().OfType<JsonObject>() ?? [])
                {
                    var current = signedData.Verify(row["signedTransactionInfo"]?.ToString() ?? "", environment);
                    if (current["originalTransactionId"]?.ToString() != original) continue;
                    var currentProduct = current["productId"]?.ToString() ?? "";
                    if (!StoreCatalog.Products.TryGetValue(currentProduct, out var known) || known.Kind != "premium") continue;
                    ValidateTransaction(current, currentProduct, Config.AppleBundleId);
                    var renewal = row["signedRenewalInfo"] is null ? null : signedData.Verify(row["signedRenewalInfo"]!.ToString(), environment);
                    if (renewal is not null && renewal["originalTransactionId"]?.ToString() != original) throw new ApiError("INVALID", 422);
                    candidates.Add((current, renewal, StoreHttp.Long(row["status"])));
                }
            var latest = candidates.OrderByDescending(x => StoreHttp.Millis(x.Transaction["purchaseDate"])).FirstOrDefault();
            if (latest.Transaction is null) throw new ApiError("INVALID", 422);
            tx = latest.Transaction;
            var expiry = StoreHttp.Millis(tx["expiresDate"]);
            if (latest.Status == 4 && latest.Renewal is not null) expiry = StoreHttp.Millis(latest.Renewal["gracePeriodExpiresDate"]) ?? expiry;
            var entitled = latest.Status is 1 or 4 && tx["revocationDate"] is null && expiry > DateTimeOffset.UtcNow ? expiry : null;
            return new("ios", original, transactionId, tx["productId"]!.ToString(), product.Kind, tx["appAccountToken"]?.ToString(),
                "subscription_" + latest.Status, environment, entitled);
        }
        var quantity = StoreHttp.Long(tx["quantity"], 1);
        if (quantity is < 1 or > 10000 || tx["type"]?.ToString() != "Consumable") throw new ApiError("INVALID", 422);
        var amount = checked((int)quantity * product.Credits);
        return new("ios", tx["transactionId"]!.ToString(), transactionId, productId, product.Kind, tx["appAccountToken"]?.ToString(), state, environment,
            Credits: amount, RefundedCredits: state == "refunded" ? amount : 0);
    }
    private static void ValidateTransaction(JsonObject tx, string productId, string bundle)
    {
        if (tx["bundleId"]?.ToString() != bundle || tx["productId"]?.ToString() != productId || string.IsNullOrEmpty(tx["transactionId"]?.ToString()))
            throw new ApiError("INVALID", 422);
        if (StoreCatalog.Products[productId].Kind == "premium" && tx["type"]?.ToString() != "Auto-Renewable Subscription") throw new ApiError("INVALID", 422);
    }
}

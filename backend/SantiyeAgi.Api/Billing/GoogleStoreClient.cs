using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Options;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.Billing;

public sealed class GoogleStoreClient(HttpClient http, IOptions<StoreBillingOptions> options)
{
    private readonly SemaphoreSlim _tokenLock = new(1, 1);
    private string _token = "";
    private DateTimeOffset _tokenUntil;
    private StoreBillingOptions Config => options.Value;
    private string Base => "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/" + Uri.EscapeDataString(Config.GooglePackageName) + "/purchases/";
    private async Task<string> Token(CancellationToken ct)
    {
        if (!Config.Enabled || string.IsNullOrWhiteSpace(Config.GooglePackageName) || string.IsNullOrWhiteSpace(Config.GoogleServiceAccountFile))
            throw new ApiError("CONFIG", 503, "Google Play doğrulaması henüz yapılandırılmadı.");
        await _tokenLock.WaitAsync(ct);
        try
        {
            if (_tokenUntil > DateTimeOffset.UtcNow.AddMinutes(2)) return _token;
            JsonObject account;
            try { account = JsonNode.Parse(await File.ReadAllTextAsync(Config.GoogleServiceAccountFile, ct))!.AsObject(); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Text.Json.JsonException) { throw new ApiError("CONFIG", 503); }
            if (account["client_email"] is null || account["private_key"] is null) throw new ApiError("CONFIG", 503);
            using var rsa = RSA.Create();
            try { rsa.ImportFromPem(account["private_key"]!.GetValue<string>()); }
            catch (ArgumentException) { throw new ApiError("CONFIG", 503); }
            var now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            var assertion = StoreHttp.Jwt(new { alg = "RS256", typ = "JWT" }, new
            {
                iss = account["client_email"]!.GetValue<string>(), scope = "https://www.googleapis.com/auth/androidpublisher",
                aud = "https://oauth2.googleapis.com/token", iat = now, exp = now + 3600
            }, b => rsa.SignData(b, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1));
            using var request = new HttpRequestMessage(HttpMethod.Post, "https://oauth2.googleapis.com/token")
            { Content = new FormUrlEncodedContent(new Dictionary<string, string> { ["grant_type"] = "urn:ietf:params:oauth:grant-type:jwt-bearer", ["assertion"] = assertion }) };
            var response = await StoreHttp.Send(http, request, ct, receipt: false);
            _token = response["access_token"]?.GetValue<string>() ?? throw new ApiError("CONFIG", 503);
            _tokenUntil = DateTimeOffset.UtcNow.AddSeconds(Math.Clamp(StoreHttp.Long(response["expires_in"], 3600), 60, 3600));
            return _token;
        }
        finally { _tokenLock.Release(); }
    }
    public async Task<VerifiedStorePurchase> Verify(string productId, string token, CancellationToken ct)
    {
        if (!StoreCatalog.Products.TryGetValue(productId, out var product)) throw new ApiError("UNKNOWN_PRODUCT", 422);
        var access = await Token(ct);
        var path = product.Kind == "premium" ? "subscriptionsv2/tokens/" + Uri.EscapeDataString(token)
            : "products/" + Uri.EscapeDataString(productId) + "/tokens/" + Uri.EscapeDataString(token);
        using var request = StoreHttp.Request(HttpMethod.Get, Base + path, access);
        var data = await StoreHttp.Send(http, request, ct);
        return Parse(productId, token, data, Config.AllowSandbox);
    }
    // Pure parser is covered with signed-server response fixtures, not fake grants.
    public static VerifiedStorePurchase Parse(string productId, string token, JsonObject data, bool allowSandbox)
    {
        var product = StoreCatalog.Products.GetValueOrDefault(productId) ?? throw new ApiError("UNKNOWN_PRODUCT", 422);
        var test = data["testPurchase"] is not null || StoreHttp.Long(data["purchaseType"], -1) == 0;
        if (test && !allowSandbox) throw new ApiError("INVALID", 422, "Test satın alımları bu sunucuda kabul edilmiyor.");
        if (product.Kind == "premium")
        {
            var items = data["lineItems"]?.AsArray() ?? throw new ApiError("INVALID", 422);
            var matching = items.OfType<JsonObject>().Where(x => x["productId"]?.ToString() == productId).ToList();
            if (matching.Count == 0) throw new ApiError("INVALID", 422);
            var state = data["subscriptionState"]?.ToString() ?? "";
            var expiry = matching.Select(x => StoreHttp.Date(x["expiryTime"])).Max();
            var active = state is "SUBSCRIPTION_STATE_ACTIVE" or "SUBSCRIPTION_STATE_IN_GRACE_PERIOD" or "SUBSCRIPTION_STATE_CANCELED";
            var entitled = active && expiry > DateTimeOffset.UtcNow ? expiry : null;
            return new("android", token, token, productId, product.Kind,
                data["externalAccountIdentifiers"]?["obfuscatedExternalAccountId"]?.ToString(), state, test ? "Sandbox" : "Production",
                entitled, Acknowledged: data["acknowledgementState"]?.ToString() == "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED");
        }
        if (data["productId"] is not null && data["productId"]!.ToString() != productId) throw new ApiError("INVALID", 422);
        var purchaseState = StoreHttp.Long(data["purchaseState"], -1);
        if (purchaseState == 2) throw new ApiError("PENDING", 422);
        if (purchaseState is not 0 and not 1) throw new ApiError("INVALID", 422);
        var quantity = StoreHttp.Long(data["quantity"], 1);
        if (quantity is < 1 or > 10000) throw new ApiError("INVALID", 422);
        var refundable = StoreHttp.Long(data["refundableQuantity"], quantity);
        if (refundable < 0 || refundable > quantity) throw new ApiError("INVALID", 422);
        var amount = checked((int)quantity * product.Credits);
        var refunded = purchaseState == 1 ? amount : checked((int)(quantity - refundable) * product.Credits);
        return new("android", token, token, productId, product.Kind, data["obfuscatedExternalAccountId"]?.ToString(),
            purchaseState == 0 ? "purchased" : "refunded", test ? "Sandbox" : "Production", Credits: amount, RefundedCredits: refunded,
            Acknowledged: StoreHttp.Long(data["consumptionState"]) == 1);
    }
    public async Task Acknowledge(VerifiedStorePurchase purchase, CancellationToken ct)
    {
        if (purchase.Acknowledged || (purchase.Kind == "premium" && purchase.EntitledUntil is null) || purchase.RefundedCredits >= purchase.Credits && purchase.Kind == "credits") return;
        var access = await Token(ct);
        var path = purchase.Kind == "premium" ? "subscriptions/" : "products/";
        path += Uri.EscapeDataString(purchase.ProductId) + "/tokens/" + Uri.EscapeDataString(purchase.Reference) + (purchase.Kind == "premium" ? ":acknowledge" : ":consume");
        using var request = StoreHttp.Request(HttpMethod.Post, Base + path, access,
            purchase.Kind == "premium" ? JsonContent.Create(new { }) : null);
        await StoreHttp.Send(http, request, ct, receipt: false);
    }
    public async IAsyncEnumerable<StoreVoid> Voids([EnumeratorCancellation] CancellationToken ct)
    {
        var access = await Token(ct); string? page = null;
        // Always replay the 30-day store window; persisted event hashes deduplicate.
        // No cursor is advanced past a failed page.
        do
        {
            var url = Base + "voidedpurchases?type=1&includeQuantityBasedPartialRefund=true&maxResults=1000";
            if (page is not null) url += "&token=" + Uri.EscapeDataString(page);
            using var request = StoreHttp.Request(HttpMethod.Get, url, access);
            var data = await StoreHttp.Send(http, request, ct, receipt: false);
            foreach (var row in data["voidedPurchases"]?.AsArray().OfType<JsonObject>() ?? [])
            {
                var token = row["purchaseToken"]?.ToString();
                if (string.IsNullOrEmpty(token)) continue;
                yield return new(token, row["orderId"]?.ToString() ?? "", StoreHttp.Long(row["voidedTimeMillis"]),
                    row["voidedQuantity"] is null ? null : checked((int)StoreHttp.Long(row["voidedQuantity"])));
            }
            page = data["tokenPagination"]?["nextPageToken"]?.ToString();
        } while (!string.IsNullOrEmpty(page));
    }
}

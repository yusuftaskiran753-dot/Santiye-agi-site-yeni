using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.RateLimiting;
using Google.Apis.Auth;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Endpoints;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.Billing;

public static class StoreBillingEndpoints
{
    public static IServiceCollection AddStoreBilling(this IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<StoreBillingOptions>(configuration.GetSection("Billing"));
        services.AddHttpClient("store-billing", h => h.Timeout = TimeSpan.FromSeconds(30)).RemoveAllLoggers();
        services.AddSingleton<IAppleSignedDataVerifier, AppleSignedDataVerifier>();
        services.AddSingleton(sp => new GoogleStoreClient(sp.GetRequiredService<IHttpClientFactory>().CreateClient("store-billing"), sp.GetRequiredService<IOptions<StoreBillingOptions>>()));
        services.AddSingleton(sp => new AppleStoreClient(sp.GetRequiredService<IHttpClientFactory>().CreateClient("store-billing"), sp.GetRequiredService<IOptions<StoreBillingOptions>>(), sp.GetRequiredService<IAppleSignedDataVerifier>()));
        services.AddSingleton<IStoreVerifier, StoreVerifier>();
        services.AddScoped<StoreBillingService>();
        services.AddHostedService<StoreBillingReconciler>();
        services.AddRateLimiter(o => o.AddPolicy("billing-callback", c => RateLimitPartition.GetFixedWindowLimiter(
            c.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ => new() { PermitLimit = 120, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 })));
        return services;
    }
    public static void MapStoreBilling(this WebApplication app)
    {
        app.MapPost("/api/v1/billing/verify", (HttpContext c, JsonObject input, StoreBillingService billing, CancellationToken ct) =>
            billing.Verify(ApiEndpoints.Actor(c), input.Text("platform"), input.Text("productId", input.Text("product_id")), input.Text("token"), ct))
            .RequireAuthorization().RequireRateLimiting("api").WithMetadata(new RequestSizeLimitAttribute(16384));

        app.MapPost("/api/v1/billing/sync", async (HttpContext c, AppDbContext db, StoreBillingService billing, CancellationToken ct) =>
        {
            var actor = ApiEndpoints.Actor(c);
            var ids = await db.Set<StorePurchase>().AsNoTracking().Where(x => x.UserId == actor && x.Kind == "premium")
                .OrderByDescending(x => x.CreatedAt).Take(20).Select(x => x.Id).ToListAsync(ct);
            foreach (var id in ids) await billing.Reconcile(id, ct);
            var user = await db.Users.AsNoTracking().SingleAsync(x => x.Id == actor, ct);
            var debt = await db.Set<StoreCreditDebt>().AsNoTracking().Where(x => x.UserId == actor).Select(x => (int?)x.Amount).SingleOrDefaultAsync(ct) ?? 0;
            return new JsonObject { ["ok"] = true, ["credits"] = user.Credits, ["premium_until"] = user.PremiumUntil, ["refunded_credit_debt"] = debt };
        }).RequireAuthorization().RequireRateLimiting("auth");

        app.MapPost("/api/v1/billing/google/notifications", GoogleNotification).AllowAnonymous()
            .RequireRateLimiting("billing-callback").WithMetadata(new RequestSizeLimitAttribute(131072));
        app.MapPost("/api/v1/billing/apple/notifications", AppleNotification).AllowAnonymous()
            .RequireRateLimiting("billing-callback").WithMetadata(new RequestSizeLimitAttribute(131072));
    }
    private static async Task<IResult> GoogleNotification(HttpContext context, JsonObject body, IOptions<StoreBillingOptions> options,
        AppDbContext db, StoreBillingService billing, CancellationToken ct)
    {
        var config = options.Value;
        if (!config.Enabled || string.IsNullOrWhiteSpace(config.GooglePushAudience) || string.IsNullOrWhiteSpace(config.GooglePushServiceAccountEmail)) throw new ApiError("CONFIG", 503);
        var authorization = context.Request.Headers.Authorization.ToString();
        if (!authorization.StartsWith("Bearer ", StringComparison.Ordinal)) throw new ApiError("AUTH_REQUIRED", 401);
        GoogleJsonWebSignature.Payload identity;
        try
        {
            identity = await GoogleJsonWebSignature.ValidateAsync(authorization[7..], new GoogleJsonWebSignature.ValidationSettings
                { Audience = [config.GooglePushAudience], ExpirationTimeClockTolerance = TimeSpan.FromSeconds(30), IssuedAtClockTolerance = TimeSpan.FromSeconds(30) });
        }
        catch (InvalidJwtException) { throw new ApiError("AUTH_REQUIRED", 401); }
        if (!identity.EmailVerified || identity.Email != config.GooglePushServiceAccountEmail) throw new ApiError("AUTH_REQUIRED", 401);
        JsonObject data;
        try
        {
            var encoded = body["message"]?["data"]?.GetValue<string>() ?? "";
            if (encoded.Length > 65536) throw new ApiError("BAD_INPUT");
            data = JsonNode.Parse(Convert.FromBase64String(encoded))!.AsObject();
        }
        catch (Exception e) when (e is FormatException or JsonException or InvalidOperationException) { throw new ApiError("BAD_INPUT"); }
        if (data["packageName"]?.ToString() != config.GooglePackageName) throw new ApiError("INVALID", 422);
        var purchaseToken = data["subscriptionNotification"]?["purchaseToken"]?.ToString()
            ?? data["oneTimeProductNotification"]?["purchaseToken"]?.ToString()
            ?? data["voidedPurchaseNotification"]?["purchaseToken"]?.ToString();
        if (purchaseToken is not null)
        {
            var hash = StoreHttp.Hash("android:" + purchaseToken);
            var id = await db.Set<StorePurchase>().AsNoTracking().Where(x => x.Platform == "android" && x.KeyHash == hash && x.UserId != null).Select(x => (Guid?)x.Id).SingleOrDefaultAsync(ct);
            if (id is not null) await billing.Reconcile(id.Value, ct);
        }
        // The notification is a signal, never an entitlement assertion. Unknown
        // transactions must be bound by a signed-in client's verified purchase.
        return Results.Ok(new { ok = true });
    }
    private static async Task<IResult> AppleNotification(JsonObject body, IOptions<StoreBillingOptions> options,
        IAppleSignedDataVerifier signature, AppDbContext db, StoreBillingService billing, CancellationToken ct)
    {
        var config = options.Value;
        if (!config.Enabled || config.AppleAppId <= 0) throw new ApiError("CONFIG", 503);
        var payload = signature.Verify(body.Text("signedPayload"), null);
        var data = payload["data"]?.AsObject();
        if (data is null) throw new ApiError("INVALID", 422);
        var environment = data["environment"]?.ToString();
        if (data["bundleId"]?.ToString() != config.AppleBundleId || environment is not "Production" and not "Sandbox" ||
            environment == "Sandbox" && !config.AllowSandbox || environment == "Production" && StoreHttp.Long(data["appAppleId"]) != config.AppleAppId)
            throw new ApiError("INVALID", 422);
        if (data["signedTransactionInfo"] is not null)
        {
            var tx = signature.Verify(data["signedTransactionInfo"]!.ToString(), environment);
            if (tx["bundleId"]?.ToString() != config.AppleBundleId) throw new ApiError("INVALID", 422);
            var productId = tx["productId"]?.ToString() ?? "";
            if (!StoreCatalog.Products.TryGetValue(productId, out var product)) return Results.Ok(new { ok = true });
            var key = product.Kind == "premium" ? tx["originalTransactionId"]?.ToString() : tx["transactionId"]?.ToString();
            if (key is null) throw new ApiError("INVALID", 422);
            var hash = StoreHttp.Hash("ios:" + key);
            var id = await db.Set<StorePurchase>().AsNoTracking().Where(x => x.Platform == "ios" && x.KeyHash == hash && x.UserId != null).Select(x => (Guid?)x.Id).SingleOrDefaultAsync(ct);
            if (id is not null) await billing.Reconcile(id.Value, ct);
        }
        return Results.Ok(new { ok = true });
    }
}

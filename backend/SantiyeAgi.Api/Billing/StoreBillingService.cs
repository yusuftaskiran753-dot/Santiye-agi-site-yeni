using System.Data;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.Billing;

public sealed class StoreBillingService(AppDbContext db, IStoreVerifier verifier, IDataProtectionProvider protection, IOptions<StoreBillingOptions> options)
{
    private readonly IDataProtector _protector = protection.CreateProtector("SantiyeAgi.StoreReceipt.v1");
    public async Task<JsonObject> Verify(Guid actor, string platform, string productId, string reference, CancellationToken ct = default)
    {
        if (!options.Value.Enabled) throw new ApiError("CONFIG", 503, "Mağaza bağlantısı henüz yapılandırılmadı.");
        if (platform is not "android" and not "ios" || reference.Length is < 1 or > 8192 || !StoreCatalog.Products.ContainsKey(productId)) throw new ApiError("BAD_INPUT");
        var verified = await verifier.Verify(platform, productId, reference, ct);
        var row = await Apply(actor, verified, ct);
        if (!row.Acknowledged && CanAcknowledge(verified))
        {
            // The purchase is already durable. Retrying after an acknowledgement
            // failure can never add the same credits a second time.
            await verifier.Acknowledge(verified, ct);
            await db.Set<StorePurchase>().Where(x => x.Id == row.Id).ExecuteUpdateAsync(s => s.SetProperty(x => x.Acknowledged, true), ct);
        }
        var user = await db.Users.AsNoTracking().SingleAsync(x => x.Id == actor, ct);
        if (verified.State is "SUBSCRIPTION_STATE_PENDING" or "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED")
            return new() { ["ok"] = false, ["error"] = "PENDING" };
        if (verified.Kind == "premium" && !(row.EntitledUntil > DateTimeOffset.UtcNow))
            return new() { ["ok"] = false, ["error"] = "EXPIRED", ["premium_until"] = user.PremiumUntil };
        if (verified.Kind == "credits" && row.CreditsRevoked >= row.CreditsAwarded)
            return new() { ["ok"] = false, ["error"] = "REVOKED", ["credits"] = user.Credits };
        return new() { ["ok"] = true, ["kind"] = verified.Kind, ["credits"] = user.Credits, ["premium_until"] = user.PremiumUntil };
    }
    public async Task<StorePurchase> Apply(Guid actor, VerifiedStorePurchase receipt, CancellationToken ct = default)
    {
        if (receipt.Platform is not "android" and not "ios" || !StoreCatalog.Products.TryGetValue(receipt.ProductId, out var product) || product.Kind != receipt.Kind ||
            receipt.Credits is < 0 or > 400000 || receipt.RefundedCredits < 0 || receipt.RefundedCredits > receipt.Credits ||
            receipt.Kind == "credits" && receipt.Credits == 0) throw new ApiError("INVALID", 422);
        if (!Guid.TryParse(receipt.AccountId, out var boundAccount) || boundAccount != actor) throw new ApiError("ACCOUNT_MISMATCH", 409,
            "Satın alma bu uygulama hesabına ait değil veya hesap eşleştirme bilgisi eksik.");
        var hash = StoreHttp.Hash(receipt.Platform + ":" + receipt.PurchaseKey);
        await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.ReadCommitted, ct);
        await Lock(actor, hash, ct);
        var user = await db.Users.SingleOrDefaultAsync(x => x.Id == actor, ct) ?? throw new ApiError("AUTH_REQUIRED", 401);
        await db.Entry(user).ReloadAsync(ct);
        if (!user.PhoneVerified) throw new ApiError("PHONE_REQUIRED", 403);
        var row = await db.Set<StorePurchase>().SingleOrDefaultAsync(x => x.Platform == receipt.Platform && x.KeyHash == hash, ct);
        if (row is not null) await db.Entry(row).ReloadAsync(ct);
        if (row is not null && row.UserId != actor) throw new ApiError("ALREADY_USED", 409);
        if (row is null)
        {
            row = new() { UserId = actor, Platform = receipt.Platform, KeyHash = hash, Kind = receipt.Kind, CreditsAwarded = receipt.Credits,
                ProductId = receipt.ProductId, Environment = receipt.Environment, ProtectedReference = _protector.Protect(receipt.Reference) };
            db.Set<StorePurchase>().Add(row);
            if (receipt.Kind == "credits") await AdjustCredits(user, receipt.Credits, "purchase:" + row.Id, ct);
        }
        else if (row.Kind != receipt.Kind || row.CreditsAwarded != receipt.Credits || row.Environment != receipt.Environment)
            throw new ApiError("INVALID", 422);
        row.ProductId = receipt.ProductId; // A subscription may upgrade/downgrade in the same Apple chain.
        row.ProtectedReference = _protector.Protect(receipt.Reference);
        row.State = receipt.State; row.EntitledUntil = receipt.EntitledUntil; row.CheckedAt = DateTimeOffset.UtcNow;
        row.NextCheckAt = row.CheckedAt.Add(receipt.Kind == "premium" ? TimeSpan.FromMinutes(15) : TimeSpan.FromHours(12));
        row.Acknowledged = row.Acknowledged || receipt.Acknowledged;
        row.ReportedRefundCredits = Math.Max(row.ReportedRefundCredits, receipt.RefundedCredits);
        await ApplyRefund(user, row, ct);
        await db.SaveChangesAsync(ct);
        if (receipt.Kind == "premium") await RecalculatePremium(user, ct);
        await db.SaveChangesAsync(ct); await transaction.CommitAsync(ct);
        return row;
    }
    private async Task Lock(Guid actor, string hash, CancellationToken ct)
    {
        var purchaseLock = new Guid(Convert.FromHexString(hash)[..16]);
        foreach (var id in new[] { actor, purchaseLock }.Distinct().Order())
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({id.ToString()}, 0))", ct);
    }
    private async Task RecalculatePremium(User user, CancellationToken ct)
    {
        var now = DateTimeOffset.UtcNow;
        user.PremiumUntil = await db.Set<StorePurchase>().Where(x => x.UserId == user.Id && x.Kind == "premium" && x.EntitledUntil > now)
            .MaxAsync(x => x.EntitledUntil, ct);
    }
    private async Task ApplyRefund(User user, StorePurchase row, CancellationToken ct)
    {
        var refunded = Math.Min(row.CreditsAwarded, Math.Max(row.ReportedRefundCredits, row.VoidRefundCredits));
        if (refunded <= row.CreditsRevoked) return;
        var debit = refunded - row.CreditsRevoked;
        await AdjustCredits(user, -debit, "refund:" + row.Id, ct);
        row.CreditsRevoked = refunded;
    }
    private async Task AdjustCredits(User user, int amount, string reason, CancellationToken ct)
    {
        var debt = await db.Set<StoreCreditDebt>().FindAsync([user.Id], ct);
        if (amount < 0)
        {
            var deduct = Math.Min(user.Credits, -amount); user.Credits -= deduct;
            var remaining = -amount - deduct;
            if (remaining > 0)
            {
                if (debt is null) { debt = new() { UserId = user.Id }; db.Set<StoreCreditDebt>().Add(debt); }
                debt.Amount = checked(debt.Amount + remaining);
            }
            db.CreditEntries.Add(new() { UserId = user.Id, Delta = -deduct, Reason = reason });
        }
        else
        {
            var settle = Math.Min(debt?.Amount ?? 0, amount);
            if (debt is not null) debt.Amount -= settle;
            user.Credits = checked(user.Credits + amount - settle);
            db.CreditEntries.Add(new() { UserId = user.Id, Delta = amount - settle, Reason = reason + (settle > 0 ? ":debt-settled=" + settle : "") });
        }
    }
    public async Task Reconcile(Guid purchaseId, CancellationToken ct)
    {
        var row = await db.Set<StorePurchase>().AsNoTracking().SingleOrDefaultAsync(x => x.Id == purchaseId, ct);
        if (row?.UserId is not Guid actor || row.ProtectedReference.Length == 0) return;
        string reference;
        try { reference = _protector.Unprotect(row.ProtectedReference); }
        catch (System.Security.Cryptography.CryptographicException) { throw new ApiError("CONFIG", 503, "Mağaza kayıtları için sunucu anahtar halkası erişilemiyor."); }
        var receipt = await verifier.Verify(row.Platform, row.ProductId, reference, ct);
        var updated = await Apply(actor, receipt, ct);
        if (!updated.Acknowledged && CanAcknowledge(receipt))
        {
            await verifier.Acknowledge(receipt, ct);
            await db.Set<StorePurchase>().Where(x => x.Id == purchaseId).ExecuteUpdateAsync(s => s.SetProperty(x => x.Acknowledged, true), ct);
        }
    }
    private static bool CanAcknowledge(VerifiedStorePurchase receipt) => receipt.Kind == "premium"
        ? receipt.EntitledUntil > DateTimeOffset.UtcNow
        : receipt.Credits > receipt.RefundedCredits;
    public async Task ApplyGoogleVoid(StoreVoid item, CancellationToken ct)
    {
        var hash = StoreHttp.Hash("android:" + item.PurchaseToken);
        var existing = await db.Set<StorePurchase>().AsNoTracking().SingleOrDefaultAsync(x => x.Platform == "android" && x.KeyHash == hash, ct);
        if (existing?.UserId is not Guid actor) return;
        if (existing.Kind == "premium")
        {
            // Renewal orders share the same token. Refunding an OLD order must not
            // revoke a later paid renewal. The current subscription API is decisive.
            await Reconcile(existing.Id, ct); return;
        }
        var eventHash = StoreHttp.Hash("google-void:" + hash + ":" + item.OrderId + ":" + item.VoidedTime + ":" + item.Quantity);
        await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.ReadCommitted, ct);
        await Lock(actor, hash, ct);
        if (await db.Set<StoreRefund>().AnyAsync(x => x.EventHash == eventHash, ct)) return;
        var row = await db.Set<StorePurchase>().SingleAsync(x => x.Id == existing.Id, ct);
        await db.Entry(row).ReloadAsync(ct);
        var user = await db.Users.SingleOrDefaultAsync(x => x.Id == actor, ct);
        if (user is null) return;
        await db.Entry(user).ReloadAsync(ct);
        var unit = StoreCatalog.Products[row.ProductId].Credits;
        row.VoidRefundCredits = item.Quantity is null ? row.CreditsAwarded
            : Math.Min(row.CreditsAwarded, checked(row.VoidRefundCredits + Math.Max(0, item.Quantity.Value) * unit));
        db.Set<StoreRefund>().Add(new() { EventHash = eventHash, PurchaseId = row.Id });
        await ApplyRefund(user, row, ct);
        await db.SaveChangesAsync(ct); await transaction.CommitAsync(ct);
    }
    public async Task ForgetAccount(Guid actor, CancellationToken ct = default)
    {
        // Call before deleting the account. Only non-redeemable purchase hashes
        // remain; encrypted references that could query store history are erased.
        await db.Set<StorePurchase>().Where(x => x.UserId == actor).ExecuteUpdateAsync(s => s
            .SetProperty(x => x.ProtectedReference, "").SetProperty(x => x.EntitledUntil, (DateTimeOffset?)null), ct);
    }
}

using Microsoft.EntityFrameworkCore;
using SantiyeAgi.Api.Data;

namespace SantiyeAgi.Api.Billing;

// Receipt credentials never leave the server. A keyed Data Protection payload is
// persisted for subsequent store reconciliation, not a raw purchase token.
public sealed class StorePurchase
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid? UserId { get; set; }
    public string Platform { get; set; } = "";
    public string KeyHash { get; set; } = "";
    public string ProtectedReference { get; set; } = "";
    public string ProductId { get; set; } = "";
    public string Kind { get; set; } = "";
    public string State { get; set; } = "";
    public string Environment { get; set; } = "";
    public int CreditsAwarded { get; set; }
    public int CreditsRevoked { get; set; }
    public int ReportedRefundCredits { get; set; }
    public int VoidRefundCredits { get; set; }
    public DateTimeOffset? EntitledUntil { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset CheckedAt { get; set; }
    public DateTimeOffset NextCheckAt { get; set; } = DateTimeOffset.UtcNow;
    public bool Acknowledged { get; set; }
}

public sealed class StoreRefund
{
    public string EventHash { get; set; } = "";
    public Guid PurchaseId { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

// Spent refunded credits remain a debt; future credit purchases settle it first.
public sealed class StoreCreditDebt
{
    public Guid UserId { get; set; }
    public int Amount { get; set; }
}

public static class BillingModel
{
    public static void Configure(ModelBuilder m)
    {
        m.Entity<StorePurchase>().ToTable("StorePurchases");
        m.Entity<StorePurchase>().HasIndex(x => new { x.Platform, x.KeyHash }).IsUnique();
        m.Entity<StorePurchase>().HasIndex(x => x.NextCheckAt);
        m.Entity<StorePurchase>().HasIndex(x => x.UserId);
        m.Entity<StorePurchase>().Property(x => x.Platform).HasMaxLength(10);
        m.Entity<StorePurchase>().Property(x => x.KeyHash).HasMaxLength(64);
        m.Entity<StorePurchase>().Property(x => x.ProductId).HasMaxLength(200);
        // Tombstones keep a deleted account's transaction from being spent again.
        m.Entity<StorePurchase>().HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.SetNull);
        m.Entity<StoreRefund>().ToTable("StoreRefunds");
        m.Entity<StoreRefund>().HasKey(x => x.EventHash);
        m.Entity<StoreRefund>().Property(x => x.EventHash).HasMaxLength(64);
        m.Entity<StoreRefund>().HasOne<StorePurchase>().WithMany().HasForeignKey(x => x.PurchaseId).OnDelete(DeleteBehavior.Cascade);
        m.Entity<StoreCreditDebt>().ToTable("StoreCreditDebts");
        m.Entity<StoreCreditDebt>().HasKey(x => x.UserId);
        m.Entity<StoreCreditDebt>().HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
    }
}

public sealed record StoreProduct(string Id, string Kind, int Credits = 0);
public static class StoreCatalog
{
    public static readonly IReadOnlyDictionary<string, StoreProduct> Products = new Dictionary<string, StoreProduct>(StringComparer.Ordinal)
    {
        ["santiye_premium_aylik"] = new("santiye_premium_aylik", "premium"),
        ["santiye_premium_yillik"] = new("santiye_premium_yillik", "premium"),
        ["santiye_kredi_5"] = new("santiye_kredi_5", "credits", 5),
        ["santiye_kredi_15"] = new("santiye_kredi_15", "credits", 15),
        ["santiye_kredi_40"] = new("santiye_kredi_40", "credits", 40)
    };
}

public sealed record VerifiedStorePurchase(
    string Platform, string PurchaseKey, string Reference, string ProductId,
    string Kind, string? AccountId, string State, string Environment,
    DateTimeOffset? EntitledUntil = null, int Credits = 0,
    int RefundedCredits = 0, bool Acknowledged = true);

public sealed record StoreVoid(string PurchaseToken, string OrderId, long VoidedTime, int? Quantity);

public sealed class StoreBillingOptions
{
    public bool Enabled { get; set; }
    public bool AllowSandbox { get; set; }
    public string GooglePackageName { get; set; } = "";
    public string GoogleServiceAccountFile { get; set; } = "";
    public string AppleBundleId { get; set; } = "";
    public long AppleAppId { get; set; }
    public string AppleIssuerId { get; set; } = "";
    public string AppleKeyId { get; set; } = "";
    public string ApplePrivateKeyFile { get; set; } = "";
    public string[] AppleRootCertificateFiles { get; set; } = [];
    public string GooglePushAudience { get; set; } = "";
    public string GooglePushServiceAccountEmail { get; set; } = "";
}

public interface IStoreVerifier
{
    Task<VerifiedStorePurchase> Verify(string platform, string productId, string reference, CancellationToken ct);
    Task Acknowledge(VerifiedStorePurchase purchase, CancellationToken ct);
    IAsyncEnumerable<StoreVoid> GoogleVoids(CancellationToken ct);
}

using System.Runtime.CompilerServices;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Npgsql;
using SantiyeAgi.Api.Billing;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.Tests;

[Collection("Postgres")]
public class BillingIntegrationTests : IAsyncLifetime
{
    private string _admin = ""; private string _database = ""; private string _connection = "";
    private readonly EphemeralDataProtectionProvider _protection = new();
    public async Task InitializeAsync()
    {
        _admin = Environment.GetEnvironmentVariable("SANTIYE_TEST_POSTGRES") ?? throw new InvalidOperationException("Set local SANTIYE_TEST_POSTGRES.");
        var connection = new NpgsqlConnectionStringBuilder(_admin);
        if (connection.Host is not "127.0.0.1" and not "localhost") throw new InvalidOperationException("Tests require localhost.");
        _database = "santiye_test_" + Guid.NewGuid().ToString("N");
        await using (var admin = new NpgsqlConnection(_admin))
        {
            await admin.OpenAsync(); await using var command = new NpgsqlCommand($"CREATE DATABASE \"{_database}\"", admin); await command.ExecuteNonQueryAsync();
        }
        connection.Database = _database; _connection = connection.ConnectionString;
        await using var db = Db(); await db.Database.MigrateAsync();
    }
    public async Task DisposeAsync()
    {
        NpgsqlConnection.ClearAllPools();
        if (_database.StartsWith("santiye_test_") && _database.Length == 45)
        {
            await using var admin = new NpgsqlConnection(_admin); await admin.OpenAsync();
            await using var command = new NpgsqlCommand($"DROP DATABASE \"{_database}\" WITH (FORCE)", admin); await command.ExecuteNonQueryAsync();
        }
    }
    private AppDbContext Db() => new(new DbContextOptionsBuilder<AppDbContext>().UseNpgsql(_connection).Options);
    private StoreBillingService Billing(AppDbContext db, IStoreVerifier verifier) => new(db, verifier, _protection, Options.Create(new StoreBillingOptions { Enabled = true }));
    private async Task<Guid> User()
    {
        await using var db = Db(); var user = new User { PhoneVerified = true, ProfileComplete = true };
        db.Users.Add(user); await db.SaveChangesAsync(); return user.Id;
    }
    private static VerifiedStorePurchase Credit(Guid user, string token = "unique-token", int credits = 15, int refunded = 0) => new("android", token, token,
        credits == 40 ? "santiye_kredi_40" : credits == 5 ? "santiye_kredi_5" : "santiye_kredi_15", "credits", user.ToString(), "purchased", "Production", Credits: credits, RefundedCredits: refunded, Acknowledged: false);
    [Fact]
    public async Task ConcurrentVerifiedPurchaseOnlyAwardsOnce()
    {
        var user = await User(); var receipt = Credit(user);
        await Task.WhenAll(Enumerable.Range(0, 4).Select(async _ => { await using var db = Db(); await Billing(db, new StubVerifier(receipt)).Verify(user, "android", receipt.ProductId, receipt.Reference); }));
        await using var check = Db(); Assert.Equal(15, (await check.Users.FindAsync(user))!.Credits);
        Assert.Single(await check.Set<StorePurchase>().ToListAsync()); Assert.Single(await check.CreditEntries.ToListAsync());
    }
    [Fact]
    public async Task MissingAccountAndCrossAccountReplayCannotGrant()
    {
        var user = await User(); var other = await User(); var receipt = Credit(user);
        await using (var db = Db()) await Billing(db, new StubVerifier(receipt)).Apply(user, receipt);
        await using (var db = Db()) Assert.Equal("ACCOUNT_MISMATCH", (await Assert.ThrowsAsync<ApiError>(() => Billing(db, new StubVerifier(receipt)).Apply(other, receipt))).Code);
        await using (var db = Db()) Assert.Equal("ALREADY_USED", (await Assert.ThrowsAsync<ApiError>(() => Billing(db, new StubVerifier(receipt)).Apply(other, receipt with { AccountId = other.ToString() }))).Code);
        await using (var db = Db()) Assert.Equal("ACCOUNT_MISMATCH", (await Assert.ThrowsAsync<ApiError>(() => Billing(db, new StubVerifier(receipt)).Apply(user, receipt with { AccountId = null, PurchaseKey = "new" }))).Code);
        await using var check = Db(); Assert.Equal(0, (await check.Users.FindAsync(other))!.Credits); Assert.Single(await check.Set<StorePurchase>().ToListAsync());
    }
    [Fact]
    public async Task RefundDebtSurvivesSpentCreditsAndSettlesFuturePurchase()
    {
        var user = await User(); var receipt = Credit(user);
        await using (var db = Db()) await Billing(db, new StubVerifier(receipt)).Apply(user, receipt);
        await using (var db = Db()) { (await db.Users.FindAsync(user))!.Credits = 3; await db.SaveChangesAsync(); }
        await using (var db = Db()) await Billing(db, new StubVerifier(receipt)).Apply(user, receipt with { RefundedCredits = 15 });
        await using (var db = Db())
        {
            Assert.Equal(0, (await db.Users.FindAsync(user))!.Credits); Assert.Equal(12, (await db.Set<StoreCreditDebt>().FindAsync(user))!.Amount);
        }
        await using (var db = Db()) await Billing(db, new StubVerifier(receipt)).Apply(user, receipt with { RefundedCredits = 15 });
        var next = Credit(user, "new-credit-token", 40);
        await using (var db = Db()) await Billing(db, new StubVerifier(next)).Apply(user, next);
        await using var check = Db(); Assert.Equal(28, (await check.Users.FindAsync(user))!.Credits); Assert.Equal(0, (await check.Set<StoreCreditDebt>().FindAsync(user))!.Amount);
    }
    [Fact]
    public async Task VoidedPartialRefundAndStoreReportedRefundDoNotDoubleDebit()
    {
        var user = await User(); var receipt = Credit(user, credits: 15);
        // A multi-quantity package contains three five-credit units.
        receipt = receipt with { ProductId = "santiye_kredi_5", RefundedCredits = 5 };
        await using (var db = Db()) await Billing(db, new StubVerifier(receipt)).Apply(user, receipt);
        var item = new StoreVoid(receipt.Reference, "order", 1000, 1);
        await using (var db = Db()) await Billing(db, new StubVerifier(receipt)).ApplyGoogleVoid(item, default);
        await using (var db = Db()) await Billing(db, new StubVerifier(receipt)).ApplyGoogleVoid(item, default);
        await using (var db = Db()) Assert.Equal(10, (await db.Users.FindAsync(user))!.Credits);
        await using (var db = Db()) await Billing(db, new StubVerifier(receipt)).ApplyGoogleVoid(item with { VoidedTime = 2000 }, default);
        await using var check = Db(); Assert.Equal(5, (await check.Users.FindAsync(user))!.Credits); Assert.Equal(2, await check.Set<StoreRefund>().CountAsync());
    }
    [Fact]
    public async Task SubscriptionCanShortenAndOtherActiveSubscriptionIsPreserved()
    {
        var user = await User(); var now = DateTimeOffset.UtcNow;
        var first = new VerifiedStorePurchase("ios", "first", "1", "santiye_premium_aylik", "premium", user.ToString(), "active", "Production", now.AddDays(30));
        var second = first with { PurchaseKey = "second", Reference = "2", EntitledUntil = now.AddDays(10) };
        await using (var db = Db()) await Billing(db, new StubVerifier(first)).Apply(user, first);
        await using (var db = Db()) await Billing(db, new StubVerifier(second)).Apply(user, second);
        await using (var db = Db()) await Billing(db, new StubVerifier(first)).Apply(user, first with { State = "refunded", EntitledUntil = null });
        await using (var db = Db()) Assert.Equal(second.EntitledUntil!.Value.ToUnixTimeSeconds(), (await db.Users.FindAsync(user))!.PremiumUntil!.Value.ToUnixTimeSeconds());
        await using (var db = Db()) await Billing(db, new StubVerifier(second)).Apply(user, second with { EntitledUntil = null });
        await using var check = Db(); Assert.Null((await check.Users.FindAsync(user))!.PremiumUntil);
    }
    [Fact]
    public async Task FailedAcknowledgementRetriesAfterDurableGrantWithoutDuplication()
    {
        var user = await User(); var receipt = Credit(user, credits: 5); var verifier = new StubVerifier(receipt) { AckFailures = 1 };
        await using (var db = Db()) Assert.Equal("SERVER", (await Assert.ThrowsAsync<ApiError>(() => Billing(db, verifier).Verify(user, "android", receipt.ProductId, receipt.Reference))).Code);
        await using (var db = Db())
        {
            Assert.Equal(5, (await db.Users.FindAsync(user))!.Credits);
            var purchase = await db.Set<StorePurchase>().SingleAsync(); Assert.False(purchase.Acknowledged); Assert.DoesNotContain(receipt.Reference, purchase.ProtectedReference);
        }
        await using (var db = Db()) Assert.True((await Billing(db, verifier).Verify(user, "android", receipt.ProductId, receipt.Reference))["ok"]!.GetValue<bool>());
        await using var check = Db(); Assert.Equal(5, (await check.Users.FindAsync(user))!.Credits); Assert.True((await check.Set<StorePurchase>().SingleAsync()).Acknowledged);
    }
    [Fact]
    public async Task UnverifiedReceiptNeverWritesPurchaseOrCredits()
    {
        var user = await User(); var verifier = new StubVerifier(Credit(user)) { VerifyFailure = true };
        await using (var db = Db()) await Assert.ThrowsAsync<ApiError>(() => Billing(db, verifier).Verify(user, "android", "santiye_kredi_15", "arbitrary"));
        await using var check = Db(); Assert.Equal(0, (await check.Users.FindAsync(user))!.Credits); Assert.Empty(await check.Set<StorePurchase>().ToListAsync());
    }
    [Fact]
    public async Task DeletedAccountPurchaseIsNotRedeemableAgainAndReferenceIsPurged()
    {
        var user = await User(); var other = await User(); var receipt = Credit(user);
        await using (var db = Db()) await Billing(db, new StubVerifier(receipt)).Apply(user, receipt);
        await using (var db = Db())
        {
            await Billing(db, new StubVerifier(receipt)).ForgetAccount(user);
            db.Users.Remove((await db.Users.FindAsync(user))!); await db.SaveChangesAsync();
        }
        await using (var db = Db()) Assert.Equal("ALREADY_USED", (await Assert.ThrowsAsync<ApiError>(() => Billing(db, new StubVerifier(receipt)).Apply(other, receipt with { AccountId = other.ToString() }))).Code);
        await using var check = Db(); var purchase = await check.Set<StorePurchase>().SingleAsync(); Assert.Null(purchase.UserId); Assert.Empty(purchase.ProtectedReference);
    }
    private sealed class StubVerifier(VerifiedStorePurchase receipt) : IStoreVerifier
    {
        public int AckFailures { get; set; }
        public bool VerifyFailure { get; set; }
        public Task<VerifiedStorePurchase> Verify(string platform, string productId, string reference, CancellationToken ct) => VerifyFailure ? throw new ApiError("INVALID", 422) : Task.FromResult(receipt);
        public Task Acknowledge(VerifiedStorePurchase purchase, CancellationToken ct)
        { if (AckFailures-- > 0) throw new ApiError("SERVER", 503); return Task.CompletedTask; }
        public async IAsyncEnumerable<StoreVoid> GoogleVoids([EnumeratorCancellation] CancellationToken ct) { await Task.CompletedTask; yield break; }
    }
}

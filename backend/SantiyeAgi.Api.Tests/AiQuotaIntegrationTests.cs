using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Options;
using Npgsql;
using SantiyeAgi.Api.AI;
using SantiyeAgi.Api.Auth;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.Tests;

/// The only provider is a local HttpMessageHandler. Every test creates and later
/// drops its own database; non-local PostgreSQL servers are refused before use.
[Collection("Postgres")]
public sealed class AiQuotaIntegrationTests : IAsyncLifetime
{
    private WebApplicationFactory<Program> _factory = null!;
    private string _database = "", _admin = "", _keysPath = "";
    private string? _previousConnection, _previousKey, _previousProtection;
    private readonly AiClock _clock = new();
    private readonly AiTests.Handler _provider;
    private Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> _reply =
        (_, _) => Task.FromResult(AiTests.ProviderResponse(AiTests.ValidResult));

    public AiQuotaIntegrationTests() => _provider = new((request, ct) => _reply(request, ct));

    private sealed class AiClock : TimeProvider
    {
        private long _ticks = new DateTimeOffset(2026, 10, 20, 10, 0, 0, TimeSpan.Zero).Ticks;
        public override DateTimeOffset GetUtcNow() => new(Interlocked.Read(ref _ticks), TimeSpan.Zero);
        public void Advance(TimeSpan span) => Interlocked.Add(ref _ticks, span.Ticks);
    }

    public async Task InitializeAsync()
    {
        _admin = Environment.GetEnvironmentVariable("SANTIYE_TEST_POSTGRES")
            ?? throw new InvalidOperationException("Set SANTIYE_TEST_POSTGRES to a dedicated local test PostgreSQL connection.");
        var connection = new NpgsqlConnectionStringBuilder(_admin);
        if (connection.Host is not "localhost" and not "127.0.0.1") throw new InvalidOperationException("AI tests only run on localhost.");
        _database = "santiye_test_" + Guid.NewGuid().ToString("N");
        await using (var admin = new NpgsqlConnection(_admin))
        {
            await admin.OpenAsync();
            await using var create = new NpgsqlCommand($"CREATE DATABASE \"{_database}\"", admin);
            await create.ExecuteNonQueryAsync();
        }
        connection.Database = _database;
        _previousConnection = Environment.GetEnvironmentVariable("ConnectionStrings__Postgres");
        _previousKey = Environment.GetEnvironmentVariable("Auth__SigningKey");
        _previousProtection = Environment.GetEnvironmentVariable("DataProtection__KeysPath");
        _keysPath = Path.Combine(Path.GetTempPath(), "santiye_test_ai_keys_" + Guid.NewGuid().ToString("N"));
        Environment.SetEnvironmentVariable("ConnectionStrings__Postgres", connection.ConnectionString);
        Environment.SetEnvironmentVariable("Auth__SigningKey", new string('A', 64));
        Environment.SetEnvironmentVariable("DataProtection__KeysPath", _keysPath);
        var config = new Dictionary<string, string?>
        {
            ["Auth:RequirePhoneVerification"] = "false",
            ["AI:Enabled"] = "true", ["AI:ApiKey"] = "LOCAL-FAKE-KEY-NEVER-SENT-TO-NETWORK",
            ["AI:DailyLimit"] = "30", ["AI:PremiumDailyLimit"] = "200",
            ["AI:GlobalDailyRequestLimit"] = "1000", ["AI:MaxConcurrency"] = "2",
            ["AI:TimeoutSeconds"] = "12", ["AI:MaxOutputTokens"] = "2048"
        };
        _factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
            builder.UseEnvironment("Development")
                .ConfigureAppConfiguration((_, c) => c.AddInMemoryCollection(config))
                .ConfigureServices(services =>
                {
                    services.RemoveAll<TimeProvider>(); services.AddSingleton<TimeProvider>(_clock);
                    services.RemoveAll<IGeminiClient>();
                    services.AddTransient<IGeminiClient>(sp => new GeminiClient(new HttpClient(_provider, disposeHandler: false), sp.GetRequiredService<IOptions<AiOptions>>()));
                }));
        using var scope = _factory.Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.MigrateAsync();
    }

    public async Task DisposeAsync()
    {
        if (_factory is not null) await _factory.DisposeAsync();
        _provider.Dispose();
        Environment.SetEnvironmentVariable("ConnectionStrings__Postgres", _previousConnection);
        Environment.SetEnvironmentVariable("Auth__SigningKey", _previousKey);
        Environment.SetEnvironmentVariable("DataProtection__KeysPath", _previousProtection);
        var temporaryRoot = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar);
        if (Directory.Exists(_keysPath) && Path.GetDirectoryName(Path.GetFullPath(_keysPath)) == temporaryRoot &&
            Path.GetFileName(_keysPath).StartsWith("santiye_test_ai_keys_", StringComparison.Ordinal)) Directory.Delete(_keysPath, recursive: true);
        NpgsqlConnection.ClearAllPools();
        if (_database.StartsWith("santiye_test_", StringComparison.Ordinal) && _database.Length == 45)
        {
            await using var admin = new NpgsqlConnection(_admin); await admin.OpenAsync();
            await using var drop = new NpgsqlCommand($"DROP DATABASE \"{_database}\" WITH (FORCE)", admin);
            await drop.ExecuteNonQueryAsync();
        }
    }

    private WebApplicationFactory<Program> Config(params (string Key, string Value)[] values) =>
        _factory.WithWebHostBuilder(b => b.ConfigureAppConfiguration((_, c) =>
            c.AddInMemoryCollection(values.ToDictionary(x => x.Key, x => (string?)x.Value))));

    private async Task<(HttpClient Client, Guid User)> Login(WebApplicationFactory<Program>? factory = null, bool premium = false, bool verified = false, bool profileComplete = true)
    {
        factory ??= _factory;
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var user = new User { Name = "Yerel AI Test", ProfileComplete = profileComplete, PhoneVerified = verified,
            City = "Ankara", PremiumUntil = premium ? _clock.GetUtcNow().AddDays(3) : null, Credits = 40 };
        var refresh = TokenService.NewRefresh();
        var session = new Session { UserId = user.Id, RefreshHash = TokenService.Hash(refresh), ExpiresAt = DateTimeOffset.UtcNow.AddHours(1) };
        db.Users.Add(user); db.Sessions.Add(session); await db.SaveChangesAsync();
        var token = scope.ServiceProvider.GetRequiredService<TokenService>().Issue(user, session, refresh)["access_token"]!.GetValue<string>();
        var client = factory.CreateClient(); client.DefaultRequestHeaders.Authorization = new("Bearer", token);
        return (client, user.Id);
    }

    private static Task<HttpResponseMessage> Understand(HttpClient client) =>
        client.PostAsJsonAsync("/api/v1/ai/understand", new { text = "Yarın Ankara'ya 24 ton demir göndereceğim", city = "İstanbul" });

    private async Task<List<AiUsage>> Usage()
    {
        using var scope = _factory.Services.CreateScope();
        return await scope.ServiceProvider.GetRequiredService<AppDbContext>().Set<AiUsage>().AsNoTracking().ToListAsync();
    }

    [Fact]
    public async Task DisabledMissingKeyPhonePolicyAndRevokedSessionsNeverCallProvider()
    {
        Assert.False(new AiOptions().Enabled);
        using var unauthenticated = _factory.CreateClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await unauthenticated.GetAsync("/api/v1/ai/options")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await Understand(unauthenticated)).StatusCode);
        await using var disabled = Config(("AI:Enabled", "false"));
        var (disabledClient, _) = await Login(disabled);
        using (disabledClient)
        {
            var options = (await disabledClient.GetFromJsonAsync<JsonObject>("/api/v1/ai/options"))!;
            Assert.False(options["enabled"]!.GetValue<bool>());
            Assert.Equal("CONFIG", (await (await Understand(disabledClient)).Content.ReadFromJsonAsync<JsonObject>())!["error"]!.GetValue<string>());
        }
        await using var missingKey = Config(("AI:ApiKey", ""));
        var (missingClient, _) = await Login(missingKey);
        using (missingClient) Assert.Equal(HttpStatusCode.ServiceUnavailable, (await Understand(missingClient)).StatusCode);
        await using var requirePhone = Config(("Auth:RequirePhoneVerification", "true"));
        var (unverified, unverifiedId) = await Login(requirePhone);
        using (unverified)
        {
            var blocked = await Understand(unverified);
            Assert.Equal(HttpStatusCode.Forbidden, blocked.StatusCode);
            Assert.Equal("PHONE_REQUIRED", (await blocked.Content.ReadFromJsonAsync<JsonObject>())!["error"]!.GetValue<string>());
            using (var scope = requirePhone.Services.CreateScope())
                await scope.ServiceProvider.GetRequiredService<AppDbContext>().Sessions.Where(x => x.UserId == unverifiedId).ExecuteUpdateAsync(s => s.SetProperty(x => x.RevokedAt, DateTimeOffset.UtcNow));
            Assert.Equal(HttpStatusCode.Unauthorized, (await unverified.GetAsync("/api/v1/ai/options")).StatusCode);
        }
        Assert.Empty(await Usage()); Assert.Equal(0, _provider.Calls);
    }

    [Fact]
    public async Task SuccessfulProviderResponseIsOnlyATemplateAndInputErrorsSpendNoBudget()
    {
        var (client, userId) = await Login();
        using (client)
        {
            var options = await client.GetAsync("/api/v1/ai/options"); options.EnsureSuccessStatusCode();
            Assert.True((await options.Content.ReadFromJsonAsync<JsonObject>())!["enabled"]!.GetValue<bool>());
            Assert.True(options.Headers.CacheControl!.NoStore);
            Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/v1/ai/understand", new { text = new string('A', 401), city = "Ankara" })).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/v1/ai/understand", new { text = 123 })).StatusCode);
            Assert.Equal(0, _provider.Calls); Assert.Empty(await Usage());
            var response = await Understand(client); response.EnsureSuccessStatusCode();
            Assert.True(response.Headers.CacheControl!.NoStore);
            var result = (await response.Content.ReadFromJsonAsync<JsonObject>())!;
            Assert.Equal("gemini", result["source"]!.GetValue<string>());
            Assert.Equal("ilan_ver", result["result"]!["intent"]!.GetValue<string>());
            Assert.Equal(15, result["result"]!.AsObject().Count);
            var usage = Assert.Single(await Usage()); Assert.Equal(userId, usage.UserId);
            Assert.True(usage.LeaseUntil <= _clock.GetUtcNow());
            using var scope = _factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            Assert.Equal(40, (await db.Users.FindAsync(userId))!.Credits);
            Assert.Null((await db.Users.FindAsync(userId))!.PremiumUntil);
            Assert.False(await db.Listings.AnyAsync()); Assert.False(await db.Requests.AnyAsync()); Assert.False(await db.Deals.AnyAsync());
            Assert.False(await db.CreditEntries.AnyAsync());
        }
    }

    [Fact]
    public async Task FreePremiumAndUtcDayQuotasAreAtomicAcrossConcurrentRequests()
    {
        await using var configured = Config(("AI:DailyLimit", "2"), ("AI:PremiumDailyLimit", "3"), ("AI:MaxConcurrency", "10"));
        var (free, freeId) = await Login(configured); var (premium, premiumId) = await Login(configured, premium: true);
        using (free) using (premium)
        {
            var freeResults = await Task.WhenAll(Enumerable.Range(0, 5).Select(_ => Understand(free)));
            Assert.Equal(2, freeResults.Count(x => x.IsSuccessStatusCode));
            Assert.Equal(3, freeResults.Count(x => x.StatusCode == HttpStatusCode.TooManyRequests));
            var premiumResults = await Task.WhenAll(Enumerable.Range(0, 5).Select(_ => Understand(premium)));
            Assert.Equal(3, premiumResults.Count(x => x.IsSuccessStatusCode));
            Assert.Equal(2, premiumResults.Count(x => x.StatusCode == HttpStatusCode.TooManyRequests));
            var usage = await Usage(); Assert.Equal(2, usage.Count(x => x.UserId == freeId)); Assert.Equal(3, usage.Count(x => x.UserId == premiumId));
            Assert.Equal(5, _provider.Calls);
            _clock.Advance(TimeSpan.FromDays(1));
            (await Understand(free)).EnsureSuccessStatusCode(); Assert.Equal(6, _provider.Calls);
        }
    }

    [Fact]
    public async Task GlobalBudgetSurvivesAccountDeletionAndCannotBeResetByAnotherAccount()
    {
        await using var configured = Config(("AI:GlobalDailyRequestLimit", "2"));
        var (first, _) = await Login(configured); var (second, _) = await Login(configured); var (third, _) = await Login(configured);
        using (first) using (second) using (third)
        {
            (await Understand(first)).EnsureSuccessStatusCode(); (await Understand(second)).EnsureSuccessStatusCode();
            (await first.DeleteAsync("/api/v1/account")).EnsureSuccessStatusCode();
            var usage = await Usage(); Assert.Equal(2, usage.Count); Assert.Single(usage, x => x.UserId is null);
            var blocked = await Understand(third);
            Assert.Equal(HttpStatusCode.TooManyRequests, blocked.StatusCode);
            Assert.Equal("RATE_LIMIT", (await blocked.Content.ReadFromJsonAsync<JsonObject>())!["error"]!.GetValue<string>());
            Assert.Equal(2, _provider.Calls); Assert.Equal(2, (await Usage()).Count);
        }
    }

    [Fact]
    public async Task DatabaseLeasesBoundWorkersAndExpiredCrashLeaseRecovers()
    {
        await using var configured = Config(("AI:MaxConcurrency", "1"));
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var proceed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        _reply = async (_, ct) => { entered.TrySetResult(); await proceed.Task.WaitAsync(ct); return AiTests.ProviderResponse(AiTests.ValidResult); };
        var (first, firstId) = await Login(configured); var (second, _) = await Login(configured);
        using (first) using (second)
        {
            var ongoing = Understand(first); await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
            try
            {
                Assert.Equal(HttpStatusCode.TooManyRequests, (await Understand(second)).StatusCode);
                Assert.Single(await Usage()); Assert.Equal(1, _provider.Calls);
            }
            finally { proceed.TrySetResult(); }
            (await ongoing).EnsureSuccessStatusCode();
            (await Understand(second)).EnsureSuccessStatusCode(); Assert.Equal(2, _provider.Calls);
            using (var scope = _factory.Services.CreateScope())
            {
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                db.Set<AiUsage>().Add(new() { UserId = firstId, CreatedAt = _clock.GetUtcNow(), LeaseUntil = _clock.GetUtcNow().AddSeconds(25) });
                await db.SaveChangesAsync();
            }
            Assert.Equal(HttpStatusCode.TooManyRequests, (await Understand(second)).StatusCode);
            _clock.Advance(TimeSpan.FromSeconds(26));
            (await Understand(second)).EnsureSuccessStatusCode(); Assert.Equal(3, _provider.Calls);
        }
    }

    [Fact]
    public async Task FailedOrCancelledProviderCallsStillSpendBudgetButReleaseConcurrency()
    {
        await using var configured = Config(("AI:DailyLimit", "2"), ("AI:MaxConcurrency", "1"), ("AI:TimeoutSeconds", "1"));
        _reply = async (_, ct) => { await Task.Delay(Timeout.InfiniteTimeSpan, ct); return AiTests.ProviderResponse(AiTests.ValidResult); };
        var (client, _) = await Login(configured);
        using (client)
        {
            Assert.Equal(HttpStatusCode.ServiceUnavailable, (await Understand(client)).StatusCode);
            Assert.True(Assert.Single(await Usage()).LeaseUntil <= _clock.GetUtcNow());
            _reply = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("invalid provider json") });
            Assert.Equal(HttpStatusCode.BadGateway, (await Understand(client)).StatusCode);
            Assert.All(await Usage(), u => Assert.True(u.LeaseUntil <= _clock.GetUtcNow()));
            Assert.Equal(HttpStatusCode.TooManyRequests, (await Understand(client)).StatusCode);
            Assert.Equal(2, _provider.Calls); Assert.Equal(2, (await Usage()).Count);
            using var canceled = new CancellationTokenSource(); canceled.Cancel();
            using var scope = _factory.Services.CreateScope();
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => scope.ServiceProvider.GetRequiredService<AiQuota>().Reserve(Guid.NewGuid(), canceled.Token));
            Assert.Equal(2, (await Usage()).Count);
        }
    }
}

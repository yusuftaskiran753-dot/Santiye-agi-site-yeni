using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Npgsql;
using SantiyeAgi.Api.Auth;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Infrastructure;
using SantiyeAgi.Api.Services.Push;

namespace SantiyeAgi.Api.Tests;

[Collection("Postgres")]
public sealed class SmsPushIntegrationTests : IAsyncLifetime
{
    private readonly TestPushSender _push = new();
    private readonly TestSmsSender _sms = new();
    private WebApplicationFactory<Program> _factory = null!;
    private string _database = "", _admin = "";
    private string? _previousConnection, _previousKey, _previousProtection;
    private string _keysPath = "";

    public async Task InitializeAsync()
    {
        _admin = Environment.GetEnvironmentVariable("SANTIYE_TEST_POSTGRES") ?? throw new InvalidOperationException("Local test PostgreSQL connection is required.");
        var connection = new NpgsqlConnectionStringBuilder(_admin);
        if (connection.Host is not "localhost" and not "127.0.0.1") throw new InvalidOperationException("Tests only run on localhost.");
        _database = "santiye_test_" + Guid.NewGuid().ToString("N");
        await using (var db = new NpgsqlConnection(_admin))
        {
            await db.OpenAsync();
            await using var command = new NpgsqlCommand($"CREATE DATABASE \"{_database}\"", db); await command.ExecuteNonQueryAsync();
        }
        connection.Database = _database;
        _previousConnection = Environment.GetEnvironmentVariable("ConnectionStrings__Postgres");
        _previousKey = Environment.GetEnvironmentVariable("Auth__SigningKey");
        _previousProtection = Environment.GetEnvironmentVariable("DataProtection__KeysPath");
        _keysPath = Path.Combine(Path.GetTempPath(), "santiye_test_keys_" + Guid.NewGuid().ToString("N"));
        Environment.SetEnvironmentVariable("ConnectionStrings__Postgres", connection.ConnectionString);
        Environment.SetEnvironmentVariable("Auth__SigningKey", new string('Q', 64));
        Environment.SetEnvironmentVariable("DataProtection__KeysPath", _keysPath);
        _factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder => builder.UseEnvironment("Development").ConfigureServices(services =>
        {
            services.RemoveAll<IPushSender>(); services.AddSingleton<IPushSender>(_push);
            services.RemoveAll<ISmsOtpSender>(); services.AddSingleton<ISmsOtpSender>(_sms);
            var worker = services.FirstOrDefault(x => x.ServiceType == typeof(IHostedService) && x.ImplementationType == typeof(PushDispatchWorker));
            if (worker is not null) services.Remove(worker);
        }));
        using var scope = _factory.Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.MigrateAsync();
    }

    public async Task DisposeAsync()
    {
        if (_factory is not null) await _factory.DisposeAsync();
        Environment.SetEnvironmentVariable("ConnectionStrings__Postgres", _previousConnection);
        Environment.SetEnvironmentVariable("Auth__SigningKey", _previousKey);
        Environment.SetEnvironmentVariable("DataProtection__KeysPath", _previousProtection);
        var temporaryRoot = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar);
        if (Directory.Exists(_keysPath) && Path.GetDirectoryName(Path.GetFullPath(_keysPath)) == temporaryRoot &&
            Path.GetFileName(_keysPath).StartsWith("santiye_test_keys_", StringComparison.Ordinal)) Directory.Delete(_keysPath, recursive: true);
        NpgsqlConnection.ClearAllPools();
        if (_database.StartsWith("santiye_test_", StringComparison.Ordinal) && _database.Length == 45)
        {
            await using var connection = new NpgsqlConnection(_admin); await connection.OpenAsync();
            await using var command = new NpgsqlCommand($"DROP DATABASE \"{_database}\" WITH (FORCE)", connection); await command.ExecuteNonQueryAsync();
        }
    }

    private async Task<(HttpClient Client, Guid UserId)> Login(string phone)
    {
        var client = _factory.CreateClient();
        var request = await client.PostAsJsonAsync("/api/v1/auth/phone/request", new { phone }); request.EnsureSuccessStatusCode();
        var code = (await request.Content.ReadFromJsonAsync<JsonObject>())!["development_code"]!.GetValue<string>();
        var verify = await client.PostAsJsonAsync("/api/v1/auth/phone/verify", new { phone, code }); verify.EnsureSuccessStatusCode();
        var session = (await verify.Content.ReadFromJsonAsync<JsonObject>())!;
        client.DefaultRequestHeaders.Authorization = new("Bearer", session["access_token"]!.GetValue<string>());
        return (client, Guid.Parse(session["user_id"]!.GetValue<string>()));
    }

    private async Task<Guid> Notify(Guid user)
    {
        using var scope = _factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var notification = new Notification { UserId = user, Title = "Test", Body = "Test", RefType = "deal", RefId = Guid.NewGuid() };
        db.Notifications.Add(notification); await db.SaveChangesAsync();
        Assert.True(await db.Set<PushOutbox>().AnyAsync(x => x.NotificationId == notification.Id));
        return notification.Id;
    }

    private async Task<int> Dispatch()
    {
        using var scope = _factory.Services.CreateScope();
        return await scope.ServiceProvider.GetRequiredService<PushDispatcher>().RunBatch();
    }

    [Fact]
    public async Task DeviceOwnershipAccountSwitchAndLogoutDoNotLeakRecipients()
    {
        var (first, firstId) = await Login("+905551900001"); var (second, secondId) = await Login("+905551900002");
        using (first) using (second)
        {
            var install = Guid.NewGuid(); const string token = "first-device-test-token-long-enough";
            (await first.PutAsJsonAsync($"/api/v1/push/devices/{install}", new { token, platform = "android" })).EnsureSuccessStatusCode();
            (await second.DeleteAsync($"/api/v1/push/devices/{install}")).EnsureSuccessStatusCode();
            using (var scope = _factory.Services.CreateScope())
                Assert.True(await scope.ServiceProvider.GetRequiredService<AppDbContext>().Set<PushDevice>().AnyAsync(x => x.UserId == firstId));
            // Possessing the current FCM token transfers its recipient association
            // when the same physical installation switches account.
            (await second.PutAsJsonAsync($"/api/v1/push/devices/{install}", new { token, platform = "android" })).EnsureSuccessStatusCode();
            await Notify(firstId); await Notify(secondId); Assert.Equal(1, await Dispatch());
            Assert.Single(_push.Sent); Assert.Equal(secondId, _push.Sent[0].User);
            (await second.PostAsync("/api/v1/auth/logout", null)).EnsureSuccessStatusCode();
            using var finalScope = _factory.Services.CreateScope();
            Assert.False(await finalScope.ServiceProvider.GetRequiredService<AppDbContext>().Set<PushDevice>().AnyAsync(x => x.UserId == secondId));
        }
    }

    [Fact]
    public async Task NotificationOutboxRetriesAndRestartDoesNotResendCompletedJobs()
    {
        var (client, user) = await Login("+905551900011"); using (client)
        {
            (await client.PutAsJsonAsync($"/api/v1/push/devices/{Guid.NewGuid()}", new { token = "retry-device-token-long-enough", platform = "ios" })).EnsureSuccessStatusCode();
            var id = await Notify(user);
            _push.Next = new(PushResultKind.Retry, "UNAVAILABLE");
            Assert.Equal(0, await Dispatch());
            using (var scope = _factory.Services.CreateScope())
            {
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var job = await db.Set<PushDelivery>().SingleAsync(x => x.NotificationId == id);
                Assert.Equal(1, job.Attempts); Assert.Null(job.CompletedAt); Assert.True(job.NextAttemptAt > DateTimeOffset.UtcNow);
                job.NextAttemptAt = DateTimeOffset.UtcNow.AddMinutes(-1); await db.SaveChangesAsync();
            }
            _push.Next = new(PushResultKind.Success, "SENT");
            Assert.Equal(1, await Dispatch()); Assert.Equal(0, await Dispatch());
            using var finalScope = _factory.Services.CreateScope();
            var completed = await finalScope.ServiceProvider.GetRequiredService<AppDbContext>().Set<PushDelivery>().SingleAsync(x => x.NotificationId == id);
            Assert.Equal(2, completed.Attempts); Assert.NotNull(completed.CompletedAt);
        }
    }

    [Fact]
    public async Task UnregisteredDeviceIsRemovedAndAccountDeletionCascadesPushData()
    {
        var (client, user) = await Login("+905551900021"); using (client)
        {
            var install = Guid.NewGuid();
            (await client.PutAsJsonAsync($"/api/v1/push/devices/{install}", new { token = "invalid-device-token-long-enough", platform = "android" })).EnsureSuccessStatusCode();
            await Notify(user); _push.Next = new(PushResultKind.InvalidToken, "UNREGISTERED");
            Assert.Equal(0, await Dispatch());
            using (var scope = _factory.Services.CreateScope())
            {
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                Assert.Empty(await db.Set<PushDevice>().ToListAsync()); Assert.Empty(await db.Set<PushDelivery>().ToListAsync());
            }
            (await client.PutAsJsonAsync($"/api/v1/push/devices/{install}", new { token = "replacement-device-token-long-enough", platform = "android" })).EnsureSuccessStatusCode();
            await Notify(user);
            (await client.DeleteAsync("/api/v1/account")).EnsureSuccessStatusCode();
            using var finalScope = _factory.Services.CreateScope(); var finalDb = finalScope.ServiceProvider.GetRequiredService<AppDbContext>();
            Assert.Empty(await finalDb.Set<PushDevice>().ToListAsync()); Assert.Empty(await finalDb.Set<PushOutbox>().ToListAsync());
        }
    }

    [Fact]
    public async Task DevelopmentChallengeCannotBeReusedAfterSwitchingToProduction()
    {
        const string phone = "+905551900041";
        using var development = _factory.CreateClient();
        var request = await development.PostAsJsonAsync("/api/v1/auth/phone/request", new { phone }); request.EnsureSuccessStatusCode();
        var code = (await request.Content.ReadFromJsonAsync<JsonObject>())!["development_code"]!.GetValue<string>();
        await using var productionFactory = _factory.WithWebHostBuilder(builder => builder.UseEnvironment("Production"));
        using var production = productionFactory.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new Uri("https://localhost") });
        var verify = await production.PostAsJsonAsync("/api/v1/auth/phone/verify", new { phone, code });
        Assert.Equal(HttpStatusCode.BadRequest, verify.StatusCode);
        Assert.Equal("BAD_INPUT", (await verify.Content.ReadFromJsonAsync<JsonObject>())!["error"]!.GetValue<string>());
    }

    [Fact]
    public async Task RealProviderModeHidesCodeAndPersistsSharedSendBudgetAcrossPhones()
    {
        _sms.Simulation = false;
        _factory.Services.GetRequiredService<IConfiguration>()["Sms:DailyBudget"] = "2";
        using var client = _factory.CreateClient();
        foreach (var phone in new[] { "+905551900051", "+905551900052" })
        {
            var request = await client.PostAsJsonAsync("/api/v1/auth/phone/request", new { phone }); request.EnsureSuccessStatusCode();
            Assert.Null((await request.Content.ReadFromJsonAsync<JsonObject>())!["development_code"]);
        }
        var third = await client.PostAsJsonAsync("/api/v1/auth/phone/request", new { phone = "+905551900053" });
        Assert.Equal(HttpStatusCode.TooManyRequests, third.StatusCode);
        using var scope = _factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        Assert.Equal(2, (await db.Set<PhoneOtpQuota>().SingleAsync(x => x.Phone == "__daily_budget__")).DayCount);
        Assert.False(await db.PhoneChallenges.AnyAsync(x => x.Phone == "+905551900053"));
    }

    [Fact]
    public async Task StagedSmsVerifiesExistingReviewPhoneWithoutBlockingPasswordAccess()
    {
        const string phone = "+905551900061";
        const string password = "Local-review-staging-password-729!";
        var userId = Guid.NewGuid();
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.Users.Add(new User { Id = userId, Phone = phone, Name = "Review staging fixture", ProfileComplete = true });
            await db.SaveChangesAsync();
        }
        _sms.Simulation = false;
        await using var production = _factory.WithWebHostBuilder(builder => builder.UseEnvironment("Production")
            .ConfigureAppConfiguration((_, configuration) => configuration.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Auth:RequirePhoneVerification"] = "false",
                ["Sms:Enabled"] = "false",
                ["Auth:AccountLogin:Enabled"] = "true",
                ["Auth:AccountLogin:Accounts:0:Username"] = "review.fixture",
                ["Auth:AccountLogin:Accounts:0:UserId"] = userId.ToString(),
                ["Auth:AccountLogin:Accounts:0:PasswordHash"] = AccountPassword.Hash(password)
            })));
        using var client = production.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new Uri("https://localhost") });
        var config = production.Services.GetRequiredService<IConfiguration>();
        var options = (await client.GetFromJsonAsync<JsonObject>("/api/v1/auth/options"))!;
        Assert.False(options["phone_verification_available"]!.GetValue<bool>());
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await client.PostAsJsonAsync("/api/v1/auth/phone/request", new { phone })).StatusCode);
        Assert.Empty(_sms.Sent);

        config["Sms:Enabled"] = "true";
        options = (await client.GetFromJsonAsync<JsonObject>("/api/v1/auth/options"))!;
        Assert.False(options["phone_verification_required"]!.GetValue<bool>());
        Assert.True(options["phone_verification_available"]!.GetValue<bool>());
        var readiness = await SmsReviewReadiness.Check(config, default);
        Assert.True(readiness.ReadOnly);
        Assert.False(readiness.ReadyForRequiredSms);
        Assert.Equal(1, readiness.MissingOrInvalidAccountCount);
        (await client.PostAsJsonAsync("/api/v1/auth/password/login", new { username = "review.fixture", password })).EnsureSuccessStatusCode();
        var requested = await client.PostAsJsonAsync("/api/v1/auth/phone/request", new { phone });
        requested.EnsureSuccessStatusCode();
        Assert.Null((await requested.Content.ReadFromJsonAsync<JsonObject>())!["development_code"]);
        Assert.Single(_sms.Sent);
        using (var scope = production.Services.CreateScope())
            Assert.False((await scope.ServiceProvider.GetRequiredService<AppDbContext>().Users.FindAsync(userId))!.PhoneVerified);

        var verified = await client.PostAsJsonAsync("/api/v1/auth/phone/verify", new { phone, code = _sms.Sent[0].Code });
        verified.EnsureSuccessStatusCode();
        var session = (await verified.Content.ReadFromJsonAsync<JsonObject>())!;
        Assert.Equal(userId.ToString(), session["user_id"]!.GetValue<string>());
        Assert.True(session["phone_verified"]!.GetValue<bool>());
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/v1/auth/phone/verify", new { phone, code = _sms.Sent[0].Code })).StatusCode);
        readiness = await SmsReviewReadiness.Check(config, default);
        Assert.True(readiness.ReadyForRequiredSms);
        Assert.Equal(1, readiness.VerifiedAccountCount);

        config["Auth:RequirePhoneVerification"] = "true";
        (await client.PostAsJsonAsync("/api/v1/auth/password/login", new { username = "review.fixture", password })).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PostAsJsonAsync("/api/v1/auth/anonymous", new { })).StatusCode);
        using var finalScope = production.Services.CreateScope();
        var finalDb = finalScope.ServiceProvider.GetRequiredService<AppDbContext>();
        Assert.Single(await finalDb.Users.ToListAsync());
        Assert.Equal("Review staging fixture", (await finalDb.Users.FindAsync(userId))!.Name);
    }

    [Fact]
    public async Task FailedSmsSubmissionInvalidatesPreviousCodeAndStillConsumesQuota()
    {
        const string phone = "+905551900031";
        using var client = _factory.CreateClient();
        var first = await client.PostAsJsonAsync("/api/v1/auth/phone/request", new { phone }); first.EnsureSuccessStatusCode();
        var code = (await first.Content.ReadFromJsonAsync<JsonObject>())!["development_code"]!.GetValue<string>();
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var quota = await db.Set<PhoneOtpQuota>().SingleAsync(x => x.Phone == phone); quota.LastAttemptAt = DateTimeOffset.UtcNow.AddMinutes(-2); await db.SaveChangesAsync();
        }
        _sms.Fail = true;
        var second = await client.PostAsJsonAsync("/api/v1/auth/phone/request", new { phone }); Assert.Equal(HttpStatusCode.ServiceUnavailable, second.StatusCode);
        Assert.Null((await second.Content.ReadFromJsonAsync<JsonObject>())!["development_code"]);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/v1/auth/phone/verify", new { phone, code })).StatusCode);
        using var finalScope = _factory.Services.CreateScope(); var finalDb = finalScope.ServiceProvider.GetRequiredService<AppDbContext>();
        Assert.Equal(2, (await finalDb.Set<PhoneOtpQuota>().SingleAsync(x => x.Phone == phone)).DayCount);
        Assert.Equal(5, (await finalDb.PhoneChallenges.SingleAsync(x => x.Phone == phone)).Attempts);
    }

    private sealed class TestSmsSender : ISmsOtpSender
    {
        public bool Fail { get; set; }
        public bool Simulation { get; set; } = true;
        public List<(string Phone, string Code)> Sent { get; } = [];
        public bool DevelopmentSimulation => Simulation;
        public void EnsureConfigured() { }
        public Task Send(string phone, string code, CancellationToken cancellationToken)
        {
            if (Fail) throw new ApiError("SMS_UNAVAILABLE", 503);
            Sent.Add((phone, code));
            return Task.CompletedTask;
        }
    }
    private sealed class TestPushSender : IPushSender
    {
        public bool Configured => true;
        public PushSendResult Next { get; set; } = new(PushResultKind.Success, "SENT");
        public List<(string Token, Guid User)> Sent { get; } = [];
        public Task<PushSendResult> Send(PushDevice device, Notification notification, CancellationToken cancellationToken)
        { Sent.Add((device.Token, notification.UserId)); return Task.FromResult(Next); }
    }
}

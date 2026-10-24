using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using SantiyeAgi.Api.Auth;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Infrastructure;
using SantiyeAgi.Api.LiveLocation;
using SantiyeAgi.Api.Services.Push;

namespace SantiyeAgi.Api.Tests;

public sealed class LiveLocationValidationTests
{
    [Theory]
    [InlineData(double.NaN, 29, null, null, null, 60)]
    [InlineData(91, 29, null, null, null, 60)]
    [InlineData(41, double.PositiveInfinity, null, null, null, 60)]
    [InlineData(41, -181, null, null, null, 60)]
    [InlineData(41, 29, -1d, null, null, 60)]
    [InlineData(41, 29, null, 360d, null, 60)]
    [InlineData(41, 29, null, null, -1d, 60)]
    [InlineData(41, 29, null, null, 151d, 60)]
    [InlineData(41, 29, null, null, null, 61)]
    public void InvalidFixOrDurationIsRejected(double lat, double lng, double? accuracy, double? heading, double? speed, int minutes)
    {
        var now = DateTimeOffset.UtcNow;
        var error = Assert.Throws<ApiError>(() => LiveLocationService.Validate(new(lat, lng, now, accuracy, heading, speed, minutes), now));
        Assert.Equal("BAD_INPUT", error.Code);
    }

    [Fact]
    public void StaleFutureAndAmbiguousStartAreRejected()
    {
        var now = DateTimeOffset.UtcNow;
        Assert.Throws<ApiError>(() => LiveLocationService.Validate(new(41, 29, now.AddMinutes(-6), Minutes: 60), now));
        Assert.Throws<ApiError>(() => LiveLocationService.Validate(new(41, 29, now.AddMinutes(3), Minutes: 60), now));
        Assert.Throws<ApiError>(() => LiveLocationService.Validate(new(41, 29, now, Minutes: 60, UntilDelivered: true), now));
        LiveLocationService.Validate(new(41, 29, now, Accuracy: 4, Heading: 0, Speed: 10, UntilDelivered: true), now);
    }
}

// A fresh, explicitly localhost-only santiye_test_* database is owned and removed
// by each fixture. Production/external database connections are never accepted.
[Collection("Postgres")]
public sealed class LiveLocationIntegrationTests : IAsyncLifetime
{
    private WebApplicationFactory<Program> _factory = null!;
    private string _admin = "";
    private string _database = "";
    private string? _previousConnection;
    private string? _previousKey;
    private string? _previousProtection;
    private readonly TestClock _clock = new();
    private HttpClient _customer = null!;
    private HttpClient _provider = null!;
    private HttpClient _outsider = null!;
    private Guid _customerId;
    private Guid _providerId;
    private Guid _dealId;

    private sealed class TestClock : TimeProvider
    {
        private DateTimeOffset _now = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => _now;
        public void Advance(TimeSpan duration) => _now += duration;
    }

    public async Task InitializeAsync()
    {
        _admin = Environment.GetEnvironmentVariable("SANTIYE_TEST_POSTGRES") ?? throw new InvalidOperationException("A dedicated localhost PostgreSQL test connection is required.");
        var connection = new NpgsqlConnectionStringBuilder(_admin);
        if (connection.Host is not "localhost" and not "127.0.0.1") throw new InvalidOperationException("Integration tests only run on localhost.");
        _database = "santiye_test_" + Guid.NewGuid().ToString("N");
        await using (var admin = new NpgsqlConnection(_admin))
        {
            await admin.OpenAsync();
            await using var command = new NpgsqlCommand($"CREATE DATABASE \"{_database}\"", admin);
            await command.ExecuteNonQueryAsync();
        }
        connection.Database = _database;
        // Program validates connection/signing configuration before the factory's
        // application configuration callbacks run, matching the existing test suites.
        _previousConnection = Environment.GetEnvironmentVariable("ConnectionStrings__Postgres");
        _previousKey = Environment.GetEnvironmentVariable("Auth__SigningKey");
        _previousProtection = Environment.GetEnvironmentVariable("DataProtection__KeysPath");
        Environment.SetEnvironmentVariable("ConnectionStrings__Postgres", connection.ConnectionString);
        Environment.SetEnvironmentVariable("Auth__SigningKey", new string('L', 64));
        Environment.SetEnvironmentVariable("DataProtection__KeysPath", Path.Combine(AppContext.BaseDirectory, "development-keys"));
        var config = new Dictionary<string, string?>
        {
            ["ConnectionStrings:Postgres"] = connection.ConnectionString,
            ["Auth:SigningKey"] = new string('L', 64),
            ["Auth:RequirePhoneVerification"] = "true",
            ["DataProtection:KeysPath"] = Path.Combine(AppContext.BaseDirectory, "development-keys"),
            ["AI:Enabled"] = "false"
        };
        _factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder => builder.UseEnvironment("Development")
            .ConfigureAppConfiguration((_, settings) => settings.AddInMemoryCollection(config))
            .ConfigureServices(services => { services.RemoveAll<TimeProvider>(); services.AddSingleton<TimeProvider>(_clock); }));
        using (var scope = _factory.Services.CreateScope())
            await scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.MigrateAsync();
        (_customer, _customerId) = await Client("Customer");
        (_provider, _providerId) = await Client("Provider");
        (_outsider, _) = await Client("Outsider");
        _dealId = await SeedDeal();
    }

    public async Task DisposeAsync()
    {
        _customer?.Dispose(); _provider?.Dispose(); _outsider?.Dispose();
        if (_factory is not null) await _factory.DisposeAsync();
        Environment.SetEnvironmentVariable("ConnectionStrings__Postgres", _previousConnection);
        Environment.SetEnvironmentVariable("Auth__SigningKey", _previousKey);
        Environment.SetEnvironmentVariable("DataProtection__KeysPath", _previousProtection);
        NpgsqlConnection.ClearAllPools();
        if (_database.StartsWith("santiye_test_", StringComparison.Ordinal) && _database.Length == 45)
        {
            await using var admin = new NpgsqlConnection(_admin);
            await admin.OpenAsync();
            await using var command = new NpgsqlCommand($"DROP DATABASE \"{_database}\" WITH (FORCE)", admin);
            await command.ExecuteNonQueryAsync();
        }
    }

    private async Task<(HttpClient, Guid)> Client(string name)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var user = new User { Name = name, ProfileComplete = true, PhoneVerified = true };
        var refresh = TokenService.NewRefresh();
        var session = new Session { UserId = user.Id, RefreshHash = TokenService.Hash(refresh), ExpiresAt = DateTimeOffset.UtcNow.AddDays(1) };
        db.Users.Add(user); db.Sessions.Add(session); await db.SaveChangesAsync();
        var token = scope.ServiceProvider.GetRequiredService<TokenService>().Issue(user, session, refresh);
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new("Bearer", token["access_token"]!.GetValue<string>());
        return (client, user.Id);
    }

    private async Task<Guid> SeedDeal(string status = "active", bool solo = false)
    {
        using var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var deal = new Deal { CustomerId = _customerId, ProviderId = solo ? null : _providerId, CreatedBy = _customerId,
            Code = Guid.NewGuid().ToString("N")[..8].ToUpperInvariant(), Status = status,
            Data = new JsonObject { ["title"] = "Local location test", ["kind"] = "yuk", ["milestones"] = new JsonArray(), ["log"] = new JsonArray() }.ToJsonString() };
        db.Deals.Add(deal); await db.SaveChangesAsync(); return deal.Id;
    }

    private object Fix(int? minutes = null, bool until = false, double lat = 41, DateTimeOffset? at = null, Guid? generation = null) =>
        new { lat, lng = 29, at = at ?? _clock.GetUtcNow(), accuracy = 5, heading = 90, speed = 10, minutes, until_delivered = until, generation };
    private async Task<Guid> Prepare(HttpClient client, Guid? deal = null)
    {
        var response = await client.PostAsync($"/api/v1/deals/{deal ?? _dealId}/location/prepare", null);
        response.EnsureSuccessStatusCode();
        return Guid.Parse((await response.Content.ReadFromJsonAsync<JsonObject>())!["generation"]!.GetValue<string>());
    }
    private async Task<HttpResponseMessage> Put(HttpClient client, int? minutes = null, bool until = false, double lat = 41, Guid? deal = null, DateTimeOffset? at = null)
    {
        Guid? generation = null;
        if (minutes is not null || until)
        {
            var prepare = await client.PostAsync($"/api/v1/deals/{deal ?? _dealId}/location/prepare", null);
            if (!prepare.IsSuccessStatusCode) return prepare;
            generation = Guid.Parse((await prepare.Content.ReadFromJsonAsync<JsonObject>())!["generation"]!.GetValue<string>());
            prepare.Dispose();
        }
        return await client.PutAsJsonAsync($"/api/v1/deals/{deal ?? _dealId}/location", Fix(minutes, until, lat, at, generation));
    }
    private async Task<JsonArray> Locations(HttpClient client, Guid? deal = null) =>
        (await client.GetFromJsonAsync<JsonArray>($"/api/v1/deals/{deal ?? _dealId}/locations"))!;
    private async Task<LiveLocationShare[]> Shares()
    {
        using var scope = _factory.Services.CreateScope();
        return await scope.ServiceProvider.GetRequiredService<AppDbContext>().Set<LiveLocationShare>().AsNoTracking().Where(x => x.DealId == _dealId).ToArrayAsync();
    }
    private async Task<int> Notifications()
    {
        using var scope = _factory.Services.CreateScope();
        return await scope.ServiceProvider.GetRequiredService<AppDbContext>().Notifications.CountAsync(x => x.RefId == _dealId && x.Title == "Canlı konum paylaşılıyor");
    }
    private async Task Action(HttpClient client, string action)
    {
        var response = await client.PostAsJsonAsync($"/api/v1/deals/{_dealId}/actions", new { action, note = "" });
        response.EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task RealParticipantsOnlyAndServerDerivesIdentity()
    {
        using var anonymous = _factory.CreateClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await Put(anonymous, 60)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await Put(_outsider, 60)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await _outsider.GetAsync($"/api/v1/deals/{_dealId}/locations")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await _outsider.DeleteAsync($"/api/v1/deals/{_dealId}/location")).StatusCode);
        var measuredAt = _clock.GetUtcNow().AddSeconds(-20);
        var generation = await Prepare(_customer);
        var response = await _customer.PutAsJsonAsync($"/api/v1/deals/{_dealId}/location", new
        {
            lat = 41, lng = 29, at = measuredAt, minutes = 60, generation, user_id = _providerId
        });
        response.EnsureSuccessStatusCode();
        var location = Assert.Single(await Locations(_provider));
        Assert.Equal(_customerId.ToString(), location!["user_id"]!.GetValue<string>());
        // Uploading a cached fix must not make its age appear fresher.
        var shownAt = DateTimeOffset.Parse(location["updated_at"]!.GetValue<string>(), System.Globalization.CultureInfo.InvariantCulture);
        Assert.True((shownAt - measuredAt).Duration() < TimeSpan.FromMilliseconds(1));
        Assert.Single(await Shares());
    }

    [Fact]
    public async Task PendingAndSoloDealsRejectSharingAndRequireProfileAndPhonePolicy()
    {
        var pending = await SeedDeal("pending"); var solo = await SeedDeal(solo: true);
        Assert.Equal(HttpStatusCode.BadRequest, (await Put(_customer, 60, deal: pending)).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await Put(_customer, 60, deal: solo)).StatusCode);
        using var scope = _factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var user = await db.Users.FindAsync(_customerId); user!.PhoneVerified = false; await db.SaveChangesAsync();
        Assert.Equal(HttpStatusCode.Forbidden, (await Put(_customer, 60)).StatusCode);
        user.PhoneVerified = true; user.ProfileComplete = false; await db.SaveChangesAsync();
        Assert.Equal(HttpStatusCode.BadRequest, (await Put(_customer, 60)).StatusCode);
    }

    [Fact]
    public async Task UpdatesNeverRenewAndOldFixesAndBurstsCannotReplaceTheLatest()
    {
        (await Put(_customer, 60)).EnsureSuccessStatusCode();
        var started = Assert.Single(await Shares()); var expiry = started.ExpiresAt;
        (await Put(_provider, 480)).EnsureSuccessStatusCode();
        Assert.Equal(2, (await Locations(_customer)).Count);
        _clock.Advance(TimeSpan.FromSeconds(4));
        (await Put(_customer, 60, lat: 42)).EnsureSuccessStatusCode();
        var latest = (await Shares()).Single(x => x.UserId == _customerId);
        Assert.Equal(expiry, latest.ExpiresAt); Assert.Equal(42, latest.Lat); Assert.Equal(started.StartedAt, latest.StartedAt);
        (await Put(_customer, lat: 43)).EnsureSuccessStatusCode();
        _clock.Advance(TimeSpan.FromSeconds(4));
        (await Put(_customer, lat: 44, at: started.FixAt)).EnsureSuccessStatusCode();
        latest = (await Shares()).Single(x => x.UserId == _customerId);
        Assert.Equal(42, latest.Lat); Assert.Equal(expiry, latest.ExpiresAt);
        Assert.Equal(2, await Notifications());
        using var scope = _factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        Assert.Equal(2, await db.Set<PushOutbox>().Join(db.Notifications.Where(x => x.RefId == _dealId), x => x.NotificationId, x => x.Id, (a, b) => a).CountAsync());
    }

    [Fact]
    public async Task ExpiredShareErasesCoordinatesAndRequiresAnExplicitNewStart()
    {
        (await Put(_customer, 60)).EnsureSuccessStatusCode();
        _clock.Advance(TimeSpan.FromMinutes(61));
        Assert.Empty(await Locations(_provider));
        var old = Assert.Single(await Shares()); Assert.Null(old.Lat); Assert.Null(old.Lng); Assert.NotNull(old.StoppedAt);
        Assert.Equal(HttpStatusCode.Conflict, (await Put(_customer)).StatusCode);
        (await Put(_customer, until: true)).EnsureSuccessStatusCode();
        var restarted = Assert.Single(await Shares());
        Assert.Equal(TimeSpan.FromHours(24), restarted.ExpiresAt - restarted.StartedAt);
        Assert.Equal(2, await Notifications());
        Assert.Single(await Locations(_provider));
    }

    [Fact]
    public async Task StopIsIdempotentAndCannotBeUndoneByABackgroundFix()
    {
        (await Put(_customer, 60)).EnsureSuccessStatusCode();
        for (var i = 0; i < 2; i++) Assert.Equal(HttpStatusCode.NoContent, (await _customer.DeleteAsync($"/api/v1/deals/{_dealId}/location")).StatusCode);
        Assert.Empty(await Locations(_provider));
        Assert.Equal(HttpStatusCode.Conflict, (await Put(_customer)).StatusCode);
        var row = Assert.Single(await Shares()); Assert.Null(row.Lat); Assert.Null(row.Lng); Assert.Null(row.Speed);
    }

    [Fact]
    public async Task DelayedExplicitStartAndItsFutureDeviceTimestampCannotUndoStopBeforeFirstFix()
    {
        var generation = await Prepare(_customer);
        var delayed = Fix(60, at: _clock.GetUtcNow().AddSeconds(90), generation: generation);
        var prepared = Assert.Single(await Shares()); Assert.Null(prepared.Lat); Assert.NotNull(prepared.StoppedAt);
        Assert.Equal(generation, prepared.Generation);
        Assert.Equal(HttpStatusCode.NoContent, (await _customer.DeleteAsync($"/api/v1/deals/{_dealId}/location")).StatusCode);
        var stopped = Assert.Single(await Shares()); Assert.NotEqual(generation, stopped.Generation);
        var replay = await _customer.PutAsJsonAsync($"/api/v1/deals/{_dealId}/location", delayed);
        Assert.Equal(HttpStatusCode.Conflict, replay.StatusCode);
        Assert.Equal("LOCATION_NOT_SHARING", (await replay.Content.ReadFromJsonAsync<JsonObject>())!["error"]!.GetValue<string>());
        Assert.Empty(await Locations(_provider)); Assert.Equal(0, await Notifications());
        var next = await Prepare(_customer); Assert.NotEqual(generation, next);
        (await _customer.PutAsJsonAsync($"/api/v1/deals/{_dealId}/location", Fix(60, generation: next))).EnsureSuccessStatusCode();
        Assert.Single(await Locations(_provider));
    }

    [Fact]
    public async Task StopWithoutAnyEarlierRowCreatesFenceAndRepeatedStopsRotateIt()
    {
        Assert.Empty(await Shares());
        Assert.Equal(HttpStatusCode.NoContent, (await _customer.DeleteAsync($"/api/v1/deals/{_dealId}/location")).StatusCode);
        var first = Assert.Single(await Shares()); Assert.NotEqual(Guid.Empty, first.Generation); Assert.Null(first.Lat);
        Assert.Equal(HttpStatusCode.Conflict, (await _customer.PutAsJsonAsync($"/api/v1/deals/{_dealId}/location", Fix(60))).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await _customer.DeleteAsync($"/api/v1/deals/{_dealId}/location")).StatusCode);
        Assert.NotEqual(first.Generation, Assert.Single(await Shares()).Generation);
        Assert.Empty(await Locations(_provider)); Assert.Equal(0, await Notifications());
    }

    [Fact]
    public async Task ActiveGenerationRetryIsIdempotentButExpiredGenerationMustBePreparedAgain()
    {
        var generation = await Prepare(_customer);
        var response = await _customer.PutAsJsonAsync($"/api/v1/deals/{_dealId}/location", Fix(60, generation: generation));
        response.EnsureSuccessStatusCode();
        var original = Assert.Single(await Shares());
        _clock.Advance(TimeSpan.FromSeconds(5));
        (await _customer.PutAsJsonAsync($"/api/v1/deals/{_dealId}/location", Fix(60, generation: generation))).EnsureSuccessStatusCode();
        Assert.Equal(original.ExpiresAt, Assert.Single(await Shares()).ExpiresAt); Assert.Equal(1, await Notifications());
        _clock.Advance(TimeSpan.FromMinutes(61));
        Assert.Equal(HttpStatusCode.Conflict, (await _customer.PutAsJsonAsync($"/api/v1/deals/{_dealId}/location", Fix(60, generation: generation))).StatusCode);
        Assert.Empty(await Locations(_provider));
        Assert.NotEqual(generation, Assert.Single(await Shares()).Generation);
        Assert.Equal(HttpStatusCode.Conflict, (await _customer.PutAsJsonAsync($"/api/v1/deals/{_dealId}/location", Fix(60, generation: generation))).StatusCode);
        (await Put(_customer, 60)).EnsureSuccessStatusCode(); Assert.Single(await Locations(_provider));
    }

    [Fact]
    public async Task BlockInvalidatesAnInactivePreparedGenerationBeforeAnyLocationUpload()
    {
        var generation = await Prepare(_customer);
        (await _provider.PutAsJsonAsync($"/api/v1/blocks/{_customerId}", new { })).EnsureSuccessStatusCode();
        (await _provider.DeleteAsync($"/api/v1/blocks/{_customerId}")).EnsureSuccessStatusCode();
        Assert.NotEqual(generation, Assert.Single(await Shares()).Generation);
        Assert.Equal(HttpStatusCode.Conflict, (await _customer.PutAsJsonAsync($"/api/v1/deals/{_dealId}/location", Fix(60, generation: generation))).StatusCode);
        Assert.Empty(await Locations(_provider)); Assert.Equal(0, await Notifications());
    }

    [Fact]
    public async Task CleanupGenerationPreventsAnAlreadyLoadedFixFromRestoringStoredCoordinates()
    {
        (await Put(_customer, 60)).EnsureSuccessStatusCode();
        using var uploading = _factory.Services.CreateScope();
        var uploadingDb = uploading.ServiceProvider.GetRequiredService<AppDbContext>();
        var loaded = await uploadingDb.Set<LiveLocationShare>().SingleAsync(x => x.DealId == _dealId && x.UserId == _customerId);
        var generation = loaded.Generation;
        // The background worker has an independent context and does not share
        // the API's advisory locks. Its generation must fence this tracked row.
        using (var cleanup = _factory.Services.CreateScope())
        {
            var cleanupDb = cleanup.ServiceProvider.GetRequiredService<AppDbContext>();
            await LiveLocationService.EraseExpired(cleanupDb, _clock.GetUtcNow().AddMinutes(61));
        }
        loaded.Lat = 42; loaded.Lng = 30; loaded.UpdatedAt = _clock.GetUtcNow();
        await Assert.ThrowsAsync<DbUpdateConcurrencyException>(() => uploadingDb.SaveChangesAsync());
        var stored = Assert.Single(await Shares());
        Assert.NotEqual(generation, stored.Generation); Assert.NotNull(stored.StoppedAt);
        Assert.Null(stored.Lat); Assert.Null(stored.Lng); Assert.Null(stored.Accuracy); Assert.Null(stored.Speed);
    }

    [Fact]
    public async Task BlockingImmediatelyErasesBothSharesAndUnblockingNeverResumesThem()
    {
        (await Put(_customer, 60)).EnsureSuccessStatusCode(); (await Put(_provider, 60)).EnsureSuccessStatusCode();
        (await _customer.PutAsJsonAsync($"/api/v1/blocks/{_providerId}", new { })).EnsureSuccessStatusCode();
        Assert.All(await Shares(), x => { Assert.Null(x.Lat); Assert.Null(x.Lng); Assert.NotNull(x.StoppedAt); });
        Assert.Empty(await Locations(_customer)); Assert.Empty(await Locations(_provider));
        Assert.Equal(HttpStatusCode.Forbidden, (await Put(_provider, 60)).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await _provider.DeleteAsync($"/api/v1/deals/{_dealId}/location")).StatusCode);
        (await _customer.DeleteAsync($"/api/v1/blocks/{_providerId}")).EnsureSuccessStatusCode();
        Assert.Empty(await Locations(_provider)); Assert.Equal(HttpStatusCode.Conflict, (await Put(_provider)).StatusCode);
    }

    [Fact]
    public async Task DeliveryEndsUntilDeliveredButFixedShareEndsOnCompletion()
    {
        (await Put(_customer, 480)).EnsureSuccessStatusCode(); (await Put(_provider, until: true)).EnsureSuccessStatusCode();
        await Action(_provider, "deliver");
        var left = Assert.Single(await Locations(_customer)); Assert.Equal(_customerId.ToString(), left!["user_id"]!.GetValue<string>());
        Assert.Null((await Shares()).Single(x => x.UserId == _providerId).Lat);
        Assert.Equal(HttpStatusCode.BadRequest, (await Put(_provider, until: true)).StatusCode);
        await Action(_customer, "complete");
        Assert.Empty(await Locations(_provider)); Assert.All(await Shares(), x => Assert.Null(x.Lat));
        Assert.Equal(HttpStatusCode.BadRequest, (await Put(_customer, 60)).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await _customer.DeleteAsync($"/api/v1/deals/{_dealId}/location")).StatusCode);
    }

    [Fact]
    public async Task MutualCancellationPreservesExistingBusinessRuleThenErasesAllCoordinates()
    {
        (await Put(_customer, 60)).EnsureSuccessStatusCode(); await Action(_customer, "cancel");
        Assert.Single(await Locations(_provider));
        await Action(_provider, "cancel");
        Assert.Empty(await Locations(_provider)); Assert.All(await Shares(), x => Assert.Null(x.Lat));
    }

    [Fact]
    public async Task AccountDeletionCascadesOwnRowAndErasesTheOtherParticipantsShare()
    {
        (await Put(_customer, 60)).EnsureSuccessStatusCode(); (await Put(_provider, 60)).EnsureSuccessStatusCode();
        (await _customer.DeleteAsync("/api/v1/account")).EnsureSuccessStatusCode();
        Assert.Empty(await Locations(_provider));
        var row = Assert.Single(await Shares()); Assert.Equal(_providerId, row.UserId); Assert.Null(row.Lat); Assert.Null(row.Lng);
        Assert.Equal(HttpStatusCode.Unauthorized, (await _customer.GetAsync($"/api/v1/deals/{_dealId}/locations")).StatusCode);
    }

    [Fact]
    public async Task LogoutRevokesSessionAndErasesLocationWithoutDisablingTheOtherUsersLogin()
    {
        (await Put(_customer, 60)).EnsureSuccessStatusCode(); (await Put(_provider, 60)).EnsureSuccessStatusCode();
        (await _customer.PostAsync("/api/v1/auth/logout", null)).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Unauthorized, (await Put(_customer, 60)).StatusCode);
        Assert.Empty(await Locations(_provider)); Assert.All(await Shares(), x => Assert.Null(x.Lat));
        (await Put(_provider, 60)).EnsureSuccessStatusCode(); Assert.Single(await Locations(_provider));
    }

    [Fact]
    public async Task RevokedSessionIsCheckedAgainInsideTheMutationAfterAuthentication()
    {
        Guid sessionId;
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var session = await db.Sessions.SingleAsync(x => x.UserId == _customerId);
            sessionId = session.Id; session.RevokedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync();
        }
        // Simulate a request whose JWT check happened just before logout acquired
        // the user lock. Calling the service directly tests the in-mutation check.
        using var request = _factory.Services.CreateScope();
        var service = request.ServiceProvider.GetRequiredService<LiveLocationService>();
        var error = await Assert.ThrowsAsync<ApiError>(() => service.Put(_customerId, _dealId,
            new ShareLocationInput(41, 29, _clock.GetUtcNow(), Minutes: 60), sessionId));
        Assert.Equal("AUTH_REQUIRED", error.Code); Assert.Equal(401, error.Status);
        Assert.Empty(await Shares());
    }

    [Fact]
    public async Task CleanupErasesExpiredCoordinatesAndPurgesInactiveRowsAfterSevenDays()
    {
        (await Put(_customer, 60)).EnsureSuccessStatusCode();
        _clock.Advance(TimeSpan.FromDays(8));
        using var scope = _factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await LiveLocationCleanup.Purge(db, _clock.GetUtcNow());
        Assert.Empty(await db.Set<LiveLocationShare>().Where(x => x.DealId == _dealId).ToArrayAsync());
    }
}

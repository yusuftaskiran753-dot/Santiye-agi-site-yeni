using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Configuration;
using Npgsql;
using SantiyeAgi.Api.Data;

namespace SantiyeAgi.Api.Tests;

[CollectionDefinition("Postgres", DisableParallelization = true)]
public class PostgresCollection;

[Collection("Postgres")]
public class ApiIntegrationTests : IAsyncLifetime
{
    private WebApplicationFactory<Program> _factory = null!;
    private string _database = "";
    private string _admin = "";
    private string _connection = "";
    private string? _previousConnection;
    private string? _previousKey;
    private string? _previousProtection;
    public async Task InitializeAsync()
    {
        _admin = Environment.GetEnvironmentVariable("SANTIYE_TEST_POSTGRES") ?? throw new InvalidOperationException("Set SANTIYE_TEST_POSTGRES to the dedicated local test PostgreSQL connection.");
        var builder = new NpgsqlConnectionStringBuilder(_admin);
        if (builder.Host is not "127.0.0.1" and not "localhost") throw new InvalidOperationException("Integration tests only run on localhost.");
        _database = "santiye_test_" + Guid.NewGuid().ToString("N");
        await using (var connection = new NpgsqlConnection(_admin))
        {
            await connection.OpenAsync();
            await using var command = new NpgsqlCommand($"CREATE DATABASE \"{_database}\"", connection); await command.ExecuteNonQueryAsync();
        }
        builder.Database = _database; _connection = builder.ConnectionString;
        _previousConnection = Environment.GetEnvironmentVariable("ConnectionStrings__Postgres"); _previousKey = Environment.GetEnvironmentVariable("Auth__SigningKey");
        Environment.SetEnvironmentVariable("ConnectionStrings__Postgres", _connection);
        Environment.SetEnvironmentVariable("Auth__SigningKey", new string('T', 64));
        _previousProtection = Environment.GetEnvironmentVariable("DataProtection__KeysPath");
        Environment.SetEnvironmentVariable("DataProtection__KeysPath", Path.Combine(AppContext.BaseDirectory, "development-keys"));
        _factory = new WebApplicationFactory<Program>().WithWebHostBuilder(b => b.UseEnvironment("Development"));
        using var scope = _factory.Services.CreateScope(); await scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.MigrateAsync();
    }
    public async Task DisposeAsync()
    {
        if (_factory is not null) await _factory.DisposeAsync();
        Environment.SetEnvironmentVariable("ConnectionStrings__Postgres", _previousConnection); Environment.SetEnvironmentVariable("Auth__SigningKey", _previousKey);
        Environment.SetEnvironmentVariable("DataProtection__KeysPath", _previousProtection);
        NpgsqlConnection.ClearAllPools();
        if (_database.StartsWith("santiye_test_") && _database.Length == 45)
        {
            await using var connection = new NpgsqlConnection(_admin); await connection.OpenAsync();
            await using var command = new NpgsqlCommand($"DROP DATABASE \"{_database}\" WITH (FORCE)", connection); await command.ExecuteNonQueryAsync();
        }
    }
    private async Task<(HttpClient Client, Guid User)> Login(string phone, string name)
    {
        var client = _factory.CreateClient();
        var request = await client.PostAsJsonAsync("/api/v1/auth/phone/request", new { phone });
        var code = (await request.Content.ReadFromJsonAsync<JsonObject>())!["development_code"]!.GetValue<string>();
        var verify = await client.PostAsJsonAsync("/api/v1/auth/phone/verify", new { phone, code }); verify.EnsureSuccessStatusCode();
        var session = (await verify.Content.ReadFromJsonAsync<JsonObject>())!;
        client.DefaultRequestHeaders.Authorization = new("Bearer", session["access_token"]!.GetValue<string>());
        var user = Guid.Parse(session["user_id"]!.GetValue<string>());
        var profile = await client.PutAsJsonAsync("/api/v1/profiles/me", new { name, phone, company = "", role = "nakliyeci", city = "İstanbul" }); profile.EnsureSuccessStatusCode();
        return (client, user);
    }

    [Fact]
    public async Task ProvisionedPasswordLoginIsReusableAndHonorsPhonePolicyAndAccountDeletion()
    {
        var userId = Guid.NewGuid();
        using (var scope = _factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.Users.Add(new User { Id = userId, Name = "Local review fixture", ProfileComplete = true });
            await db.SaveChangesAsync();
        }
        const string password = "Local-only-account-test-327!";
        var settings = new Dictionary<string, string?>
        {
            ["Auth:RequirePhoneVerification"] = "false",
            ["Auth:AccountLogin:Enabled"] = "true",
            ["Auth:AccountLogin:Accounts:0:Username"] = "local.fixture",
            ["Auth:AccountLogin:Accounts:0:UserId"] = userId.ToString(),
            ["Auth:AccountLogin:Accounts:0:PasswordHash"] = Auth.AccountPassword.Hash(password)
        };
        await using var configured = _factory.WithWebHostBuilder(b => b.ConfigureAppConfiguration((_, c) => c.AddInMemoryCollection(settings)));
        using var first = configured.CreateClient();
        using var second = configured.CreateClient();
        var bad = await first.PostAsJsonAsync("/api/v1/auth/password/login", new { username = "local.fixture", password = password + "bad" });
        Assert.Equal(HttpStatusCode.Unauthorized, bad.StatusCode);
        foreach (var client in new[] { first, second })
        {
            var response = await client.PostAsJsonAsync("/api/v1/auth/password/login", new { username = "LOCAL.FIXTURE", password });
            response.EnsureSuccessStatusCode();
            var session = (await response.Content.ReadFromJsonAsync<JsonObject>())!;
            Assert.Equal(userId.ToString(), session["user_id"]!.GetValue<string>());
            Assert.False(session["phone_verified"]!.GetValue<bool>());
            client.DefaultRequestHeaders.Authorization = new("Bearer", session["access_token"]!.GetValue<string>());
            (await client.GetAsync("/api/v1/profiles/me")).EnsureSuccessStatusCode();
        }
        var phoneSettings = new Dictionary<string, string?>(settings) { ["Auth:RequirePhoneVerification"] = "true" };
        await using var phoneRequired = _factory.WithWebHostBuilder(b => b.ConfigureAppConfiguration((_, c) => c.AddInMemoryCollection(phoneSettings)));
        var blocked = await phoneRequired.CreateClient().PostAsJsonAsync("/api/v1/auth/password/login", new { username = "local.fixture", password });
        Assert.Equal(HttpStatusCode.Forbidden, blocked.StatusCode);
        (await first.DeleteAsync("/api/v1/account")).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Unauthorized, (await second.GetAsync("/api/v1/profiles/me")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await second.PostAsJsonAsync("/api/v1/auth/password/login", new { username = "local.fixture", password })).StatusCode);
    }
    private async Task<Guid> Machine(HttpClient client, bool available = true)
    {
        var id = Guid.NewGuid();
        var response = await client.PutAsJsonAsync($"/api/v1/listings/makine/{id}", new { type = "ekskavator", model = "Test makine", capacity = "", city = "İstanbul", lat = 41m, lng = 29m, hourly = 500m, daily = 3000m, available, with_operator = true, note = "", status = "active" });
        response.EnsureSuccessStatusCode(); return id;
    }
    private static byte[] TestPhoto()
    {
        using var bitmap = new SkiaSharp.SKBitmap(32, 16);
        using (var canvas = new SkiaSharp.SKCanvas(bitmap)) canvas.Clear(SkiaSharp.SKColors.Orange);
        using var image = SkiaSharp.SKImage.FromBitmap(bitmap);
        using var data = image.Encode(SkiaSharp.SKEncodedImageFormat.Png, 100);
        return data.ToArray();
    }
    private static async Task<HttpResponseMessage> UploadPhoto(HttpClient client, Guid id, byte[] bytes, string caption = "Tamamlanan iş")
    {
        using var form = new MultipartFormDataContent();
        form.Add(new StringContent(id.ToString()), "id");
        form.Add(new StringContent(caption), "caption");
        // Yanıltıcı dosya adı veya MIME kabul ölçütü değildir; gerçek görüntü çözülür.
        var file = new ByteArrayContent(bytes); file.Headers.ContentType = new("application/octet-stream");
        form.Add(file, "file", "untrusted.png");
        return await client.PostAsync("/api/v1/portfolio", form);
    }
    [Fact]
    public async Task PortfolioOwnershipBlockingNormalizationAndAccountCleanup()
    {
        var (owner, ownerId) = await Login("+905551000061", "Fotoğraf sahibi");
        var (other, otherId) = await Login("+905551000062", "Ziyaretçi");
        using (owner) using (other)
        {
            var id = Guid.NewGuid(); var bytes = TestPhoto();
            (await UploadPhoto(owner, id, bytes)).EnsureSuccessStatusCode();
            (await UploadPhoto(owner, id, bytes)).EnsureSuccessStatusCode();
            Assert.Equal(HttpStatusCode.BadRequest, (await UploadPhoto(owner, id, bytes, "Değişen açıklama")).StatusCode);
            var list = await other.GetFromJsonAsync<JsonArray>($"/api/v1/profiles/{ownerId}/portfolio");
            Assert.Single(list!); Assert.Null(list![0]!["data"]);
            var image = await other.GetAsync($"/api/v1/portfolio/{id}/image"); image.EnsureSuccessStatusCode();
            Assert.Equal("image/jpeg", image.Content.Headers.ContentType!.MediaType);
            Assert.True(image.Headers.CacheControl!.NoStore);
            var jpeg = await image.Content.ReadAsByteArrayAsync(); Assert.Equal(0xff, jpeg[0]); Assert.Equal(0xd8, jpeg[1]);
            Assert.Equal(HttpStatusCode.Forbidden, (await other.DeleteAsync($"/api/v1/portfolio/{id}")).StatusCode);
            using var unauthenticated = _factory.CreateClient();
            Assert.Equal(HttpStatusCode.Unauthorized, (await unauthenticated.GetAsync($"/api/v1/portfolio/{id}/image")).StatusCode);
            (await owner.PutAsync($"/api/v1/blocks/{otherId}", null)).EnsureSuccessStatusCode();
            Assert.Equal(HttpStatusCode.Forbidden, (await other.GetAsync($"/api/v1/portfolio/{id}/image")).StatusCode);
            Assert.Equal(HttpStatusCode.Forbidden, (await other.GetAsync($"/api/v1/profiles/{ownerId}/portfolio")).StatusCode);
            (await owner.DeleteAsync($"/api/v1/blocks/{otherId}")).EnsureSuccessStatusCode();
            (await owner.DeleteAsync($"/api/v1/portfolio/{id}")).EnsureSuccessStatusCode();
            Assert.Equal(HttpStatusCode.NotFound, (await other.GetAsync($"/api/v1/portfolio/{id}/image")).StatusCode);
            (await UploadPhoto(owner, Guid.NewGuid(), bytes)).EnsureSuccessStatusCode();
            (await owner.DeleteAsync("/api/v1/account")).EnsureSuccessStatusCode();
            using var scope = _factory.Services.CreateScope();
            Assert.False(await scope.ServiceProvider.GetRequiredService<AppDbContext>().PortfolioPhotos.AnyAsync(x => x.OwnerId == ownerId));
        }
    }
    [Fact]
    public async Task PortfolioRejectsInvalidImagesOversizeAndQuotaOverflow()
    {
        var (owner, ownerId) = await Login("+905551000071", "Fotoğraf sahibi");
        using (owner)
        {
            Assert.Equal(HttpStatusCode.BadRequest, (await UploadPhoto(owner, Guid.NewGuid(), "<svg/>"u8.ToArray())).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await UploadPhoto(owner, Guid.NewGuid(), new byte[8 * 1024 * 1024 + 1])).StatusCode);
            Assert.Equal(HttpStatusCode.BadRequest, (await UploadPhoto(owner, Guid.NewGuid(), TestPhoto(), new string('A', 201))).StatusCode);
            using (var scope = _factory.Services.CreateScope())
            {
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                db.PortfolioPhotos.AddRange(Enumerable.Range(0, 20).Select(_ => new PortfolioPhoto { Id = Guid.NewGuid(), OwnerId = ownerId, Data = TestPhoto(), Width = 32, Height = 16 }));
                await db.SaveChangesAsync();
            }
            Assert.Equal(HttpStatusCode.Conflict, (await UploadPhoto(owner, Guid.NewGuid(), TestPhoto())).StatusCode);
        }
    }
    [Fact]
    public async Task AuthorizationAndOwnershipAreEnforced()
    {
        using var anonymous = _factory.CreateClient(); Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync("/api/v1/usage")).StatusCode);
        var (owner, _) = await Login("+905551000001", "Sahip"); var (other, _) = await Login("+905551000002", "Diğer");
        using (owner) using (other)
        {
            var id = await Machine(owner);
            Assert.Equal(HttpStatusCode.Forbidden, (await other.PutAsJsonAsync($"/api/v1/listings/makine/{id}/status", new { status = "closed" })).StatusCode);
            Assert.Equal(HttpStatusCode.Forbidden, (await other.DeleteAsync($"/api/v1/listings/makine/{id}")).StatusCode);
        }
    }
    [Fact]
    public async Task RequestsRequireAvailabilityAndAreIdempotent()
    {
        var (owner, ownerId) = await Login("+905551000011", "Sahip"); var (other, _) = await Login("+905551000012", "Talep eden");
        using (owner) using (other)
        {
            var id = await Machine(owner);
            var unlock = await other.PostAsJsonAsync($"/api/v1/listings/makine/{id}/unlock", new { use_credit = false }); unlock.EnsureSuccessStatusCode();
            var body = new { kind = "makine", listing_id = id, amount = 3000m, quantity = 1m, unit = "gün", start_date = (string?)null, address = "", note = "" };
            other.DefaultRequestHeaders.Add("Idempotency-Key", Guid.NewGuid().ToString());
            var first = await other.PostAsJsonAsync("/api/v1/requests", body); first.EnsureSuccessStatusCode();
            var second = await other.PostAsJsonAsync("/api/v1/requests", body); second.EnsureSuccessStatusCode();
            var row = (await first.Content.ReadFromJsonAsync<JsonObject>())!; var duplicate = (await second.Content.ReadFromJsonAsync<JsonObject>())!;
            Assert.Equal(row["id"]!.ToString(), duplicate["id"]!.ToString());
            other.DefaultRequestHeaders.Remove("Idempotency-Key");
            await owner.PutAsJsonAsync($"/api/v1/machines/{id}/availability", new { available = false });
            var unavailable = await owner.PostAsJsonAsync($"/api/v1/requests/{row["id"]}/respond", new { accept = true });
            Assert.Equal("NOT_AVAILABLE", (await unavailable.Content.ReadFromJsonAsync<JsonObject>())!["error"]!.ToString());
            await owner.PutAsJsonAsync($"/api/v1/machines/{id}/availability", new { available = true });
            await other.PutAsync($"/api/v1/blocks/{ownerId}", null);
            var blocked = await owner.PostAsJsonAsync($"/api/v1/requests/{row["id"]}/respond", new { accept = true });
            Assert.Equal(HttpStatusCode.Forbidden, blocked.StatusCode);
        }
    }
    [Fact]
    public async Task SameOperationKeyCannotHideDifferentPayload()
    {
        var (client, _) = await Login("+905551000021", "Sahip");
        using (client)
        {
            var id = await Machine(client);
            client.DefaultRequestHeaders.Add("Idempotency-Key", Guid.NewGuid().ToString());
            (await client.PutAsJsonAsync($"/api/v1/listings/makine/{id}/status", new { status = "closed" })).EnsureSuccessStatusCode();
            Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsJsonAsync($"/api/v1/listings/makine/{id}/status", new { status = "active" })).StatusCode);
        }
    }
    [Fact]
    public async Task UnverifiedPurchaseCannotGrantCredits()
    {
        var (client, _) = await Login("+905551000031", "Sahip");
        using (client)
        {
            var response = await client.PostAsJsonAsync("/api/v1/billing/verify", new { productId = "santiye_kredi_40", token = "fake", platform = "android" });
            Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
            var usage = (await client.GetFromJsonAsync<JsonObject>("/api/v1/usage"))!; Assert.Equal(0, usage["credits"]!.GetValue<int>());
        }
    }
    [Fact]
    public async Task CompleteTradeAndDeleteAccountPreservesAnonymousRating()
    {
        var (owner, ownerId) = await Login("+905551000041", "Makine sahibi"); var (buyer, buyerId) = await Login("+905551000042", "Alıcı");
        using (owner) using (buyer)
        {
            var id = await Machine(owner);
            (await buyer.PostAsJsonAsync($"/api/v1/listings/makine/{id}/unlock", new { use_credit = false })).EnsureSuccessStatusCode();
            var requestResponse = await buyer.PostAsJsonAsync("/api/v1/requests", new { kind = "makine", listing_id = id, amount = 3000m, quantity = 1m, unit = "gün", start_date = (string?)null, address = "", note = "" }); requestResponse.EnsureSuccessStatusCode();
            var request = (await requestResponse.Content.ReadFromJsonAsync<JsonObject>())!;
            var accept = await owner.PostAsJsonAsync($"/api/v1/requests/{request["id"]}/respond", new { accept = true }); accept.EnsureSuccessStatusCode();
            var dealId = (await accept.Content.ReadFromJsonAsync<JsonObject>())!["deal_id"]!.ToString();
            (await owner.PostAsJsonAsync($"/api/v1/deals/{dealId}/actions", new { action = "deliver", note = "" })).EnsureSuccessStatusCode();
            (await buyer.PostAsJsonAsync($"/api/v1/deals/{dealId}/actions", new { action = "complete", note = "" })).EnsureSuccessStatusCode();
            (await buyer.PostAsJsonAsync($"/api/v1/deals/{dealId}/ratings", new { stars = 5, comment = "Başarılı iş" })).EnsureSuccessStatusCode();
            var before = (await owner.GetFromJsonAsync<JsonObject>("/api/v1/profiles/me"))!; Assert.Equal(1, before["rating_count"]!.GetValue<int>());
            (await buyer.DeleteAsync("/api/v1/account")).EnsureSuccessStatusCode();
            Assert.Equal(HttpStatusCode.Unauthorized, (await buyer.GetAsync("/api/v1/usage")).StatusCode);
            var after = (await owner.GetFromJsonAsync<JsonObject>("/api/v1/profiles/me"))!; Assert.Equal(1, after["rating_count"]!.GetValue<int>());
            var ratings = await owner.GetFromJsonAsync<JsonArray>($"/api/v1/profiles/{ownerId}/ratings"); Assert.Equal("Silinen kullanıcı", ratings![0]!["from_name"]!.ToString());
            using var scope = _factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            Assert.False(await db.Users.AnyAsync(x => x.Id == buyerId));
            var deal = await db.Deals.SingleAsync(); Assert.DoesNotContain("Alıcı", deal.Data);
            Assert.DoesNotContain(buyerId.ToString(), deal.Data);
        }
    }
    [Fact]
    public async Task DeletingOneParticipantClosesOpenDisputeWithoutLockingSurvivor()
    {
        var (owner, _) = await Login("+905551000081", "Ayrılan taraf");
        var (buyer, _) = await Login("+905551000082", "Kalan taraf");
        using (owner) using (buyer)
        {
            var id = await Machine(owner);
            (await buyer.PostAsJsonAsync($"/api/v1/listings/makine/{id}/unlock", new { use_credit = false })).EnsureSuccessStatusCode();
            var response = await buyer.PostAsJsonAsync("/api/v1/requests", new { kind = "makine", listing_id = id, amount = 3000m, quantity = 1m, unit = "gün", note = "Kişisel bilgi içeren not" });
            response.EnsureSuccessStatusCode();
            var request = (await response.Content.ReadFromJsonAsync<JsonObject>())!;
            var accept = await owner.PostAsJsonAsync($"/api/v1/requests/{request["id"]}/respond", new { accept = true }); accept.EnsureSuccessStatusCode();
            var dealId = (await accept.Content.ReadFromJsonAsync<JsonObject>())!["deal_id"]!.ToString();
            (await owner.PostAsJsonAsync($"/api/v1/deals/{dealId}/actions", new { action = "dispute", note = "Sorun" })).EnsureSuccessStatusCode();
            (await owner.DeleteAsync("/api/v1/account")).EnsureSuccessStatusCode();
            var deals = (await buyer.GetFromJsonAsync<JsonObject>("/api/v1/deals"))!["items"]!.AsArray();
            Assert.Single(deals);
            Assert.Equal("cancelled", deals[0]!["status"]!.ToString());
            Assert.DoesNotContain("Kişisel", deals[0]!.ToJsonString());
            Assert.Equal("Hesabı silinen kullanıcıyla yapılan işlem", deals[0]!["title"]!.ToString());
        }
    }
    [Fact]
    public async Task DuplicateConcurrentUnlockUsesOnlyOneFreeRight()
    {
        var (owner, _) = await Login("+905551000051", "Sahip"); var (client, _) = await Login("+905551000052", "Alıcı");
        using (owner) using (client)
        {
            var id = await Machine(owner);
            var results = await Task.WhenAll(Enumerable.Range(0, 8).Select(_ => client.PostAsJsonAsync($"/api/v1/listings/makine/{id}/unlock", new { use_credit = false })));
            foreach (var result in results) result.EnsureSuccessStatusCode();
            Assert.Equal(1, (await client.GetFromJsonAsync<JsonObject>("/api/v1/usage"))!["free_used"]!.GetValue<int>());
        }
    }

    [Fact]
    public async Task ProductionSmsToggleAllowsGuestDataAndGatesExistingSessionsWhenEnabled()
    {
        await using var production = _factory.WithWebHostBuilder(b => b.UseEnvironment("Production")
            .ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Auth:RequirePhoneVerification"] = "false",
                ["DataProtection:KeysPath"] = Path.Combine(AppContext.BaseDirectory, "development-keys"),
                ["Sms:Provider"] = "Disabled"
            })));
        using var guest = production.CreateClient(new WebApplicationFactoryClientOptions { BaseAddress = new Uri("https://localhost") });
        var options = (await guest.GetFromJsonAsync<JsonObject>("/api/v1/auth/options"))!;
        Assert.False(options["phone_verification_required"]!.GetValue<bool>());
        var login = await guest.PostAsJsonAsync("/api/v1/auth/anonymous", new { }); login.EnsureSuccessStatusCode();
        var session = (await login.Content.ReadFromJsonAsync<JsonObject>())!;
        Assert.False(session["phone_verified"]!.GetValue<bool>());
        guest.DefaultRequestHeaders.Authorization = new("Bearer", session["access_token"]!.ToString());
        var profileBody = new { name = "SMS'siz hesap", company = "", role = "muteahhit", city = "İstanbul", phone = "+905551000091" };
        var saved = await guest.PutAsJsonAsync("/api/v1/profiles/me", profileBody); saved.EnsureSuccessStatusCode();
        Assert.False((await saved.Content.ReadFromJsonAsync<JsonObject>())!["phone_verified"]!.GetValue<bool>());
        var machine = await Machine(guest);
        Assert.Equal(1, (await guest.GetFromJsonAsync<JsonObject>("/api/v1/usage"))!["active_listings"]!.GetValue<int>());
        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await guest.PostAsJsonAsync("/api/v1/auth/phone/request", new { phone = profileBody.phone })).StatusCode);
        var config = production.Services.GetRequiredService<IConfiguration>();
        config["Auth:RequirePhoneVerification"] = "true";
        Assert.True((await guest.GetFromJsonAsync<JsonObject>("/api/v1/auth/options"))!["phone_verification_required"]!.GetValue<bool>());
        var blocked = await guest.GetAsync("/api/v1/usage");
        Assert.Equal(HttpStatusCode.Forbidden, blocked.StatusCode);
        Assert.Equal("PHONE_REQUIRED", (await blocked.Content.ReadFromJsonAsync<JsonObject>())!["error"]!.ToString());
        Assert.Equal(HttpStatusCode.Forbidden, (await guest.PutAsJsonAsync("/api/v1/profiles/me", profileBody)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await UploadPhoto(guest, Guid.NewGuid(), TestPhoto())).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await guest.PostAsJsonAsync("/api/v1/auth/anonymous", new { })).StatusCode);
        config["Auth:RequirePhoneVerification"] = "false";
        Assert.Equal(1, (await guest.GetFromJsonAsync<JsonObject>("/api/v1/usage"))!["active_listings"]!.GetValue<int>());
        Assert.Contains((await guest.GetFromJsonAsync<JsonObject>("/api/v1/listings/makine"))!["items"]!.AsArray(), r => r!["id"]!.ToString() == machine.ToString());
        // Ayrı test veritabanında gerçek OTP sağlayıcısının doğrulama sonucunu temsil eder.
        using (var scope = production.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var user = await db.Users.FindAsync(Guid.Parse(session["user_id"]!.ToString()));
            user!.PhoneVerified = true; await db.SaveChangesAsync();
        }
        config["Auth:RequirePhoneVerification"] = "true";
        // Aynı JWT için durum veritabanından yeniden okunur; telefon doğrulanmış hesap devam eder.
        Assert.Equal(HttpStatusCode.OK, (await guest.GetAsync("/api/v1/usage")).StatusCode);
    }

    [Fact]
    public async Task GuestCannotClaimAnExistingPhoneOrReceiveVerifiedBadge()
    {
        await using var optional = _factory.WithWebHostBuilder(b => b.ConfigureAppConfiguration((_, config) =>
            config.AddInMemoryCollection(new Dictionary<string, string?> { ["Auth:RequirePhoneVerification"] = "false" })));
        using var first = optional.CreateClient(); using var second = optional.CreateClient();
        foreach (var client in new[] { first, second })
        {
            var login = await client.PostAsJsonAsync("/api/v1/auth/anonymous", new { }); login.EnsureSuccessStatusCode();
            var json = (await login.Content.ReadFromJsonAsync<JsonObject>())!;
            client.DefaultRequestHeaders.Authorization = new("Bearer", json["access_token"]!.ToString());
        }
        var profile = new { name = "İlk hesap", company = "", role = "muteahhit", city = "İstanbul", phone = "+905551000092" };
        (await first.PutAsJsonAsync("/api/v1/profiles/me", profile)).EnsureSuccessStatusCode();
        Assert.Equal(HttpStatusCode.Conflict, (await second.PutAsJsonAsync("/api/v1/profiles/me", profile)).StatusCode);
        Assert.False((await first.GetFromJsonAsync<JsonObject>("/api/v1/profiles/me"))!["phone_verified"]!.GetValue<bool>());
        Assert.Null(await second.GetFromJsonAsync<JsonObject?>("/api/v1/profiles/me"));
    }

    [Fact]
    public async Task HaulPointsArePrivatePersistedAndRemovedWithTheirOwner()
    {
        var (owner, ownerId) = await Login("+905551000093", "Saha sahibi");
        var (other, _) = await Login("+905551000094", "Diğer hesap");
        using (owner) using (other)
        {
            var id = Guid.NewGuid();
            var body = new { name = "Kazı sahası", kind = "excavation", lat = 41m, lng = 29m, volume = 2500m, feePerM3 = 0m, needM3 = 300m, material = "", demo = false };
            (await owner.PutAsJsonAsync($"/api/v1/haul-points/{id}", body)).EnsureSuccessStatusCode();
            // Aynı kimlikle tekrar gönderim ikinci saha oluşturmamalı.
            (await owner.PutAsJsonAsync($"/api/v1/haul-points/{id}", body)).EnsureSuccessStatusCode();
            var saved = Assert.Single((await owner.GetFromJsonAsync<JsonArray>("/api/v1/haul-points"))!);
            Assert.Equal(300m, saved!["needM3"]!.GetValue<decimal>());
            Assert.False(saved["demo"]!.GetValue<bool>());
            Assert.Empty((await other.GetFromJsonAsync<JsonArray>("/api/v1/haul-points"))!);
            Assert.Equal(HttpStatusCode.Forbidden, (await other.PutAsJsonAsync($"/api/v1/haul-points/{id}", body)).StatusCode);
            Assert.Equal(HttpStatusCode.Forbidden, (await other.DeleteAsync($"/api/v1/haul-points/{id}")).StatusCode);
            (await owner.DeleteAsync($"/api/v1/haul-points/{id}")).EnsureSuccessStatusCode();
            Assert.Empty((await owner.GetFromJsonAsync<JsonArray>("/api/v1/haul-points"))!);
            (await owner.PutAsJsonAsync($"/api/v1/haul-points/{id}", body)).EnsureSuccessStatusCode();
            (await owner.DeleteAsync("/api/v1/account")).EnsureSuccessStatusCode();
            using var scope = _factory.Services.CreateScope();
            Assert.False(await scope.ServiceProvider.GetRequiredService<AppDbContext>().HaulPoints.AnyAsync(x => x.OwnerId == ownerId));
        }
    }

    [Fact]
    public async Task HaulPointsRejectDemoDataAndInvalidCoordinates()
    {
        var (owner, _) = await Login("+905551000095", "Saha doğrulama");
        using (owner)
        {
            var body = new JsonObject { ["name"] = "Kontrol", ["kind"] = "dump", ["lat"] = 91, ["lng"] = 29, ["volume"] = 100,
                ["feePerM3"] = 10, ["needM3"] = 0, ["material"] = "", ["demo"] = false };
            var path = $"/api/v1/haul-points/{Guid.NewGuid()}";
            Assert.Equal(HttpStatusCode.BadRequest, (await owner.PutAsJsonAsync(path, body)).StatusCode);
            body["lat"] = 41; body["demo"] = true;
            Assert.Equal(HttpStatusCode.BadRequest, (await owner.PutAsJsonAsync(path, body)).StatusCode);
            body["demo"] = false; body["volume"] = -1;
            Assert.Equal(HttpStatusCode.BadRequest, (await owner.PutAsJsonAsync(path, body)).StatusCode);
            Assert.Empty((await owner.GetFromJsonAsync<JsonArray>("/api/v1/haul-points"))!);
        }
    }
    [Fact]
    public async Task BillingSyncRequiresLoginAndDoesNotCreateUnverifiedEntitlements()
    {
        using var anonymous = _factory.CreateClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.PostAsJsonAsync("/api/v1/billing/sync", new { })).StatusCode);
        var (client, _) = await Login("+905551000097", "Billing sync fixture");
        using (client)
        {
            var result = await client.PostAsJsonAsync("/api/v1/billing/sync", new { });
            result.EnsureSuccessStatusCode();
            var data = (await result.Content.ReadFromJsonAsync<JsonObject>())!;
            Assert.Equal(0, data["credits"]!.GetValue<int>());
            Assert.Null(data["premium_until"]);
        }
        using var scope = _factory.Services.CreateScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<AppDbContext>()
            .Set<SantiyeAgi.Api.Billing.StorePurchase>().ToListAsync());
    }

    [Fact]
    public async Task ConfiguredAppleCallbackStillRejectsUnsignedPayload()
    {
        using var factory = _factory.WithWebHostBuilder(builder => builder.ConfigureAppConfiguration((_, config) =>
            config.AddInMemoryCollection(new Dictionary<string, string?> {
                ["Billing:Enabled"] = "true", ["Billing:AppleAppId"] = "6824034438",
                ["Billing:AppleBundleId"] = "com.yusuftaskiran.santiyeagi.pro" })));
        using var client = factory.CreateClient();
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await client.PostAsJsonAsync(
            "/api/v1/billing/apple/notifications", new { signedPayload = "not-an-apple-jws" })).StatusCode);
    }

    [Theory]
    [InlineData("Production", "com.yusuftaskiran.santiyeagi.pro", 6824034438L, true)]
    [InlineData("Sandbox", "com.yusuftaskiran.santiyeagi.pro", 6824034438L, false)]
    [InlineData("Production", "wrong.bundle", 6824034438L, false)]
    [InlineData("Production", "com.yusuftaskiran.santiyeagi.pro", 123L, false)]
    public async Task AppleCallbackChecksApplicationAndEnvironmentWithoutGrantingRights(string environment, string bundle, long appId, bool accepted)
    {
        // A local signature seam isolates routing/identity policy; this is NOT a real Apple signature or receipt.
        using var factory = _factory.WithWebHostBuilder(builder => {
            builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(new Dictionary<string, string?> {
                ["Billing:Enabled"] = "true", ["Billing:AllowSandbox"] = "false",
                ["Billing:AppleAppId"] = "6824034438", ["Billing:AppleBundleId"] = "com.yusuftaskiran.santiyeagi.pro" }));
            builder.ConfigureServices(services => services.AddSingleton<SantiyeAgi.Api.Billing.IAppleSignedDataVerifier>(
                new NotificationFixtureSignature(new JsonObject { ["notificationType"] = "TEST", ["data"] = new JsonObject {
                    ["environment"] = environment, ["bundleId"] = bundle, ["appAppleId"] = appId } })));
        });
        using var client = factory.CreateClient();
        var response = await client.PostAsJsonAsync("/api/v1/billing/apple/notifications", new { signedPayload = "fixture-only" });
        Assert.Equal(accepted ? HttpStatusCode.OK : HttpStatusCode.UnprocessableEntity, response.StatusCode);
        using var scope = factory.Services.CreateScope();
        Assert.Empty(await scope.ServiceProvider.GetRequiredService<AppDbContext>()
            .Set<SantiyeAgi.Api.Billing.StorePurchase>().ToListAsync());
    }
    private sealed class NotificationFixtureSignature(JsonObject payload) : SantiyeAgi.Api.Billing.IAppleSignedDataVerifier
    {
        public JsonObject Verify(string signed, string? environment) => signed == "fixture-only"
            ? payload.DeepClone().AsObject() : throw new SantiyeAgi.Api.Infrastructure.ApiError("INVALID", 422);
    }

}

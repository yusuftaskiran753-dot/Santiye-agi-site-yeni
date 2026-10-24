using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using SantiyeAgi.Api.Data;

namespace SantiyeAgi.Api.Tests;

// Müşterinin ilk mobilindeki beş talep formu ve kodla katılma akışlarının
// gerçek HTTP + PostgreSQL sınırında korunmasını denetler.
[Collection("Postgres")]
public sealed class TradeParityIntegrationTests : IAsyncLifetime
{
    private WebApplicationFactory<Program> _factory = null!;
    private string _database = "";
    private string _admin = "";
    private string? _previousConnection;
    private string? _previousKey;

    public async Task InitializeAsync()
    {
        _admin = Environment.GetEnvironmentVariable("SANTIYE_TEST_POSTGRES") ?? throw new InvalidOperationException("A dedicated localhost test PostgreSQL connection is required.");
        var builder = new NpgsqlConnectionStringBuilder(_admin);
        if (builder.Host is not "127.0.0.1" and not "localhost") throw new InvalidOperationException("Integration tests only run on localhost.");
        _database = "santiye_test_" + Guid.NewGuid().ToString("N");
        await using (var connection = new NpgsqlConnection(_admin))
        {
            await connection.OpenAsync();
            await using var command = new NpgsqlCommand($"CREATE DATABASE \"{_database}\"", connection);
            await command.ExecuteNonQueryAsync();
        }
        builder.Database = _database;
        _previousConnection = Environment.GetEnvironmentVariable("ConnectionStrings__Postgres");
        _previousKey = Environment.GetEnvironmentVariable("Auth__SigningKey");
        Environment.SetEnvironmentVariable("ConnectionStrings__Postgres", builder.ConnectionString);
        Environment.SetEnvironmentVariable("Auth__SigningKey", new string('T', 64));
        _factory = new WebApplicationFactory<Program>().WithWebHostBuilder(b => b.UseEnvironment("Development"));
        using var scope = _factory.Services.CreateScope();
        await scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.MigrateAsync();
    }

    public async Task DisposeAsync()
    {
        if (_factory is not null) await _factory.DisposeAsync();
        Environment.SetEnvironmentVariable("ConnectionStrings__Postgres", _previousConnection);
        Environment.SetEnvironmentVariable("Auth__SigningKey", _previousKey);
        NpgsqlConnection.ClearAllPools();
        if (_database.StartsWith("santiye_test_", StringComparison.Ordinal) && _database.Length == 45)
        {
            await using var connection = new NpgsqlConnection(_admin);
            await connection.OpenAsync();
            await using var command = new NpgsqlCommand($"DROP DATABASE \"{_database}\" WITH (FORCE)", connection);
            await command.ExecuteNonQueryAsync();
        }
    }

    private async Task<HttpClient> Login(string phone, string name)
    {
        var client = _factory.CreateClient();
        var challenge = await client.PostAsJsonAsync("/api/v1/auth/phone/request", new { phone }); challenge.EnsureSuccessStatusCode();
        var code = (await challenge.Content.ReadFromJsonAsync<JsonObject>())!["development_code"]!.GetValue<string>();
        var verify = await client.PostAsJsonAsync("/api/v1/auth/phone/verify", new { phone, code }); verify.EnsureSuccessStatusCode();
        var session = (await verify.Content.ReadFromJsonAsync<JsonObject>())!;
        client.DefaultRequestHeaders.Authorization = new("Bearer", session["access_token"]!.GetValue<string>());
        (await client.PutAsJsonAsync("/api/v1/profiles/me", new { name, phone, company = "", role = "nakliyeci", city = "İstanbul" })).EnsureSuccessStatusCode();
        return client;
    }

    private static async Task<JsonObject> Post(HttpClient client, string path, object body)
    {
        var response = await client.PostAsJsonAsync(path, body);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<JsonObject>())!;
    }

    [Theory]
    [InlineData("yuk")]
    [InlineData("makine")]
    [InlineData("malzeme")]
    [InlineData("personel")]
    [InlineData("sicil")]
    public async Task PendingOfferUpdateAndAcceptanceRetainPaymentAndDetails(string kind)
    {
        using var owner = await Login("+905551100101", "İlan sahibi");
        using var other = await Login("+905551100102", "Teklif veren");
        var listingId = Guid.NewGuid();
        var date = DateTime.UtcNow.AddDays(1).ToString("yyyy-MM-dd");
        object listing = kind switch
        {
            "yuk" => new { from_city = "İstanbul", to_city = "Ankara", cargo = "Test yükü", tons = 10m, vehicle = "tir", price = 3000m, load_date = date, note = "", status = "active" },
            "makine" => new { type = "ekskavator", model = "Test makine", capacity = "20 ton", city = "İstanbul", lat = 41m, lng = 29m, hourly = 500m, daily = 3000m, available = true, with_operator = true, note = "", status = "active" },
            "malzeme" => new { kind = "agrega", product = "Mıcır", unit = "ton", price = 100m, stock = "bol", plant_name = "Test tesis", city = "İstanbul", lat = 41m, lng = 29m, delivery = true, min_qty = 10m, note = "", status = "active" },
            "personel" => new { title = "Test operatör aranıyor", role = "ekskavatorOp", city = "İstanbul", wage = 500m, wage_period = "Günlük", duration = "1 ay", requirements = new[] { "MYK" }, note = "", status = "active" },
            _ => new { role = "ekskavatorOp", city = "İstanbul", years = 5, certificates = new[] { "MYK" }, available = true, about = "Deneyimli operatör", status = "active" }
        };
        (await owner.PutAsJsonAsync($"/api/v1/listings/{kind}/{listingId}", listing)).EnsureSuccessStatusCode();
        await Post(other, $"/api/v1/listings/{kind}/{listingId}/unlock", new { use_credit = false });
        var amount = kind switch { "personel" => 0m, "malzeme" => 1000m, "sicil" => 2000m, _ => 3000m };
        var quantity = kind switch { "personel" => 0m, "yuk" or "malzeme" => 10m, _ => 1m };
        var unit = kind switch { "personel" => "", "yuk" or "malzeme" => "ton", "makine" => "gün", _ => "Günlük" };
        var draft = new JsonObject { ["kind"] = kind, ["listing_id"] = listingId.ToString(), ["amount"] = amount, ["quantity"] = quantity, ["unit"] = unit,
            ["start_date"] = kind == "personel" ? null : date, ["address"] = "Test şantiyesi", ["note"] = "İlk teklif" };
        other.DefaultRequestHeaders.Add("Idempotency-Key", Guid.NewGuid().ToString());
        var first = await Post(other, "/api/v1/requests", draft);
        draft["note"] = "Güncellenen teklif";
        other.DefaultRequestHeaders.Remove("Idempotency-Key");
        other.DefaultRequestHeaders.Add("Idempotency-Key", Guid.NewGuid().ToString());
        var updated = await Post(other, "/api/v1/requests", draft);
        var retried = await Post(other, "/api/v1/requests", draft);
        Assert.Equal(first["id"]!.ToString(), updated["id"]!.ToString());
        Assert.Equal(updated["id"]!.ToString(), retried["id"]!.ToString());
        Assert.Equal("Güncellenen teklif", updated["note"]!.GetValue<string>());
        other.DefaultRequestHeaders.Remove("Idempotency-Key");
        var requests = (await other.GetFromJsonAsync<JsonObject>("/api/v1/requests"))!["items"]!.AsArray();
        Assert.Single(requests);

        var accepted = await Post(owner, $"/api/v1/requests/{first["id"]}/respond", new { accept = true });
        var deal = (await owner.GetFromJsonAsync<JsonObject>("/api/v1/deals"))!["items"]!.AsArray().Single()!.AsObject();
        Assert.Equal(accepted["deal_id"]!.ToString(), deal["id"]!.ToString());
        Assert.Contains("Adres: Test şantiyesi", deal["details"]!.GetValue<string>());
        Assert.Contains("Not: Güncellenen teklif", deal["details"]!.GetValue<string>());
        if (quantity > 0) Assert.Contains("Miktar: ", deal["details"]!.GetValue<string>());
        if (kind != "personel") Assert.Contains("Tarih: ", deal["details"]!.GetValue<string>());
        var milestones = deal["milestones"]!.AsArray();
        if (amount == 0) Assert.Empty(milestones);
        else
        {
            Assert.Single(milestones); Assert.Equal(amount, milestones[0]!["amount"]!.GetValue<decimal>());
            var payer = kind is "yuk" or "personel" ? owner : other;
            var receiver = kind is "yuk" or "personel" ? other : owner;
            await Post(payer, $"/api/v1/deals/{deal["id"]}/actions", new { action = "mark_paid", index = 0, note = "" });
            var received = await Post(receiver, $"/api/v1/deals/{deal["id"]}/actions", new { action = "mark_received", index = 0, note = "" });
            Assert.NotNull(received["milestones"]![0]!["received_at"]);
        }
    }

    [Theory]
    [InlineData(false, false)]
    [InlineData(true, false)]
    [InlineData(false, true)]
    public async Task ManualDealAcceptsOriginalCodeAndLateSoloJoin(bool started, bool legacyCode)
    {
        using var creator = await Login("+905551100111", "Kaydı oluşturan");
        using var other = await Login("+905551100112", "Sonradan katılan");
        var deal = await Post(creator, "/api/v1/deals", new { title = "Elle test anlaşması", i_am_customer = true, counterparty_name = "Test firma", amount = 1000m,
            payment_method = "havale", details = "Test işi", payment_terms = "Teslimde", start_date = "2026-10-15",
            milestones = new[] { new { title = "Toplam bedel", amount = 1000m } } });
        var id = Guid.Parse(deal["id"]!.GetValue<string>());
        var code = deal["code"]!.GetValue<string>();
        Assert.Equal(8, code.Length);
        if (legacyCode)
        {
            using var scope = _factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var row = await db.Deals.SingleAsync(x => x.Id == id); row.Code = code = "ABCDEFGH23"; await db.SaveChangesAsync();
        }
        if (started) await Post(creator, $"/api/v1/deals/{id}/actions", new { action = "confirm", note = "" });
        var opened = await Post(creator, "/api/v1/deals/join", new { code });
        Assert.Equal(id.ToString(), opened["id"]!.GetValue<string>());
        var joined = await Post(other, "/api/v1/deals/join", new { code = code.ToLowerInvariant() });
        Assert.Equal(started ? "active" : "pending", joined["status"]!.GetValue<string>());
        Assert.Equal("Sonradan katılan", joined["provider_name"]!.GetValue<string>());
        Assert.Contains(joined["log"]!.AsArray(), x => x!["text"]!.GetValue<string>() == "Anlaşmaya katıldı");
        var again = await Post(other, "/api/v1/deals/join", new { code });
        Assert.Equal(id.ToString(), again["id"]!.GetValue<string>());
        if (!started)
        {
            var confirmed = await Post(other, $"/api/v1/deals/{id}/actions", new { action = "confirm", note = "" });
            Assert.Equal("active", confirmed["status"]!.GetValue<string>());
        }
    }
}

using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Infrastructure;
using SantiyeAgi.Api.Services;

namespace SantiyeAgi.Api.Endpoints;

public static class ApiEndpoints
{
    public static Guid Actor(HttpContext c) => Guid.Parse(c.User.FindFirst("sub")!.Value);
    public static Guid? Operation(HttpContext c)
    {
        var value = c.Request.Headers["Idempotency-Key"].ToString();
        if (value.Length == 0) return null;
        return Guid.TryParse(value, out var id) && id != Guid.Empty ? id : throw new ApiError("BAD_INPUT", detail: "Geçersiz işlem kimliği.");
    }
    public static void MapApi(this WebApplication app)
    {
        var api = app.MapGroup("/api/v1").RequireAuthorization().RequireRateLimiting("api");
        api.MapGet("/profiles/me", (HttpContext c, MarketService m) => m.MyProfile(Actor(c)));
        api.MapGet("/profiles/me/phone", async (HttpContext c, MarketService m) => new JsonObject { ["phone"] = (await m.User(Actor(c))).Phone });
        api.MapPut("/profiles/me", (HttpContext c, JsonObject j, MarketService m) => m.SaveProfile(Actor(c), j, Operation(c)));
        api.MapGet("/profiles/{id:guid}", async (Guid id, MarketService m) => (await m.Profiles([id])).GetValueOrDefault(id));
        api.MapPost("/profiles/query", async (JsonObject j, MarketService m) =>
        {
            var ids = j["ids"]?.AsArray() ?? throw new ApiError("BAD_INPUT");
            if (ids.Count > 200) throw new ApiError("BAD_INPUT");
            return new JsonArray((await m.Profiles(ids.Select(x => Guid.Parse(x!.GetValue<string>())))).Values.Select(x => (JsonNode)x).ToArray());
        });
        api.MapGet("/profiles/{id:guid}/ratings", async (Guid id, AppDbContext db) =>
        {
            var rows = await db.Ratings.AsNoTracking().Where(x => x.ToId == id).OrderByDescending(x => x.CreatedAt).Take(100).ToListAsync();
            var from = rows.Where(x => x.FromId != null).Select(x => x.FromId!.Value).ToArray();
            var names = await db.Users.Where(x => from.Contains(x.Id)).ToDictionaryAsync(x => x.Id, x => x.Name);
            return new JsonArray(rows.Select(x => (JsonNode)new JsonObject { ["id"] = x.Id.ToString(), ["deal_id"] = x.DealId.ToString(), ["from_id"] = x.FromId?.ToString() ?? "",
                ["to_id"] = x.ToId.ToString(), ["from_name"] = x.FromId is null ? "Silinen kullanıcı" : names.GetValueOrDefault(x.FromId.Value, "Kullanıcı"), ["stars"] = x.Stars, ["comment"] = x.Comment, ["created_at"] = x.CreatedAt }).ToArray());
        });
        api.MapGet("/usage", (HttpContext c, MarketService m) => m.Usage(Actor(c)));
        api.MapGet("/ratings/mine", async (HttpContext c, AppDbContext db) => await db.Ratings.Where(x => x.FromId == Actor(c)).Select(x => x.DealId).ToListAsync());
        api.MapGet("/listings/{kind}", (HttpContext c, string kind, int? page, int? pageSize, MarketService m) => m.Listings(Actor(c), kind, page ?? 1, pageSize ?? 100));
        api.MapPut("/listings/{kind}/{id:guid}", (HttpContext c, string kind, Guid id, JsonObject j, MarketService m) => m.SaveListing(Actor(c), kind, id, j, Operation(c)));
        api.MapPut("/listings/{kind}/{id:guid}/status", (HttpContext c, string kind, Guid id, JsonObject j, MarketService m) => m.ListingStatus(Actor(c), kind, id, j, Operation(c)));
        api.MapDelete("/listings/{kind}/{id:guid}", (HttpContext c, string kind, Guid id, MarketService m) => m.DeleteListing(Actor(c), kind, id, Operation(c)));
        api.MapPut("/machines/{id:guid}/availability", (HttpContext c, Guid id, JsonObject j, MarketService m) => m.Availability(Actor(c), id, j, Operation(c)));
        api.MapPost("/listings/{kind}/{id:guid}/boost", (HttpContext c, string kind, Guid id, JsonObject j, MarketService m) => m.Boost(Actor(c), kind, id, j, Operation(c)));
        api.MapPost("/listings/{kind}/{id:guid}/unlock", (HttpContext c, string kind, Guid id, JsonObject j, MarketService m) => m.Unlock(Actor(c), kind, id, j, Operation(c)));
        api.MapGet("/unlocks", async (HttpContext c, AppDbContext db) => await db.Unlocks.Where(x => x.UserId == Actor(c)).Select(x => x.Kind + ":" + x.ListingId).ToListAsync());
        api.MapGet("/contacts/{type}/{id:guid}", (HttpContext c, string type, Guid id, SafetyService s) => s.Contact(Actor(c), type, id));
        api.MapGet("/requests", (HttpContext c, int? page, TradeService s) => s.Requests(Actor(c), page ?? 1));
        api.MapPost("/requests", (HttpContext c, JsonObject j, TradeService s) => s.CreateRequest(Actor(c), j, Operation(c)));
        api.MapPost("/requests/{id:guid}/respond", (HttpContext c, Guid id, JsonObject j, TradeService s) => s.Respond(Actor(c), id, j, Operation(c)));
        api.MapPost("/requests/{id:guid}/withdraw", (HttpContext c, Guid id, TradeService s) => s.Withdraw(Actor(c), id, Operation(c)));
        api.MapGet("/deals", (HttpContext c, int? page, TradeService s) => s.Deals(Actor(c), page ?? 1));
        api.MapPost("/deals", (HttpContext c, JsonObject j, TradeService s) => s.CreateDeal(Actor(c), j, Operation(c)));
        api.MapPost("/deals/join", (HttpContext c, JsonObject j, TradeService s) => s.Join(Actor(c), j, Operation(c)));
        api.MapPost("/deals/{id:guid}/actions", (HttpContext c, Guid id, JsonObject j, TradeService s) => s.Action(Actor(c), id, j, Operation(c)));
        api.MapPost("/deals/{id:guid}/ratings", (HttpContext c, Guid id, JsonObject j, TradeService s) => s.Rate(Actor(c), id, j, Operation(c)));
        api.MapGet("/blocks", async (HttpContext c, AppDbContext db) => await db.Blocks.Where(x => x.BlockerId == Actor(c)).Select(x => x.BlockedId).ToListAsync());
        api.MapPut("/blocks/{id:guid}", (HttpContext c, Guid id, SafetyService s) => s.Block(Actor(c), id, true));
        api.MapDelete("/blocks/{id:guid}", (HttpContext c, Guid id, SafetyService s) => s.Block(Actor(c), id, false));
        api.MapPost("/reports", (HttpContext c, JsonObject j, SafetyService s) => s.Report(Actor(c), j, Operation(c)));
        api.MapGet("/notifications", async (HttpContext c, int? page, AppDbContext db) =>
        {
            if ((page ?? 1) < 1) throw new ApiError("BAD_INPUT");
            var rows = await db.Notifications.Where(x => x.UserId == Actor(c)).OrderByDescending(x => x.CreatedAt).ThenByDescending(x => x.Id).Skip(((page ?? 1) - 1) * 100).Take(100).ToListAsync();
            return new JsonArray(rows.Select(x => (JsonNode)new JsonObject { ["id"] = x.Id.ToString(), ["type"] = "info", ["title"] = x.Title, ["body"] = x.Body,
                ["ref_type"] = x.RefType, ["ref_id"] = x.RefId?.ToString(), ["read_at"] = x.ReadAt, ["created_at"] = x.CreatedAt }).ToArray());
        });
        api.MapPost("/notifications/read", async (HttpContext c, AppDbContext db) =>
        {
            await db.Notifications.Where(x => x.UserId == Actor(c) && x.ReadAt == null).ExecuteUpdateAsync(s => s.SetProperty(x => x.ReadAt, DateTimeOffset.UtcNow));
            return Results.NoContent();
        });
        api.MapDelete("/account", async (HttpContext c, SafetyService s) => { await s.DeleteAccount(Actor(c)); return Results.NoContent(); });
    }
}

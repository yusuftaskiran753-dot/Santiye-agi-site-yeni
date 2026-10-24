using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Infrastructure;
using SantiyeAgi.Api.Services;

namespace SantiyeAgi.Api.Endpoints;

public static class HaulEndpoints
{
    public static void MapHaulPoints(this WebApplication app)
    {
        var api = app.MapGroup("/api/v1/haul-points").RequireAuthorization().RequireRateLimiting("api");
        api.MapGet("", async (HttpContext c, AppDbContext db) =>
        {
            var actor = ApiEndpoints.Actor(c);
            var points = await db.HaulPoints.AsNoTracking().Where(x => x.OwnerId == actor).OrderBy(x => x.CreatedAt).ThenBy(x => x.Id).ToListAsync();
            return new JsonArray(points.Select(p => (JsonNode)PointJson(p)).ToArray());
        });
        api.MapPut("/{id:guid}", (Guid id, JsonObject input, HttpContext c, AppDbContext db, Mutations mutations, MarketService market) =>
        {
            var actor = ApiEndpoints.Actor(c);
            return mutations.Run(actor, ApiEndpoints.Operation(c), "haul-save:" + id, input, async () =>
            {
                await market.ProfileUser(actor);
                if (id == Guid.Empty || input.Bool("demo")) throw new ApiError("BAD_INPUT");
                var point = await db.HaulPoints.FindAsync(id);
                if (point is not null && point.OwnerId != actor) throw new ApiError("FORBIDDEN", 403);
                if (point is null && await db.HaulPoints.CountAsync(x => x.OwnerId == actor) >= 200) throw new ApiError("QUOTA");
                input.Choice("kind", "excavation", "dump", "source");
                input.CheckNumber("lat", -90, 90); input.CheckNumber("lng", -180, 180);
                foreach (var key in new[] { "volume", "feePerM3", "needM3" }) input.CheckNumber(key, 0, 1000000000);
                var data = new JsonObject { ["name"] = input.RequiredText("name", 2, 120), ["kind"] = input.Text("kind"),
                    ["lat"] = input.Number("lat"), ["lng"] = input.Number("lng"), ["volume"] = input.Number("volume"),
                    ["feePerM3"] = input.Number("feePerM3"), ["needM3"] = input.Number("needM3"), ["material"] = input.RequiredText("material", 0, 120) };
                if (point is null) db.HaulPoints.Add(point = new() { Id = id, OwnerId = actor });
                point.Data = data.ToJsonString();
                return PointJson(point);
            }, id);
        });
        api.MapDelete("/{id:guid}", (Guid id, HttpContext c, AppDbContext db, Mutations mutations) =>
        {
            var actor = ApiEndpoints.Actor(c);
            return mutations.Run(actor, ApiEndpoints.Operation(c), "haul-delete:" + id, new(), async () =>
            {
                var point = await db.HaulPoints.FindAsync(id);
                if (point is null) return null;
                if (point.OwnerId != actor) throw new ApiError("FORBIDDEN", 403);
                db.HaulPoints.Remove(point);
                return null;
            }, id);
        });
    }
    private static JsonObject PointJson(HaulPoint point)
    {
        var row = JsonFields.Object(point.Data);
        row["id"] = point.Id.ToString(); row["demo"] = false;
        return row;
    }
}

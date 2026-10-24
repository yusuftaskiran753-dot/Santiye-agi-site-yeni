using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Endpoints;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.Services.Push;

public static class PushEndpoints
{
    public static void MapPush(this WebApplication app)
    {
        var group = app.MapGroup("/api/v1/push/devices").RequireAuthorization().RequireRateLimiting("api");
        group.MapPut("/{installationId:guid}", Register);
        group.MapDelete("/{installationId:guid}", async (Guid installationId, HttpContext context, AppDbContext db) =>
        {
            var actor = ApiEndpoints.Actor(context);
            await db.Set<PushDevice>().Where(x => x.UserId == actor && x.InstallationId == installationId).ExecuteDeleteAsync();
            return Results.NoContent();
        });
    }

    private static async Task<IResult> Register(Guid installationId, HttpContext context, JsonObject input, AppDbContext db)
    {
        if (installationId == Guid.Empty) throw new ApiError("BAD_INPUT");
        var token = input.RequiredText("token", 20, 4096);
        if (token.Any(char.IsWhiteSpace) || token.Any(char.IsControl)) throw new ApiError("BAD_INPUT");
        var platform = input.Text("platform");
        if (platform is not "android" and not "ios") throw new ApiError("BAD_INPUT");
        var actor = ApiEndpoints.Actor(context); var session = Guid.Parse(context.User.FindFirst("sid")!.Value);
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));
        await using var transaction = await db.Database.BeginTransactionAsync();
        // Shared token lock also serializes switching accounts on the same device.
        foreach (var key in new[] { "push-token:" + hash, "push-user:" + actor }.Order())
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({key}, 0))");
        await db.Set<PushDevice>().Where(x => x.TokenHash == hash && x.UserId != actor).ExecuteDeleteAsync();
        var device = await db.Set<PushDevice>().SingleOrDefaultAsync(x => x.UserId == actor && x.InstallationId == installationId);
        var deviceId = device?.Id ?? Guid.Empty;
        await db.Set<PushDevice>().Where(x => x.TokenHash == hash && x.Id != deviceId).ExecuteDeleteAsync();
        if (device is null)
        {
            if (await db.Set<PushDevice>().CountAsync(x => x.UserId == actor) >= 10) throw new ApiError("LIMIT", 409, "En fazla 10 cihaz kaydedilebilir.");
            db.Set<PushDevice>().Add(device = new() { UserId = actor, InstallationId = installationId });
        }
        // A token refresh within the same session retains queued notifications;
        // a different login session starts a new recipient association.
        if (device.SessionId != session) device.RegisteredAt = DateTimeOffset.UtcNow;
        device.Token = token; device.TokenHash = hash; device.SessionId = session; device.Platform = platform;
        await db.SaveChangesAsync(); await transaction.CommitAsync();
        return Results.NoContent();
    }
}

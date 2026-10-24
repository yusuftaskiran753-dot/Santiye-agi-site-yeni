using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Infrastructure;
using SantiyeAgi.Api.Services;

namespace SantiyeAgi.Api.LiveLocation;

public sealed class LiveLocationService(AppDbContext db, Mutations mutations, MarketService market, TimeProvider clock)
{
    private DateTimeOffset Now => clock.GetUtcNow();

    private async Task<Deal> Deal(Guid actor, Guid id)
    {
        await market.ProfileUser(actor);
        var deal = await db.Deals.AsNoTracking().SingleOrDefaultAsync(x => x.Id == id) ?? throw new ApiError("NOT_FOUND", 404);
        if (deal.CustomerId != actor && deal.ProviderId != actor) throw new ApiError("FORBIDDEN", 403);
        return deal;
    }

    private static Guid[] Resources(Deal deal) => new[] { deal.Id, deal.CustomerId ?? Guid.Empty, deal.ProviderId ?? Guid.Empty }
        .Where(x => x != Guid.Empty).ToArray();

    private static void SameParticipants(Deal initial, Deal current)
    {
        // Join may have changed the participants before the locks were acquired.
        // Never proceed with an incomplete user-lock set; let the client retry.
        if (initial.CustomerId != current.CustomerId || initial.ProviderId != current.ProviderId)
            throw new ApiError("BAD_STATE", 409, "Anlaşmanın tarafları değişti. Yenileyip tekrar deneyin.");
    }

    private static bool HasTwoParticipants(Deal deal) => deal.CustomerId is not null && deal.ProviderId is not null && deal.CustomerId != deal.ProviderId;
    private static bool IsOpen(Deal deal) => deal.Status is "active" or "delivered" or "disputed";
    private static bool Delivered(Deal deal) => deal.Status == "delivered" ||
        deal.Status == "disputed" && JsonFields.Object(deal.Data).Text("prev_status") == "delivered";

    private async Task Session(Guid actor, Guid? sessionId)
    {
        if (sessionId is not null && !await db.Sessions.AnyAsync(s => s.Id == sessionId && s.UserId == actor && s.RevokedAt == null && s.ExpiresAt > Now))
            throw new ApiError("AUTH_REQUIRED", 401);
    }

    public async Task<JsonNode?> Prepare(Guid actor, Guid dealId, Guid? sessionId = null)
    {
        var initial = await Deal(actor, dealId);
        return await mutations.Run(actor, null, "live-location-prepare", new(), async () =>
        {
            await Session(actor, sessionId);
            var deal = await Deal(actor, dealId);
            SameParticipants(initial, deal);
            if (!HasTwoParticipants(deal) || !IsOpen(deal)) throw new ApiError("BAD_STATE");
            await market.CheckBlock(deal.CustomerId!.Value, deal.ProviderId!.Value);
            if (await db.Users.CountAsync(x => x.Id == deal.CustomerId || x.Id == deal.ProviderId) != 2) throw new ApiError("BAD_STATE");
            var now = Now;
            if (Delivered(deal)) await StopForDeal(db, dealId, now, untilDeliveredOnly: true);
            await EraseExpired(db, now, dealId);
            var row = await db.Set<LiveLocationShare>().FindAsync(dealId, actor);
            if (row is null)
            {
                row = Tombstone(dealId, actor, now);
                db.Set<LiveLocationShare>().Add(row);
            }
            return new JsonObject { ["generation"] = row.Generation.ToString() };
        }, Resources(initial));
    }

    private static LiveLocationShare Tombstone(Guid dealId, Guid actor, DateTimeOffset now) => new()
    {
        DealId = dealId, UserId = actor, StartedAt = now, UpdatedAt = now,
        FixAt = now, ExpiresAt = now, StoppedAt = now
    };

    public async Task<JsonNode?> Put(Guid actor, Guid dealId, ShareLocationInput input, Guid? sessionId = null)
    {
        Validate(input, Now);
        var initial = await Deal(actor, dealId);
        return await mutations.Run(actor, null, "live-location", new(), async () =>
        {
            await Session(actor, sessionId);
            var deal = await Deal(actor, dealId);
            SameParticipants(initial, deal);
            if (!HasTwoParticipants(deal) || !IsOpen(deal)) throw new ApiError("BAD_STATE", detail: "Canlı konum yalnızca iki tarafı olan devam eden bir anlaşmada paylaşılabilir.");
            await market.CheckBlock(deal.CustomerId!.Value, deal.ProviderId!.Value);
            if (await db.Users.CountAsync(x => x.Id == deal.CustomerId || x.Id == deal.ProviderId) != 2) throw new ApiError("BAD_STATE");
            var now = Now;
            var explicitStart = input.Minutes is not null || input.UntilDelivered;
            var row = await db.Set<LiveLocationShare>().FindAsync(dealId, actor);
            var active = row is not null && row.StoppedAt is null && row.ExpiresAt > now && !(row.UntilDelivered && Delivered(deal));
            // A start is fenced by a server generation, never by a device clock.
            // DELETE and revocation rotate it even before the first fix exists.
            // A previously active expired row must first be prepared again.
            if (explicitStart && (row is null || input.Generation is null || input.Generation == Guid.Empty ||
                input.Generation != row.Generation || !active && row.StoppedAt is null))
                throw new ApiError("LOCATION_NOT_SHARING", 409, "Paylaşım hazırlığı geçersiz. Yeniden süre seçin.");
            if (input.Generation is not null && row is not null && input.Generation != row.Generation)
                throw new ApiError("LOCATION_NOT_SHARING", 409);
            if (!active && !explicitStart) throw new ApiError("LOCATION_NOT_SHARING", 409, "Paylaşım bitti. Yeniden başlatmak için süre seçin.");
            if (input.UntilDelivered && deal.Status != "active") throw new ApiError("BAD_STATE", detail: "Teslime kadar paylaşım yalnızca teslim edilmemiş işte başlatılabilir.");
            if (!active)
            {
                row!.StartedAt = now;
                row.ExpiresAt = now.AddMinutes(input.UntilDelivered ? 1440 : input.Minutes!.Value);
                row.UntilDelivered = input.UntilDelivered;
                row.StoppedAt = null;
                row.FixAt = DateTimeOffset.MinValue;
                var other = deal.CustomerId == actor ? deal.ProviderId!.Value : deal.CustomerId!.Value;
                market.Notify(other, "Canlı konum paylaşılıyor", "Anlaşmanın diğer tarafı konum paylaşımını başlattı.", "deal", dealId);
            }
            // Replayed start requests cannot prolong the timer or send another notification.
            // Older cached fixes cannot replace a newer one; bursts retain the last accepted fix.
            if (input.At > row!.FixAt && (!active || now - row.UpdatedAt >= TimeSpan.FromSeconds(3)))
            {
                row.Lat = input.Lat; row.Lng = input.Lng;
                row.Accuracy = input.Accuracy; row.Heading = input.Heading; row.Speed = input.Speed;
                row.FixAt = input.At.ToUniversalTime(); row.UpdatedAt = now;
            }
            return new JsonObject { ["expires_at"] = row.ExpiresAt };
        }, Resources(initial));
    }

    public async Task<JsonNode?> Get(Guid actor, Guid dealId, Guid? sessionId = null)
    {
        var initial = await Deal(actor, dealId);
        return await mutations.Run(actor, null, "live-location-read", new(), async () =>
        {
            await Session(actor, sessionId);
            var deal = await Deal(actor, dealId);
            SameParticipants(initial, deal);
            var now = Now;
            if (!HasTwoParticipants(deal) || !IsOpen(deal) || await market.Blocked(deal.CustomerId!.Value, deal.ProviderId!.Value))
            {
                await StopForDeal(db, dealId, now);
                return new JsonArray();
            }
            if (Delivered(deal)) await StopForDeal(db, dealId, now, untilDeliveredOnly: true);
            await EraseExpired(db, now, dealId);
            var rows = await db.Set<LiveLocationShare>().AsNoTracking()
                .Where(x => x.DealId == dealId && x.StoppedAt == null && x.ExpiresAt > now && x.Lat != null && x.Lng != null)
                .OrderBy(x => x.UserId).ToListAsync();
            return new JsonArray(rows.Select(x => (JsonNode)new JsonObject
            {
                ["deal_id"] = x.DealId.ToString(), ["user_id"] = x.UserId.ToString(),
                ["lat"] = x.Lat, ["lng"] = x.Lng, ["accuracy"] = x.Accuracy,
                ["heading"] = x.Heading, ["speed"] = x.Speed,
                ["started_at"] = x.StartedAt, ["updated_at"] = x.FixAt,
                ["expires_at"] = x.ExpiresAt, ["until_delivered"] = x.UntilDelivered
            }).ToArray());
        }, Resources(initial));
    }

    public async Task Stop(Guid actor, Guid dealId, Guid? sessionId = null)
    {
        var initial = await Deal(actor, dealId);
        await mutations.Run(actor, null, "live-location-stop", new(), async () =>
        {
            await Session(actor, sessionId);
            SameParticipants(initial, await Deal(actor, dealId));
            var rows = db.Set<LiveLocationShare>().Where(x => x.DealId == dealId && x.UserId == actor);
            if (await rows.AnyAsync()) await Clear(rows, Now);
            else db.Set<LiveLocationShare>().Add(Tombstone(dealId, actor, Now));
            return null;
        }, Resources(initial));
    }

    public static void Validate(ShareLocationInput input, DateTimeOffset now)
    {
        static bool InRange(double value, double min, double max) => double.IsFinite(value) && value >= min && value <= max;
        if (!InRange(input.Lat, -90, 90) || !InRange(input.Lng, -180, 180) ||
            input.Accuracy is double accuracy && !InRange(accuracy, 0, 100000) ||
            input.Heading is double heading && (!InRange(heading, 0, 360) || heading == 360) ||
            input.Speed is double speed && !InRange(speed, 0, 150) ||
            input.Minutes is not null and not 60 and not 480 ||
            input.UntilDelivered && input.Minutes is not null ||
            input.At < now.AddMinutes(-5) || input.At > now.AddMinutes(2))
            throw new ApiError("BAD_INPUT", detail: "Konum, doğruluk, hız, zaman veya paylaşım süresi geçersiz.");
    }

    // These hooks run inside the existing Trade/Safety mutations and their advisory locks.
    // The location participants take the same locks, so a late fix cannot resurrect revoked data.
    public static Task<int> StopForDeal(AppDbContext db, Guid dealId, DateTimeOffset now, bool untilDeliveredOnly = false) =>
        Clear(db.Set<LiveLocationShare>().Where(x => x.DealId == dealId && (!untilDeliveredOnly || x.UntilDelivered)), now);

    public static Task<int> StopBetween(AppDbContext db, Guid first, Guid second, DateTimeOffset now) =>
        Clear(db.Set<LiveLocationShare>().Where(x => db.Deals.Any(d => d.Id == x.DealId &&
            (d.CustomerId == first && d.ProviderId == second || d.CustomerId == second && d.ProviderId == first))), now);

    public static Task<int> StopForUser(AppDbContext db, Guid userId, DateTimeOffset now) =>
        Clear(db.Set<LiveLocationShare>().Where(x => x.UserId == userId || db.Deals.Any(d =>
            d.Id == x.DealId && (d.CustomerId == userId || d.ProviderId == userId))), now);

    public static Task<int> EraseExpired(AppDbContext db, DateTimeOffset now, Guid? dealId = null) =>
        Clear(db.Set<LiveLocationShare>().Where(x => x.StoppedAt == null && x.ExpiresAt <= now && (dealId == null || x.DealId == dealId)), now);

    private static Task<int> Clear(IQueryable<LiveLocationShare> rows, DateTimeOffset now)
    {
        var nextGeneration = Guid.NewGuid();
        return rows.ExecuteUpdateAsync(s => s
            .SetProperty(x => x.Generation, nextGeneration)
            .SetProperty(x => x.Lat, (double?)null).SetProperty(x => x.Lng, (double?)null)
            .SetProperty(x => x.Accuracy, (double?)null).SetProperty(x => x.Heading, (double?)null).SetProperty(x => x.Speed, (double?)null)
            .SetProperty(x => x.StoppedAt, x => x.StoppedAt ?? now).SetProperty(x => x.UpdatedAt, now));
    }
}

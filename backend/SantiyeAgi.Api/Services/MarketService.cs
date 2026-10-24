using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Domain;
using SantiyeAgi.Api.Infrastructure;
using SantiyeAgi.Api.Auth;

namespace SantiyeAgi.Api.Services;

public sealed class MarketService(AppDbContext db, Mutations mutations, IConfiguration config)
{
    public async Task<User> User(Guid id) => await db.Users.FindAsync(id) ?? throw new ApiError("AUTH_REQUIRED", 401);
    public async Task<User> ProfileUser(Guid id)
    {
        var user = await User(id);
        if (!user.ProfileComplete) throw new ApiError("BAD_INPUT", detail: "Önce profilinizi tamamlayın.");
        return user;
    }
    public async Task<bool> Blocked(Guid a, Guid b) => await db.Blocks.AnyAsync(x => (x.BlockerId == a && x.BlockedId == b) || (x.BlockerId == b && x.BlockedId == a));
    public async Task CheckBlock(Guid a, Guid b) { if (await Blocked(a, b)) throw new ApiError("BLOCKED", 403); }
    public async Task<Dictionary<Guid, JsonObject>> Profiles(IEnumerable<Guid> ids)
    {
        var keys = ids.Distinct().Take(250).ToArray();
        var users = await db.Users.AsNoTracking().Where(x => keys.Contains(x.Id) && x.ProfileComplete).ToListAsync();
        var ratings = await db.Ratings.Where(x => keys.Contains(x.ToId)).GroupBy(x => x.ToId).Select(x => new { Id = x.Key, Avg = x.Average(v => v.Stars), Count = x.Count() }).ToListAsync();
        var asCustomer = await db.Deals.Where(x => x.Status == "completed" && x.CustomerId != null && keys.Contains(x.CustomerId.Value)).GroupBy(x => x.CustomerId!.Value).Select(x => new { Id = x.Key, Count = x.Count() }).ToListAsync();
        var asProvider = await db.Deals.Where(x => x.Status == "completed" && x.ProviderId != null && keys.Contains(x.ProviderId.Value)).GroupBy(x => x.ProviderId!.Value).Select(x => new { Id = x.Key, Count = x.Count() }).ToListAsync();
        return users.ToDictionary(x => x.Id, x =>
        {
            var r = ratings.Find(v => v.Id == x.Id);
            return new JsonObject { ["id"] = x.Id.ToString(), ["name"] = x.Name, ["company"] = x.Company, ["role"] = x.Role, ["city"] = x.City,
                ["phone_verified"] = x.PhoneVerified, ["company_verified"] = false, ["rating_avg"] = r?.Avg ?? 0, ["rating_count"] = r?.Count ?? 0,
                ["deals_completed"] = (asCustomer.Find(v => v.Id == x.Id)?.Count ?? 0) + (asProvider.Find(v => v.Id == x.Id)?.Count ?? 0), ["premium_until"] = x.PremiumUntil, ["created_at"] = x.CreatedAt };
        });
    }
    public async Task<JsonNode?> MyProfile(Guid actor) => (await Profiles([actor])).GetValueOrDefault(actor);
    public Task<JsonNode?> SaveProfile(Guid actor, JsonObject input, Guid? op) => mutations.Run(actor, op, "profile", input, async () =>
    {
        var user = await User(actor);
        user.Name = input.RequiredText("name", 2, 80); user.Company = input.RequiredText("company", 0, 120);
        input.Choice("role", "nakliyeci", "yukSahibi", "makineSahibi", "muteahhit", "tedarikci", "personel");
        user.Role = input.Text("role"); user.City = input.RequiredText("city", 2, 40);
        var phone = input.RequiredText("phone", 13, 13);
        if (!System.Text.RegularExpressions.Regex.IsMatch(phone, @"^\+905\d{9}$")) throw new ApiError("BAD_INPUT");
        if (user.PhoneVerified && user.Phone != phone) throw new ApiError("FORBIDDEN", 403, "Doğrulanmış telefon bu formdan değiştirilemez.");
        if (!user.PhoneVerified)
        {
            if (AuthPolicy.RequiresPhone(config)) throw new ApiError("PHONE_REQUIRED", 403);
            // Yalnız kullanıcının beyanı: doğrulama rozeti veya SMS sahipliği verilmez.
            if (await db.Users.AnyAsync(x => x.Id != actor && x.Phone == phone))
                throw new ApiError("DUPLICATE", 409, "Bu telefon başka bir hesapta kayıtlı.");
            user.Phone = phone;
        }
        user.ProfileComplete = true;
        await db.SaveChangesAsync();
        return await MyProfile(actor);
    });
    public async Task<JsonObject> Usage(Guid actor)
    {
        var u = await ProfileUser(actor);
        var now = DateTimeOffset.UtcNow;
        var month = new DateTimeOffset(now.Year, now.Month, 1, 0, 0, 0, TimeSpan.Zero);
        return new() { ["free_used"] = await db.Unlocks.CountAsync(x => x.UserId == actor && x.Method == "free" && x.CreatedAt >= month),
            ["free_limit"] = 5, ["credits"] = u.Credits, ["premium_until"] = u.PremiumUntil, ["free_listing_limit"] = 5,
            ["active_listings"] = await db.Listings.CountAsync(x => x.OwnerId == actor && x.Status == "active"), ["boost_day_cost"] = 1, ["boost_week_cost"] = 5, ["announcement"] = "" };
    }
    public async Task<JsonObject> Listings(Guid actor, string kind, int page, int pageSize)
    {
        if (!ListingRules.Kinds.Contains(kind) || page < 1 || pageSize < 1 || pageSize > 100) throw new ApiError("BAD_INPUT");
        var blockedIds = await db.Blocks.Where(x => x.BlockerId == actor || x.BlockedId == actor).Select(x => x.BlockerId == actor ? x.BlockedId : x.BlockerId).ToListAsync();
        var query = db.Listings.AsNoTracking().Where(x => x.Kind == kind && (x.OwnerId == actor || (!x.Hidden && x.Status == "active" && !blockedIds.Contains(x.OwnerId))));
        var rows = await query.OrderByDescending(x => x.CreatedAt).ThenByDescending(x => x.Id).Skip((page - 1) * pageSize).Take(pageSize + 1).ToListAsync();
        var owners = await Profiles(rows.Select(x => x.OwnerId));
        var items = new JsonArray();
        foreach (var listing in rows.Take(pageSize))
        {
            var data = JsonFields.Object(listing.Data);
            if (listing.Kind == "yuk" && listing.OwnerId != actor && !ListingRules.Available("yuk", data)) continue;
            var row = ListingJson(listing); row["owner"] = owners.GetValueOrDefault(listing.OwnerId)?.DeepClone(); items.Add(row);
        }
        return new() { ["items"] = items, ["page"] = page, ["has_more"] = rows.Count > pageSize };
    }
    public static JsonObject ListingJson(Listing listing)
    {
        var row = JsonFields.Object(listing.Data);
        row["id"] = listing.Id.ToString(); row["owner_id"] = listing.OwnerId.ToString(); row["status"] = listing.Status;
        row["hidden"] = listing.Hidden; row["boosted_until"] = listing.BoostedUntil; row["created_at"] = listing.CreatedAt; row["updated_at"] = listing.UpdatedAt;
        return row;
    }
    public async Task<Listing> Listing(Guid id, string? kind = null) => await db.Listings.SingleOrDefaultAsync(x => x.Id == id && (kind == null || x.Kind == kind)) ?? throw new ApiError("NOT_FOUND", 404);
    public Task<JsonNode?> SaveListing(Guid actor, string kind, Guid id, JsonObject input, Guid? op) => mutations.Run(actor, op, "listing:" + kind + ":" + id, input, async () =>
    {
        var user = await ProfileUser(actor);
        var data = ListingRules.Validate(kind, input);
        var row = await db.Listings.FindAsync(id);
        if (kind == "sicil" && row is null) row = await db.Listings.SingleOrDefaultAsync(x => x.OwnerId == actor && x.Kind == "sicil");
        if (row is not null && (row.OwnerId != actor || row.Kind != kind)) throw new ApiError("FORBIDDEN", 403);
        var opening = data.Text("status") == "active" && (row is null || row.Status != "active");
        if (opening && user.PremiumUntil <= DateTimeOffset.UtcNow || opening && user.PremiumUntil is null)
            if (await db.Listings.CountAsync(x => x.OwnerId == actor && x.Status == "active") >= 5) throw new ApiError("LISTING_LIMIT");
        if (row is null) db.Listings.Add(row = new() { Id = id, OwnerId = actor, Kind = kind });
        row.Data = data.ToJsonString(); row.Status = data.Text("status"); row.UpdatedAt = DateTimeOffset.UtcNow;
        var response = ListingJson(row); response["owner"] = (await MyProfile(actor))?.DeepClone(); return response;
    }, id);
    public Task<JsonNode?> ListingStatus(Guid actor, string kind, Guid id, JsonObject input, Guid? op) => mutations.Run(actor, op, "listing-status:" + id, input, async () =>
    {
        var row = await Listing(id, kind);
        if (row.OwnerId != actor) throw new ApiError("FORBIDDEN", 403);
        input.Choice("status", "active", "closed");
        var user = await ProfileUser(actor);
        if (row.Status != "active" && input.Text("status") == "active" && !(user.PremiumUntil > DateTimeOffset.UtcNow) && await db.Listings.CountAsync(x => x.OwnerId == actor && x.Status == "active") >= 5) throw new ApiError("LISTING_LIMIT");
        row.Status = input.Text("status"); row.UpdatedAt = DateTimeOffset.UtcNow;
        if (row.Status == "closed") await RejectOtherRequests(id);
        return null;
    }, id);
    public Task<JsonNode?> DeleteListing(Guid actor, string kind, Guid id, Guid? op) => mutations.Run(actor, op, "listing-delete:" + id, new(), async () =>
    {
        var row = await db.Listings.FindAsync(id);
        if (row is null) return null;
        if (row.OwnerId != actor || row.Kind != kind) throw new ApiError("FORBIDDEN", 403);
        await RejectOtherRequests(id); db.Listings.Remove(row); return null;
    }, id);
    public Task<JsonNode?> Availability(Guid actor, Guid id, JsonObject input, Guid? op) => mutations.Run(actor, op, "availability:" + id, input, async () =>
    {
        var row = await Listing(id, "makine");
        if (row.OwnerId != actor) throw new ApiError("FORBIDDEN", 403);
        if (input["available"] is null) throw new ApiError("BAD_INPUT");
        var data = JsonFields.Object(row.Data); data["available"] = input.Bool("available"); row.Data = data.ToJsonString(); row.UpdatedAt = DateTimeOffset.UtcNow; return null;
    }, id);
    public Task<JsonNode?> Boost(Guid actor, string kind, Guid id, JsonObject input, Guid? op) => mutations.Run(actor, op, "boost:" + id, input, async () =>
    {
        var row = await Listing(id, kind); var u = await ProfileUser(actor);
        if (row.OwnerId != actor) throw new ApiError("FORBIDDEN", 403);
        if (row.Status != "active" || row.Hidden) throw new ApiError("NOT_AVAILABLE");
        input.Choice("option", "day", "week"); var cost = input.Text("option") == "day" ? 1 : 5;
        if (u.Credits < cost) throw new ApiError("NO_CREDITS");
        u.Credits -= cost; db.CreditEntries.Add(new() { UserId = actor, Delta = -cost, Reason = "boost:" + id });
        row.BoostedUntil = (row.BoostedUntil > DateTimeOffset.UtcNow ? row.BoostedUntil.Value : DateTimeOffset.UtcNow).AddDays(cost == 1 ? 1 : 7);
        return new JsonObject { ["boosted_until"] = row.BoostedUntil };
    }, id);
    public Task<JsonNode?> Unlock(Guid actor, string kind, Guid id, JsonObject input, Guid? op) => mutations.Run(actor, op, "unlock:" + id, input, async () =>
    {
        var listing = await Listing(id, kind); var user = await ProfileUser(actor);
        await CheckBlock(actor, listing.OwnerId);
        var existing = await db.Unlocks.FindAsync(actor, id);
        string method;
        if (listing.OwnerId == actor) method = "own";
        else if (existing is not null) method = "already";
        else
        {
            if (listing.Hidden || listing.Status != "active" || !ListingRules.Available(kind, JsonFields.Object(listing.Data))) throw new ApiError("NOT_AVAILABLE");
            if (user.PremiumUntil > DateTimeOffset.UtcNow) method = "premium";
            else if (input.Bool("use_credit"))
            {
                if (user.Credits <= 0) throw new ApiError("NO_CREDITS");
                user.Credits--; method = "credit"; db.CreditEntries.Add(new() { UserId = actor, Delta = -1, Reason = "unlock:" + id });
            }
            else
            {
                var usage = await Usage(actor);
                if (usage["free_used"]!.GetValue<int>() >= 5) return new JsonObject { ["ok"] = false, ["reason"] = "QUOTA", ["credits"] = user.Credits };
                method = "free";
            }
            db.Unlocks.Add(new() { UserId = actor, ListingId = id, Kind = kind, Method = method });
        }
        return new JsonObject { ["ok"] = true, ["method"] = method, ["credits"] = user.Credits };
    }, id);
    public async Task RejectOtherRequests(Guid listingId, Guid? except = null)
    {
        var rows = await db.Requests.Where(x => x.ListingId == listingId && x.Status == "pending" && x.Id != except).ToListAsync();
        foreach (var row in rows) { row.Status = "rejected"; row.UpdatedAt = DateTimeOffset.UtcNow; Notify(row.RequesterId, "Talep kapatıldı", "İlan artık müsait değil.", "request", row.Id); }
    }
    public void Notify(Guid userId, string title, string body, string type, Guid id) => db.Notifications.Add(new() { UserId = userId, Title = title, Body = body, RefType = type, RefId = id });
}

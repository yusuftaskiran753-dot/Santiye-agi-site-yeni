using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Infrastructure;
using SantiyeAgi.Api.Billing;

namespace SantiyeAgi.Api.Services;

public sealed class SafetyService(AppDbContext db, Mutations mutations, MarketService market)
{
    public async Task<JsonObject> Contact(Guid actor, string type, Guid id)
    {
        Guid? other;
        if (type == "request")
        {
            var r = await db.Requests.FindAsync(id) ?? throw new ApiError("NOT_FOUND", 404);
            other = r.OwnerId == actor ? r.RequesterId : r.RequesterId == actor ? r.OwnerId : throw new ApiError("FORBIDDEN", 403);
        }
        else if (type == "deal")
        {
            var d = await db.Deals.FindAsync(id) ?? throw new ApiError("NOT_FOUND", 404);
            other = d.CustomerId == actor ? d.ProviderId : d.ProviderId == actor ? d.CustomerId : throw new ApiError("FORBIDDEN", 403);
        }
        else
        {
            var l = await market.Listing(id, type);
            if (l.OwnerId != actor && !await db.Unlocks.AnyAsync(x => x.UserId == actor && x.ListingId == id)) throw new ApiError("LOCKED");
            other = l.OwnerId;
        }
        if (other is null) return new() { ["user_id"] = "", ["name"] = "", ["phone"] = "" };
        await market.CheckBlock(actor, other.Value); var u = await market.User(other.Value);
        return new() { ["user_id"] = u.Id.ToString(), ["name"] = u.Name, ["phone"] = u.Phone, ["phone_verified"] = u.PhoneVerified };
    }
    public Task<JsonNode?> Block(Guid actor, Guid other, bool block) => mutations.Run(actor, null, "block", new(), async () =>
    {
        if (actor == other) throw new ApiError("BAD_INPUT"); await market.ProfileUser(other);
        var b = await db.Blocks.FindAsync(actor, other);
        if (block && b is null) db.Blocks.Add(new() { BlockerId = actor, BlockedId = other });
        else if (!block && b is not null) db.Blocks.Remove(b);
        if (block) await SantiyeAgi.Api.LiveLocation.LiveLocationService.StopBetween(db, actor, other, DateTimeOffset.UtcNow);
        return null;
    }, other);
    public Task<JsonNode?> Report(Guid actor, JsonObject input, Guid? op)
    {
        var id = input.Id("target_id");
        return mutations.Run(actor, op, "report", input, async () =>
        {
            var user = await market.ProfileUser(actor); var type = input.Text("target_type");
            if (type == "profil") { if (id == actor) throw new ApiError("BAD_INPUT"); await market.ProfileUser(id); }
            else if (type == "anlasma")
            {
                var deal = await db.Deals.FindAsync(id) ?? throw new ApiError("NOT_FOUND", 404);
                if (deal.CustomerId != actor && deal.ProviderId != actor) throw new ApiError("FORBIDDEN", 403);
            }
            else { var listing = await market.Listing(id, type); if (listing.OwnerId == actor) throw new ApiError("OWN_LISTING"); }
            if (await db.Reports.AnyAsync(x => x.ReporterId == actor && x.TargetId == id && x.TargetType == type)) return null;
            if (await db.Reports.CountAsync(x => x.ReporterId == actor && x.CreatedAt > DateTimeOffset.UtcNow.AddDays(-1)) >= 10) throw new ApiError("RATE_LIMIT", 429);
            db.Reports.Add(new() { ReporterId = actor, TargetId = id, TargetType = type, Reason = input.RequiredText("reason", 2, 60), Note = input.RequiredText("note", 0, 500) });
            if (user.CreatedAt < DateTimeOffset.UtcNow.AddHours(-24) && type is not "profil" and not "anlasma")
            {
                var count = await db.Reports.Join(db.Users, r => r.ReporterId, u => u.Id, (r, u) => new { r.TargetId, r.TargetType, u.CreatedAt }).CountAsync(x => x.TargetId == id && x.TargetType == type && x.CreatedAt < DateTimeOffset.UtcNow.AddHours(-24));
                if (count + 1 >= 3) (await market.Listing(id)).Hidden = true;
            }
            return null;
        }, id);
    }
    public async Task DeleteAccount(Guid actor)
    {
        await mutations.Run(actor, null, "account-delete", new(), async () =>
        {
            var user = await market.User(actor);
            await SantiyeAgi.Api.LiveLocation.LiveLocationService.StopForUser(db, actor, DateTimeOffset.UtcNow);
            await db.Set<StorePurchase>().Where(x => x.UserId == actor)
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.ProtectedReference, "").SetProperty(x => x.EntitledUntil, (DateTimeOffset?)null));
            var deals = await db.Deals.Where(x => x.CustomerId == actor || x.ProviderId == actor || x.CreatedBy == actor).ToListAsync();
            foreach (var d in deals)
            {
                var hadTwoParticipants = d.CustomerId is not null && d.ProviderId is not null;
                var data = JsonFields.Object(d.Data);
                if (d.CustomerId == actor) { d.CustomerId = null; data["customer_name"] = "Silinen kullanıcı"; }
                if (d.ProviderId == actor) { d.ProviderId = null; data["provider_name"] = "Silinen kullanıcı"; }
                if (d.CreatedBy == actor) d.CreatedBy = null;
                if (hadTwoParticipants && d.Status is "pending" or "active" or "delivered" or "disputed")
                {
                    d.Status = "cancelled"; data["status"] = "cancelled";
                    data["prev_status"] = null; d.UpdatedAt = DateTimeOffset.UtcNow;
                }
                // Serbest notlar kişisel veri içerebilir; silinen tarafın
                // kayıtları temizlenir. Bedel/durum ve karşı tarafın puanı korunur.
                data["details"] = ""; data["payment_terms"] = ""; data["log"] = new JsonArray();
                data["title"] = "Hesabı silinen kullanıcıyla yapılan işlem";
                if (data["milestones"] is JsonArray payments)
                    for (var i = 0; i < payments.Count; i++)
                        if (payments[i] is JsonObject payment) payment["title"] = $"Ödeme {i + 1}";
                data["customer_id"] = d.CustomerId?.ToString(); data["provider_id"] = d.ProviderId?.ToString(); data["created_by"] = d.CreatedBy?.ToString();
                data.Remove("cancel_requested_by"); data.Remove("disputed_by"); d.Data = data.ToJsonString();
                if (d.CustomerId is null && d.ProviderId is null)
                {
                    var ratings = await db.Ratings.Where(x => x.DealId == d.Id).ToListAsync();
                    db.Ratings.RemoveRange(ratings); db.Deals.Remove(d);
                }
            }
            var authoredRatings = await db.Ratings.Where(x => x.FromId == actor).ToListAsync();
            foreach (var rating in authoredRatings) rating.Comment = "";
            if (user.Phone is not null)
            {
                var challenge = await db.PhoneChallenges.FindAsync(user.Phone);
                if (challenge is not null) db.PhoneChallenges.Remove(challenge);
            }
            await db.SaveChangesAsync(); db.Users.Remove(user); return null;
        });
    }
}

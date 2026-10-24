using System.Security.Cryptography;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Domain;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.Services;

public sealed class TradeService(AppDbContext db, Mutations mutations, MarketService market)
{
    public static JsonObject RequestJson(TradeRequest r)
    {
        var j = JsonFields.Object(r.Data); j["id"] = r.Id.ToString(); j["kind"] = r.Kind; j["listing_id"] = r.ListingId.ToString();
        j["owner_id"] = r.OwnerId.ToString(); j["requester_id"] = r.RequesterId.ToString(); j["status"] = r.Status; j["deal_id"] = r.DealId?.ToString();
        j["created_at"] = r.CreatedAt; j["updated_at"] = r.UpdatedAt; return j;
    }
    public async Task<JsonObject> Requests(Guid actor, int page)
    {
        if (page < 1) throw new ApiError("BAD_INPUT");
        var rows = await db.Requests.AsNoTracking().Where(x => x.OwnerId == actor || x.RequesterId == actor).OrderByDescending(x => x.UpdatedAt).ThenByDescending(x => x.Id).Skip((page - 1) * 100).Take(101).ToListAsync();
        var profiles = await market.Profiles(rows.SelectMany(x => new[] { x.OwnerId, x.RequesterId }));
        var array = new JsonArray();
        foreach (var r in rows.Take(100)) { var j = RequestJson(r); j["owner"] = profiles.GetValueOrDefault(r.OwnerId)?.DeepClone(); j["requester"] = profiles.GetValueOrDefault(r.RequesterId)?.DeepClone(); array.Add(j); }
        return new() { ["items"] = array, ["has_more"] = rows.Count > 100 };
    }
    public Task<JsonNode?> CreateRequest(Guid actor, JsonObject input, Guid? op)
    {
        var listingId = input.Id("listing_id");
        return mutations.Run(actor, op, "request-create", input, async () =>
        {
            var u = await market.ProfileUser(actor); var listing = await market.Listing(listingId, input.Text("kind"));
            if (listing.OwnerId == actor) throw new ApiError("OWN_LISTING");
            await market.CheckBlock(actor, listing.OwnerId);
            if (listing.Hidden || listing.Status != "active" || !ListingRules.Available(listing.Kind, JsonFields.Object(listing.Data))) throw new ApiError("NOT_AVAILABLE");
            if (!await db.Unlocks.AnyAsync(x => x.UserId == actor && x.ListingId == listingId)) throw new ApiError("LOCKED");
            input.CheckNumber("amount", 0, 100000000); input.CheckNumber("quantity", 0, 100000000);
            var row = new JsonObject { ["amount"] = input.Number("amount"), ["quantity"] = input.Number("quantity"), ["unit"] = input.RequiredText("unit", 0, 20),
                ["start_date"] = input["start_date"]?.DeepClone(), ["address"] = input.RequiredText("address", 0, 300), ["note"] = input.RequiredText("note", 0, 500), ["listing_title"] = Title(listing, await market.User(listing.OwnerId)) };
            // Mobilde "Teklifi güncelle" aynı bekleyen talebi değiştirir. Kaynak
            // kilidi yeni talep ve çevrimdışı yeniden gönderimleri de seri tutar.
            var request = await db.Requests.SingleOrDefaultAsync(x => x.ListingId == listingId && x.RequesterId == actor && x.Status == "pending");
            var isNew = request is null;
            if (request is null)
            {
                request = new TradeRequest { OwnerId = listing.OwnerId, RequesterId = actor, ListingId = listingId, Kind = listing.Kind };
                db.Requests.Add(request);
            }
            request.Data = row.ToJsonString(); request.UpdatedAt = DateTimeOffset.UtcNow;
            market.Notify(listing.OwnerId, isNew ? "Yeni teklif / talep" : "Teklif / talep güncellendi", u.Name, "request", request.Id);
            return RequestJson(request);
        }, listingId);
    }
    public async Task<JsonNode?> Respond(Guid actor, Guid id, JsonObject input, Guid? op)
    {
        var initial = await db.Requests.AsNoTracking().SingleOrDefaultAsync(x => x.Id == id) ?? throw new ApiError("NOT_FOUND", 404);
        return await mutations.Run(actor, op, "request-respond:" + id, input, async () =>
        {
            var r = await db.Requests.FindAsync(id) ?? throw new ApiError("NOT_FOUND", 404);
            if (r.OwnerId != actor) throw new ApiError("FORBIDDEN", 403);
            if (r.Status != "pending") throw new ApiError("NOT_PENDING");
            var accept = input.Bool("accept");
            if (accept)
            {
                await market.CheckBlock(actor, r.RequesterId);
                var listing = await market.Listing(r.ListingId);
                if (listing.Hidden || listing.Status != "active" || !ListingRules.Available(listing.Kind, JsonFields.Object(listing.Data))) throw new ApiError("NOT_AVAILABLE");
                var requester = await market.ProfileUser(r.RequesterId); var owner = await market.ProfileUser(actor);
                var requesterIsProvider = r.Kind is "yuk" or "personel";
                var customer = requesterIsProvider ? owner : requester; var provider = requesterIsProvider ? requester : owner;
                var data = JsonFields.Object(r.Data);
                var details = new List<string>();
                if (data.Number("quantity") > 0)
                    details.Add("Miktar: " + data.Number("quantity").ToString("0.############################", System.Globalization.CultureInfo.InvariantCulture).Replace('.', ',') + " " + data.Text("unit"));
                if (DateOnly.TryParseExact(data.Text("start_date"), "yyyy-MM-dd", out var start)) details.Add("Tarih: " + start.ToString("dd.MM.yyyy"));
                if (data.Text("address") != "") details.Add("Adres: " + data.Text("address"));
                if (data.Text("note") != "") details.Add("Not: " + data.Text("note"));
                var milestones = new JsonArray();
                if (data.Number("amount") > 0)
                    milestones.Add(new JsonObject { ["title"] = "Toplam bedel", ["amount"] = data.Number("amount"), ["paid_at"] = null, ["received_at"] = null });
                var d = new Deal { Code = Code(), CustomerId = customer.Id, ProviderId = provider.Id, CreatedBy = actor, RequestId = r.Id, Status = "active" };
                d.Data = new JsonObject { ["kind"] = r.Kind, ["title"] = data.Text("listing_title"), ["details"] = string.Join('\n', details), ["customer_name"] = customer.Name,
                    ["provider_name"] = provider.Name, ["amount"] = data.Number("amount"), ["payment_method"] = "havale", ["payment_terms"] = "", ["start_date"] = data["start_date"]?.DeepClone(),
                    ["milestones"] = milestones, ["log"] = new JsonArray(new JsonObject { ["at"] = DateTimeOffset.UtcNow, ["by"] = owner.Name, ["text"] = "Teklif kabul edildi; anlaşma oluşturuldu" }) }.ToJsonString();
                db.Deals.Add(d); r.DealId = d.Id; r.Status = "accepted";
                if (r.Kind == "yuk") { listing.Status = "closed"; await market.RejectOtherRequests(listing.Id, r.Id); }
                market.Notify(r.RequesterId, "Teklifiniz kabul edildi", "Anlaşma kaydı oluşturuldu", "deal", d.Id);
            }
            else { r.Status = "rejected"; market.Notify(r.RequesterId, "Teklifiniz reddedildi", "", "request", r.Id); }
            r.UpdatedAt = DateTimeOffset.UtcNow;
            return new JsonObject { ["deal_id"] = r.DealId?.ToString() };
        }, id, initial.ListingId);
    }
    public Task<JsonNode?> Withdraw(Guid actor, Guid id, Guid? op) => mutations.Run(actor, op, "request-withdraw:" + id, new(), async () =>
    {
        var r = await db.Requests.FindAsync(id) ?? throw new ApiError("NOT_FOUND", 404);
        if (r.RequesterId != actor) throw new ApiError("FORBIDDEN", 403);
        if (r.Status == "withdrawn") return null;
        if (r.Status != "pending") throw new ApiError("NOT_PENDING");
        r.Status = "withdrawn"; r.UpdatedAt = DateTimeOffset.UtcNow; return null;
    }, id);
    public static string Code()
    {
        const string alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        return new string(Enumerable.Range(0, 8).Select(_ => alphabet[RandomNumberGenerator.GetInt32(alphabet.Length)]).ToArray());
    }
    public static JsonObject DealJson(Deal d)
    {
        var j = JsonFields.Object(d.Data); j["id"] = d.Id.ToString(); j["code"] = d.Code; j["customer_id"] = d.CustomerId?.ToString(); j["provider_id"] = d.ProviderId?.ToString();
        j["created_by"] = d.CreatedBy?.ToString(); j["request_id"] = d.RequestId?.ToString(); j["status"] = d.Status; j["created_at"] = d.CreatedAt; j["updated_at"] = d.UpdatedAt; return j;
    }
    public async Task<JsonObject> Deals(Guid actor, int page)
    {
        if (page < 1) throw new ApiError("BAD_INPUT");
        var rows = await db.Deals.AsNoTracking().Where(x => x.CustomerId == actor || x.ProviderId == actor || x.CreatedBy == actor).OrderByDescending(x => x.UpdatedAt).ThenByDescending(x => x.Id).Skip((page - 1) * 100).Take(101).ToListAsync();
        return new() { ["items"] = new JsonArray(rows.Take(100).Select(x => (JsonNode)DealJson(x)).ToArray()), ["has_more"] = rows.Count > 100 };
    }
    public Task<JsonNode?> CreateDeal(Guid actor, JsonObject input, Guid? op) => mutations.Run(actor, op, "deal-create", input, async () =>
    {
        var user = await market.ProfileUser(actor);
        var title = input.RequiredText("title", 2, 160); var other = input.RequiredText("counterparty_name", 2, 120);
        input.CheckNumber("amount", 0, 1000000000); input.Choice("payment_method", "havale", "nakit", "cek", "kart", "diger");
        var milestones = input["milestones"] as JsonArray ?? new();
        if (milestones.Count > 20) throw new ApiError("BAD_INPUT");
        foreach (var m in milestones) { var row = m!.AsObject(); row.RequiredText("title", 1, 120); row.CheckNumber("amount", 0, 1000000000); row.Remove("paid_at"); row.Remove("received_at"); }
        if (milestones.Sum(x => x!.AsObject().Number("amount")) > input.Number("amount")) throw new ApiError("BAD_INPUT", detail: "Ödeme planı toplam bedeli aşamaz.");
        var customer = input.Bool("i_am_customer");
        var d = new Deal { Code = Code(), CreatedBy = actor, CustomerId = customer ? actor : null, ProviderId = customer ? null : actor };
        d.Data = new JsonObject { ["kind"] = "diger", ["title"] = title, ["details"] = input.RequiredText("details", 0, 1500),
            ["customer_name"] = customer ? user.Name : other, ["provider_name"] = customer ? other : user.Name, ["amount"] = input.Number("amount"),
            ["payment_method"] = input.Text("payment_method"), ["payment_terms"] = input.RequiredText("payment_terms", 0, 300), ["start_date"] = input["start_date"]?.DeepClone(),
            ["milestones"] = milestones.DeepClone(), ["log"] = new JsonArray(new JsonObject { ["at"] = DateTimeOffset.UtcNow, ["by"] = user.Name, ["text"] = "Anlaşma kaydı oluşturuldu" }) }.ToJsonString();
        db.Deals.Add(d); return DealJson(d);
    });
    public async Task<JsonNode?> Join(Guid actor, JsonObject input, Guid? op)
    {
        // İlk mobil sürüm sekiz karakter kullanır. Önceki geliştirme
        // sürümünde üretilmiş on karakterli kodlar da açılabilsin.
        var code = input.RequiredText("code", 8, 10).ToUpperInvariant();
        if (code.Length is not 8 and not 10 || code.Any(ch => !"ABCDEFGHJKLMNPQRSTUVWXYZ23456789".Contains(ch))) throw new ApiError("BAD_INPUT");
        var initial = await db.Deals.AsNoTracking().SingleOrDefaultAsync(x => x.Code == code) ?? throw new ApiError("NOT_FOUND", 404);
        return await mutations.Run(actor, op, "deal-join", input, async () =>
        {
            var user = await market.ProfileUser(actor); var d = await db.Deals.FindAsync(initial.Id) ?? throw new ApiError("NOT_FOUND", 404);
            if (d.CustomerId == actor || d.ProviderId == actor) return DealJson(d);
            if (d.CreatedBy == actor || d.Status is not "pending" and not "active" || d.CustomerId is not null && d.ProviderId is not null) throw new ApiError("BAD_STATE");
            await market.CheckBlock(actor, d.CreatedBy!.Value);
            var row = JsonFields.Object(d.Data);
            if (d.CustomerId is null) { d.CustomerId = actor; row["customer_name"] = user.Name; } else { d.ProviderId = actor; row["provider_name"] = user.Name; }
            var log = row["log"] as JsonArray ?? new();
            log.Add(new JsonObject { ["at"] = DateTimeOffset.UtcNow, ["by"] = user.Name, ["text"] = "Anlaşmaya katıldı" });
            row["log"] = log;
            d.Data = row.ToJsonString(); d.UpdatedAt = DateTimeOffset.UtcNow;
            market.Notify(d.CreatedBy.Value, "Anlaşmaya katılım", user.Name, "deal", d.Id); return DealJson(d);
        }, initial.Id);
    }
    public Task<JsonNode?> Action(Guid actor, Guid id, JsonObject input, Guid? op) => mutations.Run(actor, op, "deal-action:" + id, input, async () =>
    {
        var d = await db.Deals.FindAsync(id) ?? throw new ApiError("NOT_FOUND", 404); var user = await market.ProfileUser(actor);
        if (d.CustomerId is not null && d.ProviderId is not null) await market.CheckBlock(d.CustomerId.Value, d.ProviderId.Value);
        var row = DealRules.Apply(DealJson(d), actor, user.Name, input.Text("action"), input["index"]?.GetValue<int>(), input.Text("note"));
        d.Data = row.ToJsonString(); d.Status = row.Text("status"); d.UpdatedAt = DateTimeOffset.UtcNow;
        if (d.Status is "completed" or "cancelled")
            await SantiyeAgi.Api.LiveLocation.LiveLocationService.StopForDeal(db, id, d.UpdatedAt);
        else if (d.Status == "delivered")
            await SantiyeAgi.Api.LiveLocation.LiveLocationService.StopForDeal(db, id, d.UpdatedAt, untilDeliveredOnly: true);
        var other = d.CustomerId == actor ? d.ProviderId : d.CustomerId;
        if (other is not null) market.Notify(other.Value, "Anlaşma güncellendi", row["log"]!.AsArray().Last()!.AsObject().Text("text"), "deal", id);
        return DealJson(d);
    }, id);
    public Task<JsonNode?> Rate(Guid actor, Guid id, JsonObject input, Guid? op) => mutations.Run(actor, op, "deal-rate:" + id, input, async () =>
    {
        var d = await db.Deals.FindAsync(id) ?? throw new ApiError("NOT_FOUND", 404);
        if (d.Status != "completed") throw new ApiError("BAD_STATE");
        if (d.CustomerId != actor && d.ProviderId != actor) throw new ApiError("FORBIDDEN", 403);
        var other = d.CustomerId == actor ? d.ProviderId : d.CustomerId;
        if (other is null) throw new ApiError("BAD_STATE");
        if (await db.Ratings.AnyAsync(x => x.DealId == id && x.FromId == actor)) throw new ApiError("ALREADY_RATED");
        input.CheckNumber("stars", 1, 5); if (input.Number("stars") != decimal.Truncate(input.Number("stars"))) throw new ApiError("BAD_INPUT");
        db.Ratings.Add(new() { DealId = id, FromId = actor, ToId = other.Value, Stars = (int)input.Number("stars"), Comment = input.RequiredText("comment", 0, 300) });
        market.Notify(other.Value, "Yeni değerlendirme", "Tamamlanan işiniz değerlendirildi", "deal", id); return null;
    }, id);
    private static string Title(Listing l, User owner)
    {
        var j = JsonFields.Object(l.Data);
        return l.Kind switch { "yuk" => j.Text("from_city") + " → " + j.Text("to_city"), "makine" => j.Text("model"), "malzeme" => j.Text("product"), "personel" => j.Text("title"), _ => owner.Name };
    }
}

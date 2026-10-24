using System.Text.Json.Nodes;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.Domain;

public static class DealRules
{
    public static JsonObject Apply(JsonObject source, Guid actor, string actorName, string action, int? index, string? note)
    {
        var row = (JsonObject)source.DeepClone(); var id = actor.ToString();
        var customer = row.Text("customer_id") == id; var provider = row.Text("provider_id") == id;
        var creator = row.Text("created_by") == id;
        if (!customer && !provider && !creator) throw new ApiError("FORBIDDEN", 403);
        var solo = creator && (row["customer_id"] is null || row["provider_id"] is null);
        var canC = customer || solo && row["customer_id"] is null;
        var canP = provider || solo && row["provider_id"] is null;
        var status = row.Text("status"); var now = DateTimeOffset.UtcNow;
        var clean = (note ?? "").Trim(); if (clean.Length > 300) throw new ApiError("BAD_INPUT");
        var milestones = row["milestones"] as JsonArray ?? new();
        var log = row["log"] as JsonArray ?? new();
        var text = "";
        static void Require(bool ok) { if (!ok) throw new ApiError("BAD_STATE"); }
        switch (action)
        {
            case "confirm":
                Require(status == "pending"); if (creator && !solo) throw new ApiError("WAITING_OTHER");
                row["status"] = "active"; text = "Anlaşma onaylandı"; break;
            case "reject":
                Require(status == "pending" && !creator); row["status"] = "cancelled"; text = "Anlaşma reddedildi"; break;
            case "cancel":
                Require(status is "pending" or "active" or "disputed");
                if (!solo && status != "pending" && row.Text("cancel_requested_by") != "")
                {
                    if (row.Text("cancel_requested_by") == id) throw new ApiError("WAITING_OTHER");
                    row["status"] = "cancelled"; row.Remove("cancel_requested_by"); text = "Karşılıklı onayla iptal edildi";
                }
                else if (!solo && status != "pending") { row["cancel_requested_by"] = id; text = "İptal talebi gönderildi; karşı tarafın onayı bekleniyor"; }
                else { row["status"] = "cancelled"; text = "Anlaşma iptal edildi"; }
                break;
            case "deliver": Require(canP && status == "active"); row["status"] = "delivered"; text = "İş tamamlandı / teslim edildi"; break;
            case "complete": Require(canC && status is "active" or "delivered"); row["status"] = "completed"; text = "Teslim alındı; anlaşma tamamlandı"; break;
            case "dispute":
                Require(status is "active" or "delivered"); row["prev_status"] = status; row["status"] = "disputed"; row["disputed_by"] = id; text = "Sorun bildirildi"; break;
            case "resolve":
                Require(status == "disputed");
                if (!solo && row.Text("disputed_by") != id) throw new ApiError("FORBIDDEN", 403, "Sorunu bildiren kişi çözümü onaylamalı.");
                row["status"] = row.Text("prev_status", "active"); row["prev_status"] = null; row.Remove("disputed_by"); text = "Sorunu bildiren taraf çözümü onayladı"; break;
            case "mark_paid": case "mark_received":
                Require(status is not "pending" and not "cancelled");
                if (index is null || index < 0 || index >= milestones.Count || action == "mark_paid" && !canC || action == "mark_received" && !canP) throw new ApiError("BAD_INPUT");
                var milestone = milestones[index.Value]!.AsObject();
                milestone["paid_at"] ??= JsonValue.Create(now);
                if (action == "mark_received") milestone["received_at"] ??= JsonValue.Create(now);
                text = milestone.Text("title") + (action == "mark_paid" ? " ödendi olarak işaretlendi" : " tahsil edildi olarak işaretlendi"); break;
            case "note": if (clean.Length == 0) throw new ApiError("BAD_INPUT"); text = "Not"; break;
            default: throw new ApiError("BAD_INPUT");
        }
        if (clean.Length != 0) text += ": " + clean;
        log.Add(new JsonObject { ["at"] = now, ["by"] = actorName, ["text"] = text });
        // Uzun süreli kayıtlar sonsuz büyümesin.
        while (log.Count > 500) log.RemoveAt(0);
        row["milestones"] = milestones; row["log"] = log; row["updated_at"] = now;
        return row;
    }
}

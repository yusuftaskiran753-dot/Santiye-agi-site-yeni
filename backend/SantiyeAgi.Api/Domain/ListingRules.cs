using System.Text.Json.Nodes;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.Domain;

public static class ListingRules
{
    public static readonly string[] Kinds = ["yuk", "makine", "malzeme", "personel", "sicil"];
    private static readonly string[] WorkerRoles = ["ekskavatorOp", "silindirOp", "greyderOp", "finiserOp", "vincOp", "tirSoforu", "ustabasi", "isci"];
    public static JsonObject Validate(string kind, JsonObject input)
    {
        if (!Kinds.Contains(kind)) throw new ApiError("BAD_INPUT");
        string[] fields = kind switch
        {
            "yuk" => ["from_city", "to_city", "cargo", "tons", "vehicle", "price", "load_date", "note", "status"],
            "makine" => ["type", "model", "capacity", "city", "lat", "lng", "hourly", "daily", "with_operator", "available", "note", "status"],
            "malzeme" => ["kind", "product", "unit", "price", "stock", "plant_name", "city", "lat", "lng", "delivery", "min_qty", "note", "status"],
            "personel" => ["title", "role", "city", "wage", "wage_period", "duration", "requirements", "note", "status"],
            _ => ["role", "city", "years", "certificates", "available", "about", "status"]
        };
        var row = new JsonObject();
        foreach (var key in fields) if (input.ContainsKey(key)) row[key] = input[key]?.DeepClone();
        row["status"] ??= "active";
        row.Choice("status", "active", "closed");
        foreach (var (key, max) in new[] { ("note", 500), ("about", 500), ("duration", 60), ("capacity", 100) })
            if (row.Text(key).Length > max) throw new ApiError("BAD_INPUT", detail: key);
        if (kind == "yuk")
        {
            row.RequiredText("from_city", 2, 40); row.RequiredText("to_city", 2, 40); row.RequiredText("cargo", 2, 120);
            row.CheckNumber("tons", 0.01m, 100000); row.CheckNumber("price", 0, 100000000);
            row.Choice("vehicle", "tir", "frigo", "damperli", "kirkayak", "lowbed", "kamyon", "kamyonet");
            if (!DateOnly.TryParseExact(row.Text("load_date"), "yyyy-MM-dd", out _)) throw new ApiError("BAD_INPUT");
        }
        else
        {
            row.RequiredText("city", 2, 40);
            if (kind is "makine" or "malzeme") { row.CheckNumber("lat", -90, 90); row.CheckNumber("lng", -180, 180); }
            if (kind == "makine")
            {
                row.RequiredText("model", 2, 80); row.CheckNumber("hourly", 0, 10000000); row.CheckNumber("daily", 0, 10000000);
                row.Choice("type", "ekskavator", "silindir", "greyder", "finiser", "loder", "bekoloder", "dozer", "vinc", "kamyon", "diger");
                row["available"] ??= true; row["with_operator"] ??= true;
            }
            else if (kind == "malzeme")
            {
                row.Choice("kind", "beton", "agrega", "stabilize", "asfalt", "diger"); row.Choice("stock", "bol", "az", "yok");
                row.RequiredText("product", 2, 80); row.RequiredText("unit", 1, 10); row.RequiredText("plant_name", 2, 120);
                row.CheckNumber("price", 0.01m, 10000000); row.CheckNumber("min_qty", 0, 100000000); row["delivery"] ??= true;
            }
            else
            {
                row.Choice("role", WorkerRoles);
                if (kind == "personel")
                {
                    row.RequiredText("title", 3, 120); row.CheckNumber("wage", 0, 10000000); row.Choice("wage_period", "Günlük", "Aylık", "Saatlik", "Götürü");
                    ValidateArray(row, "requirements");
                }
                else { row.CheckNumber("years", 0, 60); ValidateArray(row, "certificates"); row["available"] ??= true; }
            }
        }
        return row;
    }
    private static void ValidateArray(JsonObject row, string key)
    {
        if (row[key] is null) { row[key] = new JsonArray(); return; }
        if (row[key] is not JsonArray a || a.Count > 20 || a.Any(v => v is null || v.GetValue<string>().Length > 100)) throw new ApiError("BAD_INPUT", detail: key);
    }
    public static bool Available(string kind, JsonObject row) => kind switch
    {
        "makine" or "sicil" => row.Bool("available", true),
        "malzeme" => row.Text("stock") != "yok",
        "yuk" => DateOnly.ParseExact(row.Text("load_date"), "yyyy-MM-dd") >= DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, TimeZoneInfo.FindSystemTimeZoneById("Europe/Istanbul")).Date),
        _ => true
    };
}

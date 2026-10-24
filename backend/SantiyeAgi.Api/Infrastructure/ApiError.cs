using System.Text.Json.Nodes;

namespace SantiyeAgi.Api.Infrastructure;

public sealed class ApiError(string code, int status = 400, string? detail = null) : Exception(detail ?? code)
{
    public string Code { get; } = code;
    public int Status { get; } = status;
    public string? Detail { get; } = detail;
}
public static class JsonFields
{
    public static JsonObject Object(string json) => JsonNode.Parse(json)?.AsObject() ?? new();
    public static string Text(this JsonObject j, string key, string fallback = "") => j[key]?.GetValue<string>()?.Trim() ?? fallback;
    public static Guid Id(this JsonObject j, string key) => Guid.TryParse(j.Text(key), out var id) && id != Guid.Empty ? id : throw new ApiError("BAD_INPUT");
    public static bool Bool(this JsonObject j, string key, bool fallback = false) => j[key]?.GetValue<bool>() ?? fallback;
    public static decimal Number(this JsonObject j, string key, decimal fallback = 0)
    {
        if (j[key] is null) return fallback;
        if (decimal.TryParse(j[key]!.ToJsonString(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var value)) return value;
        throw new ApiError("BAD_INPUT", detail: key);
    }
    public static string RequiredText(this JsonObject j, string key, int min, int max)
    {
        var value = j.Text(key);
        var multiline = key is "note" or "details" or "payment_terms" or "comment";
        if (value.Length < min || value.Length > max || value.Any(ch => char.IsControl(ch) && !(multiline && ch is '\n' or '\r' or '\t'))) throw new ApiError("BAD_INPUT", detail: key);
        return value;
    }
    public static void CheckNumber(this JsonObject j, string key, decimal min, decimal max)
    {
        if (!j.ContainsKey(key) || j.Number(key) < min || j.Number(key) > max) throw new ApiError("BAD_INPUT", detail: key);
    }
    public static void Choice(this JsonObject j, string key, params string[] choices)
    {
        if (!choices.Contains(j.Text(key))) throw new ApiError("BAD_INPUT", detail: key);
    }
}

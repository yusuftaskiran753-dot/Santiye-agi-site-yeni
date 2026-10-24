using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.AI;

public sealed record AiInput(string Text, string City)
{
    public static AiInput Validate(string? text, string? city)
    {
        text = text?.Trim(); city = city?.Trim() ?? "";
        if (text is null || text.Length is < 2 or > 400 || text.Any(c => char.IsControl(c) && c is not '\n' and not '\r' and not '\t') ||
            city.Length > 40 || city.Any(char.IsControl)) throw new ApiError("BAD_INPUT");
        return new(text, AiValidation.City(city) ?? "");
    }

    public static async Task<AiInput> Read(HttpRequest request, CancellationToken cancellationToken)
    {
        if (!request.HasJsonContentType()) throw new ApiError("BAD_INPUT");
        if (request.ContentLength > 8192) throw new ApiError("BAD_INPUT", 413);
        var bytes = await AiValidation.ReadBounded(request.Body, 8192, cancellationToken);
        using var document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 4 });
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("text", out var text) || text.ValueKind != JsonValueKind.String)
            throw new ApiError("BAD_INPUT");
        string? city = null;
        if (root.TryGetProperty("city", out var value) && value.ValueKind != JsonValueKind.Null)
            city = value.ValueKind == JsonValueKind.String ? value.GetString() : throw new ApiError("BAD_INPUT");
        return Validate(text.GetString(), city);
    }
}

public static class AiValidation
{
    public static readonly string[] Vehicles = ["tir", "frigo", "damperli", "kirkayak", "lowbed", "kamyon", "kamyonet"];
    public static readonly string[] Machines = ["ekskavator", "silindir", "greyder", "finiser", "loder", "bekoloder", "dozer", "vinc", "kamyon", "diger"];
    public static readonly string[] Roles = ["ekskavatorOp", "silindirOp", "greyderOp", "finiserOp", "vincOp", "tirSoforu", "ustabasi", "isci"];
    private static readonly string[] Cities = ["Adana", "Adıyaman", "Afyonkarahisar", "Ağrı", "Aksaray", "Amasya", "Ankara", "Antalya", "Ardahan", "Artvin", "Aydın", "Balıkesir", "Bartın", "Batman", "Bayburt", "Bilecik", "Bingöl", "Bitlis", "Bolu", "Burdur", "Bursa", "Çanakkale", "Çankırı", "Çorum", "Denizli", "Diyarbakır", "Düzce", "Edirne", "Elazığ", "Erzincan", "Erzurum", "Eskişehir", "Gaziantep", "Giresun", "Gümüşhane", "Hakkari", "Hatay", "Iğdır", "Isparta", "İstanbul", "İzmir", "Kahramanmaraş", "Karabük", "Karaman", "Kars", "Kastamonu", "Kayseri", "Kırıkkale", "Kırklareli", "Kırşehir", "Kilis", "Kocaeli", "Konya", "Kütahya", "Malatya", "Manisa", "Mardin", "Mersin", "Muğla", "Muş", "Nevşehir", "Niğde", "Ordu", "Osmaniye", "Rize", "Sakarya", "Samsun", "Şanlıurfa", "Siirt", "Sinop", "Şırnak", "Sivas", "Tekirdağ", "Tokat", "Trabzon", "Tunceli", "Uşak", "Van", "Yalova", "Yozgat", "Zonguldak"];
    private static readonly StringComparer Turkish = StringComparer.Create(CultureInfo.GetCultureInfo("tr-TR"), true);

    public static string? City(string? city) => city is null ? null : Cities.FirstOrDefault(c => Turkish.Equals(c, city));

    public static JsonObject Sanitize(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Object) throw new ApiError("SERVER", 502);
        string? Text(string key, int max)
        {
            if (!value.TryGetProperty(key, out var item) || item.ValueKind != JsonValueKind.String) return null;
            var text = item.GetString()!.Trim();
            // Plain text only. Do not retain terminal/control characters, including bidi overrides.
            text = new string(text.Where(c => (!char.IsControl(c) || c is '\n' or '\t') && CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.Format).ToArray());
            if (text.Length == 0) return null;
            if (text.Length <= max) return text;
            return text[..(char.IsHighSurrogate(text[max - 1]) ? max - 1 : max)];
        }
        string? OneOf(string key, string[] allowed) => Text(key, 40) is { } item && allowed.Contains(item, StringComparer.Ordinal) ? item : null;
        decimal? Number(string key, decimal max)
        {
            if (!value.TryGetProperty(key, out var item) || item.ValueKind != JsonValueKind.Number || !item.TryGetDecimal(out var number)) return null;
            return number > 0 && number <= max ? number : null;
        }
        int? Day()
        {
            if (!value.TryGetProperty("gun", out var item) || item.ValueKind != JsonValueKind.Number || !item.TryGetInt32(out var day)) return null;
            return day is >= 0 and <= 365 ? day : null;
        }
        var intent = OneOf("intent", ["ara", "ilan_ver", "soru"]);
        var summary = Text("ozet", 160);
        if (intent is null || summary is null) throw new ApiError("SERVER", 502);
        return new JsonObject
        {
            ["intent"] = intent, ["kategori"] = OneOf("kategori", ["yuk", "makine", "malzeme", "personel"]),
            ["nereden"] = City(Text("nereden", 40)), ["nereye"] = City(Text("nereye", 40)), ["il"] = City(Text("il", 40)),
            ["arac"] = OneOf("arac", Vehicles), ["makine"] = OneOf("makine", Machines), ["malzeme"] = Text("malzeme", 40),
            ["pozisyon"] = OneOf("pozisyon", Roles), ["yuk_cinsi"] = Text("yuk_cinsi", 60),
            ["ton"] = Number("ton", 1000), ["fiyat"] = Number("fiyat", 100000000), ["gun"] = Day(),
            ["ozet"] = summary, ["cevap"] = intent == "soru" ? Text("cevap", 600) : null
        };
    }

    public static async Task<byte[]> ReadBounded(Stream stream, int maximum, CancellationToken cancellationToken)
    {
        using var output = new MemoryStream();
        var buffer = new byte[4096];
        while (true)
        {
            var read = await stream.ReadAsync(buffer.AsMemory(0, Math.Min(buffer.Length, maximum + 1 - (int)output.Length)), cancellationToken);
            if (read == 0) return output.ToArray();
            output.Write(buffer, 0, read);
            if (output.Length > maximum) throw new ApiError("BAD_INPUT", 413);
        }
    }
}

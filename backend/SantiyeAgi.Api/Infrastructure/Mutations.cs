using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using SantiyeAgi.Api.Data;

namespace SantiyeAgi.Api.Infrastructure;

// Aynı kullanıcı/işlem yeniden gönderildiğinde aynı sonuç döner.
// Ortak kaynak kilitleri sıralı alınarak teklif/anlaşma işlemleri seri hale gelir.
public sealed class Mutations(AppDbContext db)
{
    public async Task<JsonNode?> Run(Guid actor, Guid? opId, string kind, JsonObject input,
        Func<Task<JsonNode?>> action, params Guid[] resources)
    {
        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.ReadCommitted);
        foreach (var key in resources.Append(actor).Distinct().Order())
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({key.ToString()}, 0))");
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Canonical(input))));
        if (opId is not null && opId != Guid.Empty)
        {
            var previous = await db.Operations.FindAsync(actor, opId.Value);
            if (previous is not null)
            {
                if (previous.Kind != kind || previous.Fingerprint != hash) throw new ApiError("BAD_INPUT", detail: "İşlem kimliği farklı içerikle tekrar kullanılamaz.");
                return JsonNode.Parse(previous.Result);
            }
        }
        var result = await action();
        if (opId is not null && opId != Guid.Empty)
            db.Operations.Add(new() { UserId = actor, Id = opId.Value, Kind = kind, Fingerprint = hash, Result = result?.ToJsonString() ?? "null" });
        await db.SaveChangesAsync();
        await tx.CommitAsync();
        return result;
    }
    public static string Canonical(JsonNode? node) => node switch
    {
        JsonObject o => "{" + string.Join(",", o.OrderBy(x => x.Key, StringComparer.Ordinal).Select(x => System.Text.Json.JsonSerializer.Serialize(x.Key) + ":" + Canonical(x.Value))) + "}",
        JsonArray a => "[" + string.Join(",", a.Select(Canonical)) + "]",
        _ => node?.ToJsonString() ?? "null"
    };
}

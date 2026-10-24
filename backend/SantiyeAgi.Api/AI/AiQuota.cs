using System.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.AI;

public sealed class AiQuota(AppDbContext db, IOptions<AiOptions> options, TimeProvider clock)
{
    public async Task<Guid> Reserve(Guid actor, CancellationToken cancellationToken)
    {
        var config = options.Value;
        if (!config.IsConfigured) throw new ApiError("CONFIG", 503);
        await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.ReadCommitted, cancellationToken);
        // All application workers share the same short reservation lock. It is released
        // before any provider call; HTTP latency never holds a database transaction open.
        await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({"santiye-ai-budget-v1"}, 0))", cancellationToken);
        var now = clock.GetUtcNow();
        var day = new DateTimeOffset(now.UtcDateTime.Date, TimeSpan.Zero);
        var user = await db.Users.AsNoTracking().SingleOrDefaultAsync(x => x.Id == actor, cancellationToken)
            ?? throw new ApiError("AUTH_REQUIRED", 401);
        if (!user.ProfileComplete) throw new ApiError("BAD_STATE", detail: "Önce profilinizi tamamlayın.");
        var limit = user.PremiumUntil > now ? config.PremiumDailyLimit : config.DailyLimit;
        var rows = db.Set<AiUsage>();
        if (await rows.CountAsync(x => x.UserId == actor && x.CreatedAt >= day, cancellationToken) >= limit)
            throw new ApiError("QUOTA", 429, "Günlük yapay zekâ kullanım hakkınız doldu.");
        if (await rows.CountAsync(x => x.CreatedAt >= day, cancellationToken) >= config.GlobalDailyRequestLimit)
            throw new ApiError("RATE_LIMIT", 429, "Yapay zekâ yardımcısının günlük kullanım sınırı doldu.");
        if (await rows.CountAsync(x => x.LeaseUntil > now, cancellationToken) >= config.MaxConcurrency)
            throw new ApiError("RATE_LIMIT", 429, "Yapay zekâ yardımcısı meşgul. Kısa süre sonra tekrar deneyin.");
        var reservation = new AiUsage
        {
            UserId = actor, CreatedAt = now,
            LeaseUntil = now.AddSeconds(config.TimeoutSeconds + 10)
        };
        rows.Add(reservation);
        // Keep only quota metadata for the current UTC day plus a small operational
        // margin. Old leases from a crashed worker naturally expire without a job.
        await rows.Where(x => x.CreatedAt < day.AddDays(-2) && x.LeaseUntil < now)
            .ExecuteDeleteAsync(cancellationToken);
        await db.SaveChangesAsync(cancellationToken);
        await tx.CommitAsync(cancellationToken);
        return reservation.Id;
    }

    public async Task Release(Guid reservation)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        var now = clock.GetUtcNow();
        try
        {
            await db.Set<AiUsage>().Where(x => x.Id == reservation)
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.LeaseUntil, now), timeout.Token);
        }
        catch (Exception ex) when (ex is OperationCanceledException or Npgsql.NpgsqlException)
        {
            // Lease expiry is the recovery path; no prompt/key/response is logged.
        }
    }
}

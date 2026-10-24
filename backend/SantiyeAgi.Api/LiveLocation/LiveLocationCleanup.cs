using Microsoft.EntityFrameworkCore;
using SantiyeAgi.Api.Data;

namespace SantiyeAgi.Api.LiveLocation;

// Coordinate erasure runs every minute; the public API also erases before reading.
// Inactive metadata is retained at most seven days, without a route history.
public sealed class LiveLocationCleanup(IServiceScopeFactory scopes, TimeProvider clock, ILogger<LiveLocationCleanup> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(1), clock);
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if (!await timer.WaitForNextTickAsync(stoppingToken)) break;
                using var scope = scopes.CreateScope();
                await Purge(scope.ServiceProvider.GetRequiredService<AppDbContext>(), clock.GetUtcNow(), stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception e) { logger.LogWarning("Live location cleanup failed: {Type}", e.GetType().Name); }
        }
    }

    public static async Task Purge(AppDbContext db, DateTimeOffset now, CancellationToken ct = default)
    {
        await LiveLocationService.EraseExpired(db, now);
        var cutoff = now.AddDays(-7);
        await db.Set<LiveLocationShare>().Where(x => x.StoppedAt != null && x.StoppedAt < cutoff || x.ExpiresAt < cutoff).ExecuteDeleteAsync(ct);
    }
}

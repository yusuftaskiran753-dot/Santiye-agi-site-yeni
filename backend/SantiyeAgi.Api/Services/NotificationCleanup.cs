using Microsoft.EntityFrameworkCore;
using SantiyeAgi.Api.Data;

namespace SantiyeAgi.Api.Services;

public sealed class NotificationCleanup(IServiceScopeFactory scopes, ILogger<NotificationCleanup> log) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromHours(1));
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                using var scope = scopes.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var now = DateTimeOffset.UtcNow;
                await db.Notifications.Where(x => x.CreatedAt < now.AddDays(-90) || x.ReadAt != null && x.CreatedAt < now.AddDays(-30)).ExecuteDeleteAsync(stoppingToken);
                await db.PhoneChallenges.Where(x => x.ExpiresAt < now.AddDays(-1)).ExecuteDeleteAsync(stoppingToken);
                await db.Sessions.Where(x => x.ExpiresAt < now.AddDays(-1)).ExecuteDeleteAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception ex) { log.LogError(ex, "Scheduled cleanup failed"); }
        }
    }
}

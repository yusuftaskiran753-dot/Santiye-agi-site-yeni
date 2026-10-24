using Microsoft.EntityFrameworkCore;
using SantiyeAgi.Api.Auth;
using SantiyeAgi.Api.Data;

namespace SantiyeAgi.Api.Services.Push;

public sealed class PushDispatcher(AppDbContext db, IPushSender sender)
{
    public async Task<int> RunBatch(CancellationToken cancellationToken = default)
    {
        if (!sender.Configured) return 0;
        var now = DateTimeOffset.UtcNow;
        var pending = await db.Set<PushOutbox>().AsNoTracking().Where(x => x.ExpandedAt == null)
            .OrderBy(x => x.CreatedAt).Select(x => x.NotificationId).Take(25).ToListAsync(cancellationToken);
        foreach (var id in pending)
        {
            await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({"push-expand:" + id}, 0))", cancellationToken);
            var row = await db.Set<PushOutbox>().SingleOrDefaultAsync(x => x.NotificationId == id, cancellationToken);
            if (row is not null && row.ExpandedAt is null)
            {
                var notification = await db.Notifications.AsNoTracking().SingleOrDefaultAsync(x => x.Id == id, cancellationToken);
                if (notification is not null && notification.CreatedAt > now.AddHours(-24))
                {
                    var devices = await (from device in db.Set<PushDevice>()
                        join session in db.Sessions on device.SessionId equals session.Id
                        where device.UserId == notification.UserId && session.UserId == notification.UserId &&
                            session.RevokedAt == null && session.ExpiresAt > now && device.RegisteredAt <= notification.CreatedAt
                        select device.Id).ToListAsync(cancellationToken);
                    foreach (var device in devices) db.Set<PushDelivery>().Add(new() { NotificationId = id, DeviceId = device });
                }
                row.ExpandedAt = now;
                await db.SaveChangesAsync(cancellationToken);
            }
            await transaction.CommitAsync(cancellationToken);
        }

        now = DateTimeOffset.UtcNow;
        var jobs = await db.Set<PushDelivery>().AsNoTracking().Where(x => x.CompletedAt == null && x.NextAttemptAt <= now)
            .OrderBy(x => x.NextAttemptAt).Select(x => x.Id).Take(50).ToListAsync(cancellationToken);
        var sent = 0;
        foreach (var id in jobs)
        {
            await using var transaction = await db.Database.BeginTransactionAsync(cancellationToken);
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({"push-send:" + id}, 0))", cancellationToken);
            var job = await db.Set<PushDelivery>().SingleOrDefaultAsync(x => x.Id == id, cancellationToken);
            if (job is null || job.CompletedAt != null || job.NextAttemptAt > DateTimeOffset.UtcNow) { await transaction.CommitAsync(cancellationToken); continue; }
            var device = await db.Set<PushDevice>().AsNoTracking().SingleOrDefaultAsync(x => x.Id == job.DeviceId, cancellationToken);
            var notification = await db.Notifications.AsNoTracking().SingleOrDefaultAsync(x => x.Id == job.NotificationId, cancellationToken);
            if (device is null || notification is null || device.UserId != notification.UserId || notification.CreatedAt < device.RegisteredAt ||
                notification.CreatedAt < now.AddHours(-24) ||
                !await db.Sessions.AnyAsync(x => x.Id == device.SessionId && x.UserId == device.UserId && x.RevokedAt == null && x.ExpiresAt > now, cancellationToken))
            {
                job.CompletedAt = now; job.LastResult = "EXPIRED_OR_LOGGED_OUT";
            }
            else
            {
                var result = await sender.Send(device, notification, cancellationToken);
                job.Attempts++; job.LastResult = result.Code;
                switch (result.Kind)
                {
                    case PushResultKind.Success: job.CompletedAt = DateTimeOffset.UtcNow; sent++; break;
                    case PushResultKind.InvalidToken:
                        // Only a documented UNREGISTERED token response removes the
                        // token. A bad project/key/payload must not wipe all devices.
                        db.Entry(job).State = EntityState.Detached;
                        await db.Set<PushDevice>().Where(x => x.Id == device.Id && x.TokenHash == device.TokenHash).ExecuteDeleteAsync(cancellationToken);
                        break;
                    case PushResultKind.PermanentFailure: job.CompletedAt = DateTimeOffset.UtcNow; break;
                    default:
                        if (job.Attempts >= 8) job.CompletedAt = DateTimeOffset.UtcNow;
                        else job.NextAttemptAt = DateTimeOffset.UtcNow + (result.RetryAfter ?? RetryDelay(job.Attempts));
                        break;
                }
            }
            await db.SaveChangesAsync(cancellationToken); await transaction.CommitAsync(cancellationToken);
        }
        return sent;
    }

    public static TimeSpan RetryDelay(int attempts) => TimeSpan.FromSeconds(Math.Min(3600, 60 * Math.Pow(2, Math.Clamp(attempts - 1, 0, 10))));
}

public sealed class PushDispatchWorker(IServiceScopeFactory scopes, ILogger<PushDispatchWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Allows schema initialization/migrations to complete before first polling.
        await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
        var nextCleanup = DateTimeOffset.UtcNow;
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = scopes.CreateScope();
                await scope.ServiceProvider.GetRequiredService<PushDispatcher>().RunBatch(stoppingToken);
                if (DateTimeOffset.UtcNow >= nextCleanup)
                {
                    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                    var now = DateTimeOffset.UtcNow;
                    await db.Set<PushDelivery>().Where(x => x.CompletedAt < now.AddDays(-7)).ExecuteDeleteAsync(stoppingToken);
                    await db.Set<PushOutbox>().Where(x => x.CreatedAt < now.AddDays(-7)).ExecuteDeleteAsync(stoppingToken);
                    await db.Set<PushDevice>().Where(x => x.RegisteredAt < now.AddDays(-60) || !db.Sessions.Any(s => s.Id == x.SessionId && s.RevokedAt == null && s.ExpiresAt > now)).ExecuteDeleteAsync(stoppingToken);
                    await db.PhoneChallenges.Where(x => x.ExpiresAt < now.AddDays(-1)).ExecuteDeleteAsync(stoppingToken);
                    await db.Set<PhoneOtpQuota>().Where(x => x.LastAttemptAt < now.AddDays(-2)).ExecuteDeleteAsync(stoppingToken);
                    nextCleanup = now.AddHours(1);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { return; }
            catch (Exception error) { logger.LogWarning("Push queue iteration failed ({ErrorType}).", error.GetType().Name); }
            await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
        }
    }
}

public static class SmsPushRegistration
{
    public static IServiceCollection AddSmsAndPushServices(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddHttpClient("sms", client => client.Timeout = TimeSpan.FromSeconds(15))
            .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = false });
        services.AddHttpClient("push", client => client.Timeout = TimeSpan.FromSeconds(20))
            .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = false });
        services.AddSingleton<ISmsOtpSender, SmsOtpSender>();
        services.AddSingleton<IPushAccessTokenProvider, GooglePushAccessTokenProvider>();
        services.AddSingleton<IPushSender, FcmPushSender>();
        services.AddScoped<PushDispatcher>();
        services.AddHostedService<PushDispatchWorker>();
        return services;
    }
}

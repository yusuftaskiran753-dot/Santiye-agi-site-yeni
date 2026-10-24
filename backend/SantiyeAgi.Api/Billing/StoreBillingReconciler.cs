using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using SantiyeAgi.Api.Data;

namespace SantiyeAgi.Api.Billing;

public sealed class StoreBillingReconciler(IServiceScopeFactory scopes, IOptions<StoreBillingOptions> options, ILogger<StoreBillingReconciler> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!options.Value.Enabled) return;
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(1));
        var nextVoids = DateTimeOffset.MinValue;
        do
        {
            try
            {
                using var scope = scopes.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var now = DateTimeOffset.UtcNow;
                var ids = await db.Set<StorePurchase>().AsNoTracking().Where(x => x.UserId != null && x.ProtectedReference != "" && x.NextCheckAt <= now)
                    .OrderBy(x => x.NextCheckAt).Take(40).Select(x => x.Id).ToListAsync(stoppingToken);
                foreach (var id in ids)
                {
                    using var rowScope = scopes.CreateScope();
                    try { await rowScope.ServiceProvider.GetRequiredService<StoreBillingService>().Reconcile(id, stoppingToken); }
                    catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { return; }
                    catch (Exception e)
                    {
                        logger.LogWarning("Store reconciliation postponed for {Purchase}: {Type}", id, e.GetType().Name);
                        await rowScope.ServiceProvider.GetRequiredService<AppDbContext>().Set<StorePurchase>().Where(x => x.Id == id)
                            .ExecuteUpdateAsync(s => s.SetProperty(x => x.NextCheckAt, now.AddMinutes(15)), stoppingToken);
                    }
                }
                if (!string.IsNullOrWhiteSpace(options.Value.GoogleServiceAccountFile) && nextVoids <= now)
                {
                    nextVoids = now.AddMinutes(5); // Failed pages retry soon; successful sweeps run hourly.
                    await foreach (var item in scope.ServiceProvider.GetRequiredService<IStoreVerifier>().GoogleVoids(stoppingToken))
                    {
                        using var itemScope = scopes.CreateScope();
                        await itemScope.ServiceProvider.GetRequiredService<StoreBillingService>().ApplyGoogleVoid(item, stoppingToken);
                    }
                    nextVoids = now.AddHours(1);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { return; }
            catch (Exception e) { logger.LogWarning("Store billing reconciliation cycle postponed: {Type}", e.GetType().Name); }
        } while (await timer.WaitForNextTickAsync(stoppingToken));
    }
}

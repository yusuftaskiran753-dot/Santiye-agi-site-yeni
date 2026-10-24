using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using SantiyeAgi.Api.Auth;
using SantiyeAgi.Api.Data;

namespace SantiyeAgi.Api.Services.Push;

public sealed class PushDevice
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid InstallationId { get; set; }
    public Guid UserId { get; set; }
    public Guid SessionId { get; set; }
    public string Token { get; set; } = "";
    public string TokenHash { get; set; } = "";
    public string Platform { get; set; } = "";
    public DateTimeOffset RegisteredAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class PushOutbox
{
    public Guid NotificationId { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? ExpandedAt { get; set; }
}

public sealed class PushDelivery
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid NotificationId { get; set; }
    public Guid DeviceId { get; set; }
    public int Attempts { get; set; }
    public DateTimeOffset NextAttemptAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? CompletedAt { get; set; }
    public string LastResult { get; set; } = "";
}

public static class PushModel
{
    public static void Configure(ModelBuilder model)
    {
        model.Entity<PhoneOtpQuota>().ToTable("PhoneOtpQuotas");
        model.Entity<PushDevice>().ToTable("PushDevices");
        model.Entity<PushOutbox>().ToTable("PushOutbox");
        model.Entity<PushDelivery>().ToTable("PushDeliveries");
        model.Entity<PhoneOtpQuota>().HasKey(x => x.Phone);
        model.Entity<PhoneOtpQuota>().Property(x => x.Phone).HasMaxLength(20);
        model.Entity<PhoneOtpQuota>().HasIndex(x => x.LastAttemptAt);
        model.Entity<PushDevice>().HasIndex(x => new { x.UserId, x.InstallationId }).IsUnique();
        model.Entity<PushDevice>().HasIndex(x => x.TokenHash).IsUnique();
        model.Entity<PushDevice>().Property(x => x.TokenHash).HasMaxLength(64);
        model.Entity<PushDevice>().Property(x => x.Token).HasMaxLength(4096);
        model.Entity<PushDevice>().Property(x => x.Platform).HasMaxLength(10);
        model.Entity<PushDevice>().HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        model.Entity<PushDevice>().HasOne<Session>().WithMany().HasForeignKey(x => x.SessionId).OnDelete(DeleteBehavior.Cascade);
        model.Entity<PushOutbox>().HasKey(x => x.NotificationId);
        model.Entity<PushOutbox>().HasIndex(x => new { x.ExpandedAt, x.CreatedAt });
        model.Entity<PushOutbox>().HasOne<Notification>().WithOne().HasForeignKey<PushOutbox>(x => x.NotificationId).OnDelete(DeleteBehavior.Cascade);
        model.Entity<PushDelivery>().HasIndex(x => new { x.NotificationId, x.DeviceId }).IsUnique();
        model.Entity<PushDelivery>().HasIndex(x => new { x.CompletedAt, x.NextAttemptAt });
        model.Entity<PushDelivery>().Property(x => x.LastResult).HasMaxLength(40);
        model.Entity<PushDelivery>().HasOne<Notification>().WithMany().HasForeignKey(x => x.NotificationId).OnDelete(DeleteBehavior.Cascade);
        model.Entity<PushDelivery>().HasOne<PushDevice>().WithMany().HasForeignKey(x => x.DeviceId).OnDelete(DeleteBehavior.Cascade);
    }
}

// SaveChanges shares one transaction with the notification, so a committed inbox
// item cannot lose its push task if IIS recycles immediately afterwards.
public sealed class PushOutboxInterceptor : SaveChangesInterceptor
{
    private static void Enqueue(DbContext? db)
    {
        if (db is null) return;
        var ids = db.ChangeTracker.Entries<PushOutbox>().Select(x => x.Entity.NotificationId).ToHashSet();
        foreach (var notification in db.ChangeTracker.Entries<Notification>().Where(x => x.State == EntityState.Added).Select(x => x.Entity).ToArray())
            if (ids.Add(notification.Id)) db.Set<PushOutbox>().Add(new() { NotificationId = notification.Id, CreatedAt = notification.CreatedAt });
    }

    public override InterceptionResult<int> SavingChanges(DbContextEventData data, InterceptionResult<int> result)
    { Enqueue(data.Context); return result; }
    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(DbContextEventData data,
        InterceptionResult<int> result, CancellationToken cancellationToken = default)
    { Enqueue(data.Context); return ValueTask.FromResult(result); }
}

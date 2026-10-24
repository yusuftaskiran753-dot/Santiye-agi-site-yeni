using Microsoft.EntityFrameworkCore;
using SantiyeAgi.Api.Data;

namespace SantiyeAgi.Api.LiveLocation;

// One latest fix per participant/deal. No route or location history is retained.
public sealed class LiveLocationShare
{
    public Guid DealId { get; set; }
    public Guid UserId { get; set; }
    public Guid Generation { get; set; } = Guid.NewGuid();
    public double? Lat { get; set; }
    public double? Lng { get; set; }
    public double? Accuracy { get; set; }
    public double? Heading { get; set; }
    public double? Speed { get; set; }
    public DateTimeOffset FixAt { get; set; }
    public DateTimeOffset StartedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? StoppedAt { get; set; }
    public bool UntilDelivered { get; set; }
}

public static class LiveLocationModel
{
    public static void Configure(ModelBuilder model)
    {
        var share = model.Entity<LiveLocationShare>();
        share.ToTable("LiveLocationShares", t =>
        {
            t.HasCheckConstraint("live_lat_range", "\"Lat\" IS NULL OR (\"Lat\" >= -90 AND \"Lat\" <= 90)");
            t.HasCheckConstraint("live_lng_range", "\"Lng\" IS NULL OR (\"Lng\" >= -180 AND \"Lng\" <= 180)");
            t.HasCheckConstraint("live_duration_cap", "\"ExpiresAt\" <= \"StartedAt\" + INTERVAL '24 hours'");
        });
        share.HasKey(x => new { x.DealId, x.UserId });
        share.Property(x => x.Generation).IsConcurrencyToken();
        share.HasIndex(x => x.ExpiresAt);
        share.HasIndex(x => x.StoppedAt);
        share.HasOne<Deal>().WithMany().HasForeignKey(x => x.DealId).OnDelete(DeleteBehavior.Cascade);
        share.HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
    }
}

public sealed record ShareLocationInput(double Lat, double Lng, DateTimeOffset At,
    double? Accuracy = null, double? Heading = null, double? Speed = null,
    int? Minutes = null, bool UntilDelivered = false, Guid? Generation = null);

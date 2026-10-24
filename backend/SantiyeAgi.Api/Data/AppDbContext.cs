using Microsoft.EntityFrameworkCore;
using SantiyeAgi.Api.Billing;
using SantiyeAgi.Api.Services.Push;
using SantiyeAgi.Api.LiveLocation;
using SantiyeAgi.Api.AI;

namespace SantiyeAgi.Api.Data;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<HaulPoint> HaulPoints => Set<HaulPoint>();
    public DbSet<PortfolioPhoto> PortfolioPhotos => Set<PortfolioPhoto>();
    public DbSet<Session> Sessions => Set<Session>();
    public DbSet<PhoneChallenge> PhoneChallenges => Set<PhoneChallenge>();
    public DbSet<Listing> Listings => Set<Listing>();
    public DbSet<TradeRequest> Requests => Set<TradeRequest>();
    public DbSet<Deal> Deals => Set<Deal>();
    public DbSet<Rating> Ratings => Set<Rating>();
    public DbSet<Block> Blocks => Set<Block>();
    public DbSet<Unlock> Unlocks => Set<Unlock>();
    public DbSet<Notification> Notifications => Set<Notification>();
    public DbSet<Report> Reports => Set<Report>();
    public DbSet<ClientOperation> Operations => Set<ClientOperation>();
    public DbSet<CreditEntry> CreditEntries => Set<CreditEntry>();

    protected override void OnModelCreating(ModelBuilder m)
    {
        m.HasDefaultSchema("santiye");
        m.Entity<HaulPoint>().Property(x => x.Data).HasColumnType("jsonb");
        m.Entity<HaulPoint>().HasIndex(x => x.OwnerId);
        m.Entity<HaulPoint>().HasOne<User>().WithMany().HasForeignKey(x => x.OwnerId).OnDelete(DeleteBehavior.Cascade);
        m.Entity<PortfolioPhoto>().HasIndex(x => new { x.OwnerId, x.CreatedAt });
        m.Entity<PortfolioPhoto>().Property(x => x.Caption).HasMaxLength(200);
        m.Entity<PortfolioPhoto>().HasOne<User>().WithMany().HasForeignKey(x => x.OwnerId).OnDelete(DeleteBehavior.Cascade);
        m.Entity<User>().HasIndex(x => x.Phone).IsUnique();
        m.Entity<User>().Property(x => x.Phone).HasMaxLength(20);
        m.Entity<User>().ToTable(t => t.HasCheckConstraint("credits_nonnegative", "\"Credits\" >= 0"));
        m.Entity<Session>().HasIndex(x => x.RefreshHash).IsUnique();
        m.Entity<Session>().HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        m.Entity<PhoneChallenge>().HasKey(x => x.Phone);
        m.Entity<Listing>().Property(x => x.Data).HasColumnType("jsonb");
        m.Entity<Listing>().HasIndex(x => new { x.Kind, x.CreatedAt, x.Id });
        m.Entity<Listing>().HasIndex(x => new { x.OwnerId, x.Status });
        m.Entity<Listing>().HasIndex(x => x.OwnerId).IsUnique().HasFilter("\"Kind\" = 'sicil'");
        m.Entity<Listing>().HasOne<User>().WithMany().HasForeignKey(x => x.OwnerId).OnDelete(DeleteBehavior.Cascade);
        m.Entity<TradeRequest>().Property(x => x.Data).HasColumnType("jsonb");
        m.Entity<TradeRequest>().HasIndex(x => new { x.ListingId, x.RequesterId }).IsUnique().HasFilter("\"Status\" = 'pending'");
        m.Entity<TradeRequest>().HasIndex(x => new { x.OwnerId, x.UpdatedAt });
        m.Entity<TradeRequest>().HasIndex(x => new { x.RequesterId, x.UpdatedAt });
        m.Entity<TradeRequest>().HasOne<User>().WithMany().HasForeignKey(x => x.OwnerId).OnDelete(DeleteBehavior.Cascade);
        m.Entity<TradeRequest>().HasOne<User>().WithMany().HasForeignKey(x => x.RequesterId).OnDelete(DeleteBehavior.Cascade);
        m.Entity<Deal>().Property(x => x.Data).HasColumnType("jsonb");
        m.Entity<Deal>().HasIndex(x => x.Code).IsUnique();
        m.Entity<Deal>().HasIndex(x => x.RequestId).IsUnique();
        m.Entity<Deal>().HasIndex(x => new { x.CustomerId, x.UpdatedAt });
        m.Entity<Deal>().HasIndex(x => new { x.ProviderId, x.UpdatedAt });
        m.Entity<Deal>().HasOne<User>().WithMany().HasForeignKey(x => x.CustomerId).OnDelete(DeleteBehavior.SetNull);
        m.Entity<Deal>().HasOne<User>().WithMany().HasForeignKey(x => x.ProviderId).OnDelete(DeleteBehavior.SetNull);
        m.Entity<Deal>().HasOne<User>().WithMany().HasForeignKey(x => x.CreatedBy).OnDelete(DeleteBehavior.SetNull);
        m.Entity<Rating>().HasIndex(x => new { x.DealId, x.FromId }).IsUnique();
        m.Entity<Rating>().HasOne<User>().WithMany().HasForeignKey(x => x.FromId).OnDelete(DeleteBehavior.SetNull);
        m.Entity<Rating>().HasOne<User>().WithMany().HasForeignKey(x => x.ToId).OnDelete(DeleteBehavior.Cascade);
        m.Entity<Block>().HasKey(x => new { x.BlockerId, x.BlockedId });
        m.Entity<Block>().HasOne<User>().WithMany().HasForeignKey(x => x.BlockerId).OnDelete(DeleteBehavior.Cascade);
        m.Entity<Block>().HasOne<User>().WithMany().HasForeignKey(x => x.BlockedId).OnDelete(DeleteBehavior.Cascade);
        m.Entity<Unlock>().HasKey(x => new { x.UserId, x.ListingId });
        m.Entity<Unlock>().HasIndex(x => new { x.UserId, x.CreatedAt });
        m.Entity<Unlock>().HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        m.Entity<Notification>().HasIndex(x => new { x.UserId, x.CreatedAt });
        m.Entity<Notification>().HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        m.Entity<Report>().HasIndex(x => new { x.ReporterId, x.TargetType, x.TargetId }).IsUnique();
        m.Entity<Report>().HasOne<User>().WithMany().HasForeignKey(x => x.ReporterId).OnDelete(DeleteBehavior.Cascade);
        m.Entity<ClientOperation>().HasKey(x => new { x.UserId, x.Id });
        m.Entity<ClientOperation>().Property(x => x.Result).HasColumnType("jsonb");
        m.Entity<ClientOperation>().HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        m.Entity<CreditEntry>().HasIndex(x => new { x.UserId, x.CreatedAt });
        m.Entity<CreditEntry>().HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);
        BillingModel.Configure(m);
        PushModel.Configure(m);
        LiveLocationModel.Configure(m);
        AiModel.Configure(m);
    }
}

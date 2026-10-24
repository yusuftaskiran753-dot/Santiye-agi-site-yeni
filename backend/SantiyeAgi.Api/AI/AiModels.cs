using Microsoft.EntityFrameworkCore;
using SantiyeAgi.Api.Data;

namespace SantiyeAgi.Api.AI;

/// Only cost-control metadata is stored: never the user's text or provider output.
/// A deleted account is detached, while its spent global budget remains counted.
public sealed class AiUsage
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid? UserId { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset LeaseUntil { get; set; }
}

public static class AiModel
{
    public static void Configure(ModelBuilder model)
    {
        model.Entity<AiUsage>().HasIndex(x => x.CreatedAt);
        model.Entity<AiUsage>().HasIndex(x => new { x.UserId, x.CreatedAt });
        model.Entity<AiUsage>().HasIndex(x => x.LeaseUntil);
        model.Entity<AiUsage>().HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.SetNull);
    }
}

public sealed class AiOptions
{
    public bool Enabled { get; set; }
    public string ApiKey { get; set; } = "";
    // Verified against Google's official model documentation on 2026-10-20.
    public string Model { get; set; } = "gemini-3.5-flash-lite";
    public int DailyLimit { get; set; } = 30;
    public int PremiumDailyLimit { get; set; } = 200;
    // Request budget, not a currency estimate: a request has bounded input/output tokens.
    public int GlobalDailyRequestLimit { get; set; } = 1000;
    public int MaxConcurrency { get; set; } = 2;
    public int TimeoutSeconds { get; set; } = 12;
    public int MaxOutputTokens { get; set; } = 2048;

    public bool IsConfigured => Enabled && ApiKey.Length is >= 10 and <= 512 &&
        !ApiKey.Any(char.IsControl) && System.Text.RegularExpressions.Regex.IsMatch(Model, @"\Agemini-[a-z0-9][a-z0-9.-]{0,79}\z", System.Text.RegularExpressions.RegexOptions.CultureInvariant) &&
        DailyLimit is >= 1 and <= 1000 && PremiumDailyLimit is >= 1 and <= 5000 &&
        GlobalDailyRequestLimit is >= 1 and <= 100000 && MaxConcurrency is >= 1 and <= 10 &&
        TimeoutSeconds is >= 1 and <= 30 && MaxOutputTokens is >= 256 and <= 4096;
}

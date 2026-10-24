using System.Data;
using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using SantiyeAgi.Api.Data;

namespace SantiyeAgi.Api.Auth;

/// <summary>Checks whether requiring normal SMS verification would lock out configured password accounts.</summary>
public static class SmsReviewReadiness
{
    public sealed record AccountState(Guid Id, bool ProfileComplete, bool PhoneVerified);

    // Only aggregate flags/counts leave this tool; account identifiers and credentials never do.
    public sealed record Result(bool ReadOnly, bool PasswordLoginEnabled, int ConfiguredAccountCount,
        int VerifiedAccountCount, int MissingOrInvalidAccountCount, bool ReadyForRequiredSms, string Code)
    {
        [JsonIgnore]
        public int ExitCode => Code == "SMS_REVIEW_CHECK_FAILED" ? 1 : ReadyForRequiredSms ? 0 : 2;
    }

    public static Result Evaluate(bool passwordLoginEnabled, IReadOnlyList<Guid?> configuredUserIds,
        IReadOnlyCollection<AccountState> accounts)
    {
        // Disabled credentials cannot be used to review the app, and need no database query.
        if (!passwordLoginEnabled) return new(true, false, 0, 0, 0, true, "READY");
        var states = accounts.ToDictionary(x => x.Id);
        // Count configured mappings, including multiple credentials pointing to the same user.
        var verified = configuredUserIds.Count(id => id is { } value && value != Guid.Empty &&
            states.TryGetValue(value, out var user) && user.ProfileComplete && user.PhoneVerified);
        var ready = configuredUserIds.Count > 0 && verified == configuredUserIds.Count;
        return new(true, true, configuredUserIds.Count, verified, configuredUserIds.Count - verified, ready,
            ready ? "READY" : "REVIEW_ACCOUNTS_NOT_READY");
    }

    public static async Task<Result> Check(IConfiguration configuration, CancellationToken cancellationToken)
    {
        try
        {
            var enabled = configuration.GetValue<bool>("Auth:AccountLogin:Enabled");
            if (!enabled) return Evaluate(false, [], []);
            // Do not bind the account objects: only UserId is needed, never username/password/hash.
            var ids = configuration.GetSection("Auth:AccountLogin:Accounts").GetChildren()
                .Select(account => Guid.TryParse(account["UserId"], out var id) && id != Guid.Empty ? (Guid?)id : null)
                .ToArray();
            var validIds = ids.OfType<Guid>().Distinct().ToArray();
            if (validIds.Length == 0) return Evaluate(true, ids, []);

            var connection = configuration.GetConnectionString("Postgres");
            if (string.IsNullOrWhiteSpace(connection)) return Failed();
            // An independent unlogged context keeps normal IIS/EF logging and write interceptors out of this tool.
            var options = new DbContextOptionsBuilder<AppDbContext>()
                .UseNpgsql(connection, postgres => postgres.CommandTimeout(15))
                .UseLoggerFactory(NullLoggerFactory.Instance)
                .EnableSensitiveDataLogging(false).EnableDetailedErrors(false).Options;
            await using var db = new AppDbContext(options);
            await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.RepeatableRead, cancellationToken);
            await db.Database.ExecuteSqlRawAsync("SET TRANSACTION READ ONLY", cancellationToken);
            var accounts = await db.Users.AsNoTracking().Where(user => validIds.Contains(user.Id))
                .Select(user => new AccountState(user.Id, user.ProfileComplete, user.PhoneVerified))
                .ToArrayAsync(cancellationToken);
            await transaction.RollbackAsync(cancellationToken);
            return Evaluate(true, ids, accounts);
        }
        catch (Exception)
        {
            // Configuration, connection and SQL exceptions may contain secrets. Never expose their text or type.
            return Failed();
        }
    }

    private static Result Failed() => new(true, false, 0, 0, 0, false, "SMS_REVIEW_CHECK_FAILED");
}

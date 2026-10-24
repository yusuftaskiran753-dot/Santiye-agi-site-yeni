using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Infrastructure;
using SantiyeAgi.Api.Services.Push;

namespace SantiyeAgi.Api.Auth;

public static partial class AuthEndpoints
{
    [GeneratedRegex(@"^\+90[5][0-9]{9}$")]
    private static partial Regex TurkishPhone();

    public static void MapAuth(this WebApplication app)
    {
        var auth = app.MapGroup("/api/v1/auth").RequireRateLimiting("auth");
        auth.MapGet("/options", (IConfiguration config, ISmsOtpSender sms) =>
        {
            var required = AuthPolicy.RequiresPhone(config);
            var available = required || config.GetValue<bool>("Sms:Enabled");
            if (available)
            {
                try { sms.EnsureConfigured(); }
                catch (ApiError) { available = false; }
            }
            return new
            {
                phone_verification_required = required,
                phone_verification_available = available,
                password_login_enabled = config.GetValue<bool>("Auth:AccountLogin:Enabled")
            };
        });
        auth.MapPost("/password/login", async (JsonObject input, AppDbContext db, TokenService tokens, IConfiguration config) =>
        {
            var username = input.RequiredText("username", 1, 100).Trim();
            var password = input["password"]?.GetValue<string>() ?? "";
            if (password.Length is < 12 or > 128) throw new ApiError("AUTH_REQUIRED", 401);
            var section = config.GetSection("Auth:AccountLogin");
            var credential = section.GetSection("Accounts").GetChildren().FirstOrDefault(x =>
                string.Equals(x["Username"], username, StringComparison.OrdinalIgnoreCase));
            // Always derive a hash for unknown usernames as well. Never return account existence.
            var encoded = credential?["PasswordHash"] ?? "pbkdf2-sha256$600000$AAAAAAAAAAAAAAAAAAAAAA==$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
            var valid = AccountPassword.Verify(password, encoded);
            if (!section.GetValue<bool>("Enabled") || !valid || !Guid.TryParse(credential?["UserId"], out var userId))
                throw new ApiError("AUTH_REQUIRED", 401, "Kullanıcı adı veya parola hatalı.");
            var user = await db.Users.FindAsync(userId);
            if (user is null || !user.ProfileComplete) throw new ApiError("AUTH_REQUIRED", 401);
            // Alternate credentials do not mark a phone verified or bypass an enabled SMS policy.
            if (AuthPolicy.RequiresPhone(config) && !user.PhoneVerified) throw new ApiError("PHONE_REQUIRED", 403);
            var refresh = TokenService.NewRefresh();
            var session = new Session { UserId = user.Id, RefreshHash = TokenService.Hash(refresh), ExpiresAt = DateTimeOffset.UtcNow.AddDays(30) };
            db.Sessions.Add(session); await db.SaveChangesAsync();
            return tokens.Issue(user, session, refresh);
        });
        auth.MapPost("/phone/request", async (JsonObject input, AppDbContext db, TokenService tokens, ISmsOtpSender sms, IConfiguration config, IWebHostEnvironment env, CancellationToken cancellationToken) =>
        {
            var phone = input.Text("phone");
            if (!TurkishPhone().IsMatch(phone)) throw new ApiError("BAD_INPUT", detail: "Telefon +905xxxxxxxxx biçiminde olmalı.");
            // Provider readiness can be staged before making OTP mandatory for
            // all users. This lets an existing review account verify its real
            // phone normally while password access keeps its current policy.
            if (!AuthPolicy.RequiresPhone(config) && !config.GetValue<bool>("Sms:Enabled"))
                throw new ApiError("CONFIG", 503, "SMS doğrulaması şu anda kapalı.");
            if (sms.DevelopmentSimulation && !env.IsDevelopment()) throw new ApiError("CONFIG", 503);
            sms.EnsureConfigured();
            var now = DateTimeOffset.UtcNow;
            var generation = Guid.NewGuid();
            var code = RandomNumberGenerator.GetInt32(100000, 1000000).ToString(CultureInfo.InvariantCulture);
            // Persist the quota even if submission fails, to prevent paid retry floods.
            // An old code is invalidated before any external request. A new code is
            // usable only after the gateway explicitly confirms submission.
            await using (var tx = await db.Database.BeginTransactionAsync(cancellationToken))
            {
                if (!sms.DevelopmentSimulation)
                {
                    const string budgetKey = "__daily_budget__";
                    await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({budgetKey}, 0))", cancellationToken);
                    var budget = await db.Set<PhoneOtpQuota>().FindAsync([budgetKey], cancellationToken);
                    if (budget is null) db.Set<PhoneOtpQuota>().Add(budget = new() { Phone = budgetKey });
                    budget.ReserveDailyBudget(now, Math.Clamp(config.GetValue("Sms:DailyBudget", 200), 1, 10000));
                }
                await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({phone}, 0))", cancellationToken);
                var quota = await db.Set<PhoneOtpQuota>().FindAsync([phone], cancellationToken);
                if (quota is null) db.Set<PhoneOtpQuota>().Add(quota = new() { Phone = phone });
                quota.Reserve(now); quota.DevelopmentChallenge = sms.DevelopmentSimulation; quota.ChallengeGeneration = generation;
                var previous = await db.PhoneChallenges.FindAsync([phone], cancellationToken);
                if (previous is not null) { previous.ExpiresAt = now; previous.Attempts = 5; }
                await db.SaveChangesAsync(cancellationToken); await tx.CommitAsync(cancellationToken);
            }
            await sms.Send(phone, code, cancellationToken);
            await using (var tx = await db.Database.BeginTransactionAsync(cancellationToken))
            {
                await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({phone}, 0))", cancellationToken);
                var quota = await db.Set<PhoneOtpQuota>().FindAsync([phone], cancellationToken);
                await db.Entry(quota!).ReloadAsync(cancellationToken);
                if (quota!.ChallengeGeneration != generation) throw new ApiError("RATE_LIMIT", 429);
                var challenge = await db.PhoneChallenges.FindAsync([phone], cancellationToken);
                if (challenge is null) db.PhoneChallenges.Add(challenge = new() { Phone = phone });
                challenge.CodeHash = tokens.ChallengeHash(phone, code);
                challenge.ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(5); challenge.SentAt = now; challenge.Attempts = 0;
                await db.SaveChangesAsync(cancellationToken); await tx.CommitAsync(cancellationToken);
            }
            var result = new JsonObject { ["sent"] = true };
            if (env.IsDevelopment() && sms.DevelopmentSimulation) result["development_code"] = code;
            return result;
        });
        auth.MapPost("/phone/verify", async (JsonObject input, AppDbContext db, TokenService tokens, IWebHostEnvironment env) =>
        {
            var phone = input.Text("phone"); var code = input.Text("code");
            if (!TurkishPhone().IsMatch(phone) || code.Length != 6 || code.Any(c => c is < '0' or > '9')) throw new ApiError("BAD_INPUT");
            await using var tx = await db.Database.BeginTransactionAsync();
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({phone}, 0))");
            var challenge = await db.PhoneChallenges.FindAsync(phone);
            var quota = await db.Set<PhoneOtpQuota>().FindAsync(phone);
            if (quota is null || quota.DevelopmentChallenge && !env.IsDevelopment()) throw new ApiError("BAD_INPUT", detail: "Kod hatalı veya süresi dolmuş.");
            if (challenge is null || challenge.ExpiresAt < DateTimeOffset.UtcNow || challenge.Attempts >= 5) throw new ApiError("BAD_INPUT", detail: "Kod hatalı veya süresi dolmuş.");
            challenge.Attempts++;
            if (!CryptographicOperations.FixedTimeEquals(Convert.FromHexString(challenge.CodeHash), Convert.FromHexString(tokens.ChallengeHash(phone, code))))
            {
                await db.SaveChangesAsync(); await tx.CommitAsync();
                throw new ApiError("BAD_INPUT", detail: "Kod hatalı veya süresi dolmuş.");
            }
            var user = await db.Users.SingleOrDefaultAsync(x => x.Phone == phone);
            if (user is null) db.Users.Add(user = new() { Phone = phone, PhoneVerified = true });
            user.PhoneVerified = true;
            db.PhoneChallenges.Remove(challenge);
            var refresh = TokenService.NewRefresh();
            var session = new Session { UserId = user.Id, RefreshHash = TokenService.Hash(refresh), ExpiresAt = DateTimeOffset.UtcNow.AddDays(30) };
            db.Sessions.Add(session);
            await db.SaveChangesAsync(); await tx.CommitAsync();
            return tokens.Issue(user, session, refresh);
        });
        auth.MapPost("/anonymous", async (AppDbContext db, TokenService tokens, IWebHostEnvironment env, IConfiguration config) =>
        {
            var developmentGuest = env.IsDevelopment() && config.GetValue<bool>("Auth:AllowDevelopmentAnonymous");
            if (AuthPolicy.RequiresPhone(config) && !developmentGuest) throw new ApiError("PHONE_REQUIRED", 403);
            var user = new User(); var refresh = TokenService.NewRefresh();
            var session = new Session { UserId = user.Id, RefreshHash = TokenService.Hash(refresh), ExpiresAt = DateTimeOffset.UtcNow.AddDays(30) };
            db.Users.Add(user); db.Sessions.Add(session); await db.SaveChangesAsync();
            return tokens.Issue(user, session, refresh);
        });
        auth.MapPost("/refresh", async (JsonObject input, AppDbContext db, TokenService tokens) =>
        {
            var hash = TokenService.Hash(input.RequiredText("refresh_token", 64, 64));
            await using var tx = await db.Database.BeginTransactionAsync();
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({hash}, 0))");
            var session = await db.Sessions.SingleOrDefaultAsync(x => x.RefreshHash == hash);
            if (session is null || session.RevokedAt != null || session.ExpiresAt < DateTimeOffset.UtcNow) throw new ApiError("AUTH_REQUIRED", 401);
            var user = await db.Users.FindAsync(session.UserId) ?? throw new ApiError("AUTH_REQUIRED", 401);
            var refresh = TokenService.NewRefresh(); session.RefreshHash = TokenService.Hash(refresh);
            await db.SaveChangesAsync(); await tx.CommitAsync();
            return tokens.Issue(user, session, refresh);
        });
        auth.MapPost("/logout", async (HttpContext ctx, AppDbContext db) =>
        {
            await using var transaction = await db.Database.BeginTransactionAsync();
            if (Guid.TryParse(ctx.User.FindFirst("sid")?.Value, out var id))
            {
                var session = await db.Sessions.FindAsync(id);
                if (session is not null)
                {
                    // Same user lock as location writes: a late fix cannot survive logout.
                    await db.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(hashtextextended({session.UserId.ToString()}, 0))");
                    session.RevokedAt = DateTimeOffset.UtcNow;
                    await SantiyeAgi.Api.LiveLocation.LiveLocationService.StopForUser(db, session.UserId, session.RevokedAt.Value);
                    await db.Set<PushDevice>().Where(x => x.SessionId == id).ExecuteDeleteAsync();
                    await db.SaveChangesAsync();
                }
            }
            await transaction.CommitAsync();
            return Results.NoContent();
        }).RequireAuthorization();
    }
}

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using SantiyeAgi.Api.Auth;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Endpoints;
using SantiyeAgi.Api.Infrastructure;
using SantiyeAgi.Api.Services;
using SantiyeAgi.Api.Billing;
using SantiyeAgi.Api.Services.Push;
using SantiyeAgi.Api.AI;
using SantiyeAgi.Api.LiveLocation;

var builder = WebApplication.CreateBuilder(args);
var externalConfig = Environment.GetEnvironmentVariable("SANTIYE_CONFIG_FILE");
if (!string.IsNullOrWhiteSpace(externalConfig))
{
    if (!Path.IsPathFullyQualified(externalConfig)) throw new InvalidOperationException("SANTIYE_CONFIG_FILE must be an absolute path.");
    builder.Configuration.AddJsonFile(externalConfig, optional: false, reloadOnChange: false).AddEnvironmentVariables();
}
var key = builder.Configuration["Auth:SigningKey"];
if (string.IsNullOrEmpty(key) && builder.Environment.IsDevelopment())
    builder.Configuration["Auth:SigningKey"] = key = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
if (string.IsNullOrWhiteSpace(key) || Encoding.UTF8.GetByteCount(key) < 32)
    throw new InvalidOperationException("Auth:SigningKey must be at least 32 bytes. Configure it outside source control.");
var connection = builder.Configuration.GetConnectionString("Postgres");
if (string.IsNullOrWhiteSpace(connection)) throw new InvalidOperationException("ConnectionStrings:Postgres required.");
builder.Services.AddDbContext<AppDbContext>(o => o.UseNpgsql(connection).AddInterceptors(new PushOutboxInterceptor()));
var protectionPath = builder.Configuration["DataProtection:KeysPath"];
if (string.IsNullOrWhiteSpace(protectionPath))
{
    if (!builder.Environment.IsDevelopment())
        throw new InvalidOperationException("DataProtection:KeysPath must point to a persistent folder outside the deployment directory.");
    protectionPath = Path.Combine(AppContext.BaseDirectory, "development-keys");
}
var protection = builder.Services.AddDataProtection().SetApplicationName("SantiyeAgi")
    .PersistKeysToFileSystem(new DirectoryInfo(protectionPath));
if (OperatingSystem.IsWindows()) protection.ProtectKeysWithDpapi(protectToLocalMachine: true);
builder.Services.AddStoreBilling(builder.Configuration);
builder.Services.AddSmsAndPushServices(builder.Configuration);
builder.Services.AddAiServices(builder.Configuration);
builder.Services.AddLiveLocationServices();
builder.Services.AddScoped<Mutations>(); builder.Services.AddScoped<MarketService>(); builder.Services.AddScoped<TradeService>(); builder.Services.AddScoped<SafetyService>();
builder.Services.AddSingleton<TokenService>();
builder.Services.AddScoped<PortfolioService>();
builder.Services.Configure<Microsoft.AspNetCore.Http.Features.FormOptions>(o =>
{
    o.MultipartBodyLengthLimit = PortfolioService.MaxBytes + 65536;
    o.ValueLengthLimit = 1024;
    o.ValueCountLimit = 5;
});
builder.Services.AddHostedService<NotificationCleanup>();
builder.Services.ConfigureHttpJsonOptions(o => { o.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower; });
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(o =>
{
    o.MapInboundClaims = false;
    o.TokenValidationParameters = new() { ValidateIssuer = true, ValidateAudience = true, ValidateLifetime = true, ValidateIssuerSigningKey = true,
        ValidIssuer = builder.Configuration["Auth:Issuer"] ?? "SantiyeAgi", ValidAudience = builder.Configuration["Auth:Audience"] ?? "SantiyeAgi.Mobile",
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(key)), ClockSkew = TimeSpan.FromSeconds(30) };
    o.Events = new() { OnTokenValidated = async ctx =>
    {
        if (!Guid.TryParse(ctx.Principal?.FindFirst("sub")?.Value, out var userId) || !Guid.TryParse(ctx.Principal?.FindFirst("sid")?.Value, out var sessionId)) { ctx.Fail("Invalid session"); return; }
        var db = ctx.HttpContext.RequestServices.GetRequiredService<AppDbContext>();
        var verified = await (from session in db.Sessions
            join user in db.Users on session.UserId equals user.Id
            where session.Id == sessionId && session.UserId == userId && session.RevokedAt == null && session.ExpiresAt > DateTimeOffset.UtcNow
            select (bool?)user.PhoneVerified).SingleOrDefaultAsync();
        if (verified is null) { ctx.Fail("Session revoked"); return; }
        ctx.HttpContext.Items["PhoneVerified"] = verified.Value;
    }, OnChallenge = async ctx => { ctx.HandleResponse(); ctx.Response.StatusCode = 401; await ctx.Response.WriteAsJsonAsync(new { error = "AUTH_REQUIRED" }); } };
});
builder.Services.AddAuthorization();
builder.Services.AddHttpsRedirection(o => o.HttpsPort = 443);
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = 429;
    o.AddPolicy("portfolio-upload", _ => RateLimitPartition.GetConcurrencyLimiter("portfolio-upload", _ =>
        new() { PermitLimit = 2, QueueLimit = 0 }));
    o.OnRejected = async (ctx, ct) => await ctx.HttpContext.Response.WriteAsJsonAsync(new { error = "RATE_LIMIT" }, ct);
    o.AddPolicy("auth", c => RateLimitPartition.GetFixedWindowLimiter(c.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ => new() { PermitLimit = 15, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 }));
    o.AddPolicy("api", c => RateLimitPartition.GetFixedWindowLimiter(c.User.FindFirst("sub")?.Value ?? "unknown", _ => new() { PermitLimit = 300, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 }));
});
var app = builder.Build();
if (args.Contains("--sms-review-readiness"))
{
    // Read-only local audit: no listener, hosted service, migration or SMS submission is started.
    using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(40));
    var result = await SmsReviewReadiness.Check(app.Configuration, timeout.Token);
    Console.WriteLine(JsonSerializer.Serialize(new
    {
        result.ReadOnly, result.PasswordLoginEnabled, result.ConfiguredAccountCount,
        result.VerifiedAccountCount, result.MissingOrInvalidAccountCount, result.ReadyForRequiredSms, result.Code
    }));
    Environment.ExitCode = result.ExitCode;
    return;
}
if (args.Contains("--apple-notification-test") || args.Contains("--apple-api-access-check"))
{
    // Run locally on the server with its existing external configuration.
    // No HTTP listener, DB writes, migrations or entitlement changes are started.
    using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(40));
    try
    {
        var result = await app.Services.GetRequiredService<AppleStoreClient>()
            .CheckTestNotification(args.Contains("--sandbox"), timeout.Token, args.Contains("--apple-api-access-check"));
        Console.WriteLine(result.ToJsonString());
        Environment.ExitCode = result["delivered"]?.GetValue<bool>() == true || result["api_access_verified"]?.GetValue<bool>() == true ? 0 : 2;
    }
    catch (ApiError e)
    {
        Console.WriteLine(JsonSerializer.Serialize(new { error = e.Code, status = e.Status }));
        Environment.ExitCode = 1;
    }
    catch (Exception e) when (e is HttpRequestException or OperationCanceledException or IOException or System.Security.Cryptography.CryptographicException)
    {
        Console.WriteLine("{\"error\":\"APPLE_CHECK_FAILED\"}");
        Environment.ExitCode = 1;
    }
    return;
}
if (args.Contains("--migrate"))
{
    using var scope = app.Services.CreateScope();
    await scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.MigrateAsync();
    return;
}
app.Use(async (ctx, next) =>
{
    try { await next(); }
    catch (ApiError e) { ctx.Response.StatusCode = e.Status; await ctx.Response.WriteAsJsonAsync(new { error = e.Code, detail = e.Detail }); }
    catch (Exception e) when (e is JsonException or FormatException or InvalidOperationException or BadHttpRequestException)
    {
        app.Logger.LogWarning("Invalid request at {Path}: {Type}", ctx.Request.Path, e.GetType().Name);
        ctx.Response.StatusCode = 400; await ctx.Response.WriteAsJsonAsync(new { error = "BAD_INPUT" });
    }
    catch (DbUpdateException e) when (e.InnerException is Npgsql.PostgresException p && p.SqlState == "23505")
    { ctx.Response.StatusCode = 409; await ctx.Response.WriteAsJsonAsync(new { error = "DUPLICATE" }); }
    catch (Exception e)
    { app.Logger.LogError(e, "Request failed at {Path}", ctx.Request.Path); ctx.Response.StatusCode = 503; await ctx.Response.WriteAsJsonAsync(new { error = "SERVER" }); }
});
if (!app.Environment.IsDevelopment()) { app.UseHsts(); app.UseHttpsRedirection(); }
app.UseAuthentication();
app.Use(async (ctx, next) =>
{
    if (ctx.User.Identity?.IsAuthenticated == true &&
        ctx.Request.Path.StartsWithSegments("/api/v1") && !ctx.Request.Path.StartsWithSegments("/api/v1/auth") &&
        !(ctx.Request.Method == "DELETE" && ctx.Request.Path == "/api/v1/account") &&
        AuthPolicy.RequiresPhone(app.Configuration) && ctx.Items["PhoneVerified"] is not true)
    {
        ctx.Response.StatusCode = 403;
        await ctx.Response.WriteAsJsonAsync(new { error = "PHONE_REQUIRED" });
        return;
    }
    await next();
});
app.UseAuthorization(); app.UseRateLimiter();
app.MapGet("/health/live", () => Results.Ok(new { status = "ok", service = "SantiyeAgi.Api" }));
app.MapGet("/health/ready", async (AppDbContext db) =>
{
    if (!await db.Database.CanConnectAsync()) return Results.StatusCode(503);
    await db.Users.AnyAsync(); // Bağlantının yanında şemanın kurulduğunu da doğrula.
    return Results.Ok(new { status = "ready" });
});
app.MapAuth(); app.MapApi();
app.MapHaulPoints();
app.MapPortfolio();
app.MapStoreBilling();
app.MapPush();
app.MapAi();
app.MapLiveLocation();
app.Run();

public partial class Program;

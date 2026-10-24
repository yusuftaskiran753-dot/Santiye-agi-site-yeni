using System.Net;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Services.Push;

internal static class PushProbeEntry
{
public static async Task<int> Main(string[] args)
{
var output = new PushProbeReport();
try
{
    if (args.Length != 3 || !Guid.TryParse(args[2], out var operation)) throw new ProbeError("BAD_OPERATION");
    var site = args[0]; var stateFolder = args[1];
    var environment = Environment.GetEnvironmentVariable("DOTNET_ENVIRONMENT") ?? Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Production";
    var external = Environment.GetEnvironmentVariable("SANTIYE_CONFIG_FILE");
    if (environment != "Production" || string.IsNullOrEmpty(external) || !Path.IsPathFullyQualified(external)) throw new ProbeError("CONFIG_UNRESOLVED");
    var config = new ConfigurationBuilder().AddJsonFile(Path.Combine(site, "appsettings.json"), false)
        .AddJsonFile(Path.Combine(site, "appsettings.Production.json"), true).AddJsonFile(external, false).AddEnvironmentVariables().Build();
    var bindings = config.GetSection("Auth:AccountLogin:Accounts").GetChildren().Where(x => string.Equals(x["Username"], "test", StringComparison.OrdinalIgnoreCase)).ToArray();
    if (bindings.Length != 1 || !Guid.TryParse(bindings[0]["UserId"], out var actor)) throw new ProbeError("ACCOUNT_AMBIGUOUS");
    output.AccountId = actor;
    using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(50)); var ct = timeout.Token;
    var options = new DbContextOptionsBuilder<AppDbContext>().UseNpgsql(config.GetConnectionString("Postgres")).Options;
    await using var db = new AppDbContext(options);
    await using var transaction = await db.Database.BeginTransactionAsync(ct);
    await db.Database.ExecuteSqlRawAsync("SET TRANSACTION READ ONLY", ct);
    var user = await db.Users.AsNoTracking().SingleOrDefaultAsync(x => x.Id == actor, ct);
    if (user is null || !user.ProfileComplete) throw new ProbeError("ACCOUNT_NOT_FOUND");
    output.AccountName = user.Name.Length <= 100 ? user.Name : "test";
    var now = DateTimeOffset.UtcNow;
    var devices = await (from device in db.Set<PushDevice>().AsNoTracking()
        join session in db.Sessions.AsNoTracking() on device.SessionId equals session.Id
        where device.UserId == actor && device.Platform == "ios" && session.UserId == actor && session.RevokedAt == null && session.ExpiresAt > now
        orderby device.RegisteredAt descending
        select device).Take(2).ToArrayAsync(ct);
    var selected = SingleIosTarget.Select(devices, actor);
    output.DeviceId = selected.Id; output.RegisteredAt = selected.RegisteredAt;
    var current = await db.Set<PushDevice>().AsNoTracking().SingleOrDefaultAsync(x => x.Id == selected.Id && x.UserId == actor && x.TokenHash == selected.TokenHash && x.SessionId == selected.SessionId, ct);
    if (current is null) throw new ProbeError("DEVICE_CHANGED");
    var transport = new SinglePushTransport(selected.Token) { InnerHandler = new HttpClientHandler { AllowAutoRedirect = false } };
    using var http = new HttpClient(transport) { Timeout = TimeSpan.FromSeconds(20) };
    var sender = new FcmPushSender(new OneClientFactory(http), new GooglePushAccessTokenProvider(config), config, NullLogger<FcmPushSender>.Instance);
    if (!sender.Configured) throw new ProbeError("PUSH_NOT_CONFIGURED");
    var marker = Path.Combine(stateFolder, operation.ToString("N") + ".json");
    try
    {
        await using var stream = new FileStream(marker, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        await JsonSerializer.SerializeAsync(stream, new { operation, actor, device = selected.Id, state = "ATTEMPT_RESERVED", utc = DateTimeOffset.UtcNow }, cancellationToken: ct);
    }
    catch (IOException) { throw new ProbeError("ALREADY_ATTEMPTED_OR_STATE_UNAVAILABLE"); }
    // No notification/outbox/device mutation: existing sender is called once for this device only.
    var result = await sender.Send(selected, new Notification { Id = operation, UserId = actor, Title = SinglePushTransport.TestTitle, RefType = "push_test" }, ct);
    output.Code = result.Code; output.FcmHttpStatus = transport.Status; output.FcmRequestCount = transport.RequestCount;
    output.FcmAccepted = result.Kind == PushResultKind.Success && transport.RequestCount == 1;
    await File.WriteAllTextAsync(marker, JsonSerializer.Serialize(output), ct);
}
catch (ProbeError e) { output.Code = e.Code; }
catch { output.Code = "PROBE_FAILED_OR_RESULT_UNKNOWN"; }
Console.WriteLine(JsonSerializer.Serialize(output));
return output.FcmAccepted ? 0 : 1;
}
}

public sealed class ProbeError(string code) : Exception { public string Code { get; } = code; }
public sealed class PushProbeReport
{
    public int PushProbeVersion { get; } = 1;
    public string Username { get; } = "test";
    public Guid? AccountId { get; set; }
    public string? AccountName { get; set; }
    public Guid? DeviceId { get; set; }
    public DateTimeOffset? RegisteredAt { get; set; }
    public string Platform { get; } = "ios";
    public int FcmRequestCount { get; set; }
    public int? FcmHttpStatus { get; set; }
    public bool FcmAccepted { get; set; }
    public string Code { get; set; } = "NOT_SENT";
}
public static class SingleIosTarget
{
    public static PushDevice Select(PushDevice[] devices, Guid actor)
    {
        if (devices.Length == 0) throw new ProbeError("NO_ACTIVE_IOS_DEVICE");
        if (devices.Any(x => x.UserId != actor || x.Platform != "ios")) throw new ProbeError("ACCOUNT_DEVICE_MISMATCH");
        if (devices.Length > 1 && devices[0].RegisteredAt == devices[1].RegisteredAt) throw new ProbeError("IOS_DEVICE_AMBIGUOUS");
        if (devices[0].RegisteredAt < DateTimeOffset.UtcNow.AddHours(-1)) throw new ProbeError("IOS_DEVICE_NOT_RECENT");
        return devices[0];
    }
}
public sealed class SinglePushTransport(string expectedToken) : DelegatingHandler
{
    public const string TestTitle = "Şantiye Ağı — Bildirim testi";
    public int? Status { get; private set; }
    public int RequestCount { get; private set; }
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
    {
        if (RequestCount != 0 || request.Method != HttpMethod.Post || request.RequestUri?.Host != "fcm.googleapis.com" || !request.RequestUri.AbsolutePath.EndsWith("/messages:send", StringComparison.Ordinal)) throw new ProbeError("SINGLE_SEND_GUARD");
        var root = JsonNode.Parse(await request.Content!.ReadAsStringAsync(ct))!.AsObject();
        var message = root["message"]!.AsObject();
        if (message["token"]?.GetValue<string>() != expectedToken || message.ContainsKey("topic") || message.ContainsKey("condition")) throw new ProbeError("SINGLE_TARGET_GUARD");
        // Keep the existing FCM sender/credential/APNs/data path; override text only in this test process.
        message["notification"] = new JsonObject { ["title"] = TestTitle, ["body"] = "iPhone bildirim testi." };
        request.Content.Dispose(); request.Content = new StringContent(root.ToJsonString(), System.Text.Encoding.UTF8, "application/json");
        RequestCount++;
        var response = await base.SendAsync(request, ct); Status = (int)response.StatusCode; return response;
    }
}
public sealed class OneClientFactory(HttpClient client) : IHttpClientFactory { public HttpClient CreateClient(string name) => client; }

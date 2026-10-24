using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.RegularExpressions;
using Google.Apis.Auth.OAuth2;
using SantiyeAgi.Api.Data;

namespace SantiyeAgi.Api.Services.Push;

public enum PushResultKind { Success, InvalidToken, Retry, PermanentFailure }
public sealed record PushSendResult(PushResultKind Kind, string Code, TimeSpan? RetryAfter = null);

public interface IPushAccessTokenProvider
{
    Task<string> Get(CancellationToken cancellationToken);
}

public sealed class GooglePushAccessTokenProvider(IConfiguration config) : IPushAccessTokenProvider
{
    private GoogleCredential? _credential;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public async Task<string> Get(CancellationToken cancellationToken)
    {
        if (_credential is null)
        {
            await _gate.WaitAsync(cancellationToken);
            try
            {
                if (_credential is null)
                {
                    var path = config["Push:Firebase:ServiceAccountPath"];
                    if (string.IsNullOrWhiteSpace(path)) throw new InvalidOperationException("Firebase service account path is not configured.");
                    var json = await File.ReadAllTextAsync(path, cancellationToken);
                    using var document = JsonDocument.Parse(json);
                    var root = document.RootElement;
                    // Restrict the accepted credential type and OAuth host. Never
                    // accept arbitrary external-account configuration from a client.
                    if (root.GetProperty("type").GetString() != "service_account" ||
                        root.GetProperty("project_id").GetString() != config["Push:Firebase:ProjectId"] ||
                        root.GetProperty("token_uri").GetString() != "https://oauth2.googleapis.com/token")
                        throw new InvalidOperationException("Firebase service account does not match the configured project.");
                    var account = CredentialFactory.FromJson<ServiceAccountCredential>(json);
                    _credential = GoogleCredential.FromServiceAccountCredential(account)
                        .CreateScoped("https://www.googleapis.com/auth/firebase.messaging");
                }
            }
            finally { _gate.Release(); }
        }
        return await ((ITokenAccess)_credential).GetAccessTokenForRequestAsync(null, cancellationToken);
    }
}

public interface IPushSender
{
    bool Configured { get; }
    Task<PushSendResult> Send(PushDevice device, Notification notification, CancellationToken cancellationToken);
}

public sealed partial class FcmPushSender(IHttpClientFactory clients, IPushAccessTokenProvider tokens,
    IConfiguration config, ILogger<FcmPushSender> logger) : IPushSender
{
    [GeneratedRegex("^[a-z][a-z0-9-]{4,61}[a-z0-9]$")]
    private static partial Regex ProjectId();
    public bool Configured => config.GetValue<bool>("Push:Enabled") &&
        ProjectId().IsMatch(config["Push:Firebase:ProjectId"] ?? "") &&
        !string.IsNullOrWhiteSpace(config["Push:Firebase:ServiceAccountPath"]);

    public async Task<PushSendResult> Send(PushDevice device, Notification notification, CancellationToken cancellationToken)
    {
        if (!Configured) return new(PushResultKind.Retry, "NOT_CONFIGURED", TimeSpan.FromMinutes(5));
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post,
                $"https://fcm.googleapis.com/v1/projects/{config["Push:Firebase:ProjectId"]}/messages:send");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", await tokens.Get(cancellationToken));
            request.Content = JsonContent.Create(new
            {
                message = new
                {
                    token = device.Token,
                    notification = new { title = "Şantiye Ağı", body = "Yeni bir bildiriminiz var. Ayrıntıları uygulamada görüntüleyin." },
                    data = new Dictionary<string, string>
                    {
                        ["notification_id"] = notification.Id.ToString(), ["user_id"] = notification.UserId.ToString(),
                        ["ref_type"] = notification.RefType, ["ref_id"] = notification.RefId?.ToString() ?? ""
                    },
                    android = new { priority = "HIGH", ttl = "86400s", notification = new { channel_id = "santiye_updates", tag = notification.Id.ToString() } },
                    apns = new { headers = new Dictionary<string, string> { ["apns-collapse-id"] = notification.Id.ToString(), ["apns-expiration"] = DateTimeOffset.UtcNow.AddHours(24).ToUnixTimeSeconds().ToString(System.Globalization.CultureInfo.InvariantCulture) }, payload = new { aps = new { sound = "default" } } }
                }
            });
            using var response = await clients.CreateClient("push").SendAsync(request, cancellationToken);
            if (response.IsSuccessStatusCode) return new(PushResultKind.Success, "SENT");
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            var code = ErrorCode(body);
            if (code == "UNREGISTERED") return new(PushResultKind.InvalidToken, code);
            if (response.StatusCode is HttpStatusCode.TooManyRequests or HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden || (int)response.StatusCode >= 500)
                return new(PushResultKind.Retry, code, RetryDelay(response.Headers.RetryAfter));
            return new(PushResultKind.PermanentFailure, code);
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException or JsonException or IOException or InvalidOperationException or ArgumentException or KeyNotFoundException or System.Security.Cryptography.CryptographicException or Google.Apis.Auth.OAuth2.Responses.TokenResponseException)
        {
            // Never log token, credential file contents or provider error bodies.
            logger.LogWarning("Push submission failed ({ErrorType}).", error.GetType().Name);
            return new(PushResultKind.Retry, "PROVIDER_UNAVAILABLE");
        }
    }

    public static string ErrorCode(string body)
    {
        try
        {
            using var json = JsonDocument.Parse(body);
            if (!json.RootElement.TryGetProperty("error", out var error)) return "PROVIDER_ERROR";
            if (error.TryGetProperty("details", out var details) && details.ValueKind == JsonValueKind.Array)
                foreach (var detail in details.EnumerateArray())
                    if (detail.TryGetProperty("@type", out var type) && type.GetString() == "type.googleapis.com/google.firebase.fcm.v1.FcmError" &&
                        detail.TryGetProperty("errorCode", out var code))
                        return SafeCode(code.GetString());
            return error.TryGetProperty("status", out var status) ? SafeCode(status.GetString()) : "PROVIDER_ERROR";
        }
        catch (JsonException) { return "PROVIDER_ERROR"; }
    }

    private static string SafeCode(string? code) => code is { Length: > 0 and <= 40 } && code.All(c => c is >= 'A' and <= 'Z' or '_') ? code : "PROVIDER_ERROR";
    private static TimeSpan? RetryDelay(RetryConditionHeaderValue? header)
    {
        var delay = header?.Delta ?? (header?.Date is { } date ? date - DateTimeOffset.UtcNow : (TimeSpan?)null);
        return delay is null ? null : TimeSpan.FromSeconds(Math.Clamp(delay.Value.TotalSeconds, 60, 3600));
    }
}

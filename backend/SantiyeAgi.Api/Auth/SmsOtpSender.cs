using System.Net.Http.Json;
using System.Text.Json;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.Auth;

public interface ISmsOtpSender
{
    bool DevelopmentSimulation { get; }
    void EnsureConfigured();
    Task Send(string phone, string code, CancellationToken cancellationToken);
}

// Credentials are read only from server configuration. Never return the provider
// response (it can contain the recipient, message and account information).
public sealed class SmsOtpSender(IHttpClientFactory clients, IConfiguration config,
    IWebHostEnvironment environment, ILogger<SmsOtpSender> logger) : ISmsOtpSender
{
    private string Provider => config["Sms:Provider"] ?? (environment.IsDevelopment() ? "Development" : "Disabled");
    public bool DevelopmentSimulation => environment.IsDevelopment() && Provider.Equals("Development", StringComparison.OrdinalIgnoreCase);

    public void EnsureConfigured()
    {
        if (DevelopmentSimulation) return;
        if (!Provider.Equals("VatanSms", StringComparison.OrdinalIgnoreCase) || !config.GetValue<bool>("Sms:Enabled") ||
            new[] { "ApiId", "ApiKey", "Sender" }.Any(x => string.IsNullOrWhiteSpace(config["Sms:VatanSms:" + x])))
            throw new ApiError("CONFIG", 503, "Telefon doğrulama hizmeti henüz yapılandırılmadı.");
    }

    public async Task Send(string phone, string code, CancellationToken cancellationToken)
    {
        EnsureConfigured();
        if (DevelopmentSimulation) return;
        try
        {
            using var response = await clients.CreateClient("sms").PostAsJsonAsync("https://api.vatansms.net/api/v1/otp", new
            {
                api_id = config["Sms:VatanSms:ApiId"], api_key = config["Sms:VatanSms:ApiKey"],
                sender = config["Sms:VatanSms:Sender"], message_type = "normal",
                message = $"Santiye Agi dogrulama kodunuz: {code}. Kod 5 dakika gecerlidir. Kimseyle paylasmayin.",
                phones = new[] { phone[3..] }
            }, cancellationToken);
            if (!response.IsSuccessStatusCode) throw new SmsDeliveryException();
            // HTTP 200 alone is not sufficient: gateways can report rejection in JSON.
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
            if (!IsAccepted(json.RootElement)) throw new SmsDeliveryException();
        }
        catch (Exception error) when (error is HttpRequestException or TaskCanceledException or JsonException or SmsDeliveryException)
        {
            logger.LogWarning("SMS provider did not confirm OTP submission ({ErrorType}).", error.GetType().Name);
            throw new ApiError("SMS_UNAVAILABLE", 503, "Doğrulama kodu gönderilemedi. Lütfen daha sonra yeniden deneyin.");
        }
    }

    public static bool IsAccepted(JsonElement response)
    {
        if (response.ValueKind != JsonValueKind.Object) return false;
        if (response.TryGetProperty("error", out var error) && error.ValueKind is not JsonValueKind.Null and not JsonValueKind.False &&
            !(error.ValueKind == JsonValueKind.String && string.IsNullOrWhiteSpace(error.GetString()))) return false;
        if (response.TryGetProperty("errors", out var errors) && errors.ValueKind != JsonValueKind.Null &&
            !(errors.ValueKind == JsonValueKind.Array && errors.GetArrayLength() == 0)) return false;
        if (response.TryGetProperty("status", out var status))
            return status.ValueKind == JsonValueKind.String && status.GetString() is "success" or "SUCCESS" ||
                   status.ValueKind == JsonValueKind.Number && status.TryGetInt32(out var value) && value == 200;
        return response.TryGetProperty("success", out var success) && success.ValueKind == JsonValueKind.True;
    }

    private sealed class SmsDeliveryException : Exception;
}

public sealed class PhoneOtpQuota
{
    public string Phone { get; set; } = "";
    public DateTimeOffset LastAttemptAt { get; set; }
    public DateTimeOffset HourStart { get; set; }
    public int HourCount { get; set; }
    public DateTimeOffset DayStart { get; set; }
    public int DayCount { get; set; }
    public bool DevelopmentChallenge { get; set; }
    public Guid ChallengeGeneration { get; set; }

    public void Reserve(DateTimeOffset now)
    {
        if (now - LastAttemptAt < TimeSpan.FromSeconds(60)) throw new ApiError("RATE_LIMIT", 429);
        if (now - HourStart >= TimeSpan.FromHours(1)) { HourStart = now; HourCount = 0; }
        if (now - DayStart >= TimeSpan.FromDays(1)) { DayStart = now; DayCount = 0; }
        if (HourCount >= 5 || DayCount >= 10) throw new ApiError("RATE_LIMIT", 429, "Doğrulama kodu gönderim sınırına ulaşıldı.");
        LastAttemptAt = now; HourCount++; DayCount++;
    }

    public void ReserveDailyBudget(DateTimeOffset now, int limit)
    {
        if (now - DayStart >= TimeSpan.FromDays(1)) { DayStart = now; DayCount = 0; }
        if (DayCount >= limit) throw new ApiError("RATE_LIMIT", 429, "Günlük doğrulama gönderim sınırına ulaşıldı.");
        LastAttemptAt = now; DayCount++;
    }
}

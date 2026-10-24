using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Logging.Abstractions;
using SantiyeAgi.Api.Auth;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Infrastructure;
using SantiyeAgi.Api.Services.Push;

namespace SantiyeAgi.Api.Tests;

public sealed class SmsPushTests
{
    private static IConfiguration Config(params (string Key, string Value)[] settings) => new ConfigurationBuilder()
        .AddInMemoryCollection(settings.Select(x => new KeyValuePair<string, string?>(x.Key, x.Value))).Build();

    [Fact]
    public async Task DevelopmentSimulationCannotBeEnabledInProduction()
    {
        var http = new FakeHttpFactory();
        var sender = new SmsOtpSender(http, Config(("Sms:Provider", "Development")), new TestEnvironment("Production"), NullLogger<SmsOtpSender>.Instance);
        Assert.False(sender.DevelopmentSimulation);
        var error = Assert.Throws<ApiError>(sender.EnsureConfigured); Assert.Equal("CONFIG", error.Code);
        var development = new SmsOtpSender(http, Config(), new TestEnvironment("Development"), NullLogger<SmsOtpSender>.Instance);
        Assert.True(development.DevelopmentSimulation);
        await development.Send("+905550000001", "123456", default); Assert.Equal(0, http.Calls);
    }

    [Fact]
    public async Task VatanOtpUsesDocumentedEndpointAndDoesNotAcceptHttpSuccessAsDelivery()
    {
        JsonObject? submitted = null;
        var http = new FakeHttpFactory(async request =>
        {
            Assert.Equal("https://api.vatansms.net/api/v1/otp", request.RequestUri!.ToString());
            submitted = await request.Content!.ReadFromJsonAsync<JsonObject>();
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { status = "success" }) };
        });
        var sender = new SmsOtpSender(http, Config(("Sms:Provider", "VatanSms"), ("Sms:Enabled", "true"),
            ("Sms:VatanSms:ApiId", "test-api-id"), ("Sms:VatanSms:ApiKey", "unit-test-placeholder"), ("Sms:VatanSms:Sender", "TEST")),
            new TestEnvironment("Production"), NullLogger<SmsOtpSender>.Instance);
        await sender.Send("+905550000001", "654321", default);
        Assert.False(sender.DevelopmentSimulation);
        Assert.Equal("5550000001", submitted!["phones"]![0]!.GetValue<string>());
        Assert.Equal("normal", submitted["message_type"]!.GetValue<string>());
        Assert.Contains("654321", submitted["message"]!.GetValue<string>());
        http.Handler = _ => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new { status = "error", message = "private provider detail" }) });
        var error = await Assert.ThrowsAsync<ApiError>(() => sender.Send("+905550000001", "654321", default));
        Assert.Equal("SMS_UNAVAILABLE", error.Code); Assert.DoesNotContain("private", error.Message);
        http.Handler = _ => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new { message = "unknown schema" }) });
        await Assert.ThrowsAsync<ApiError>(() => sender.Send("+905550000001", "654321", default));
        http.Handler = _ => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new { success = true, error = "provider rejection" }) });
        await Assert.ThrowsAsync<ApiError>(() => sender.Send("+905550000001", "654321", default));
    }

    [Fact]
    public void PhoneQuotaLimitsRepeatRequestsPerHourAndDay()
    {
        var quota = new PhoneOtpQuota(); var now = DateTimeOffset.UtcNow;
        for (var i = 0; i < 5; i++) quota.Reserve(now.AddMinutes(i));
        Assert.Equal("RATE_LIMIT", Assert.Throws<ApiError>(() => quota.Reserve(now.AddMinutes(5))).Code);
        for (var i = 0; i < 5; i++) quota.Reserve(now.AddHours(1).AddMinutes(i));
        Assert.Throws<ApiError>(() => quota.Reserve(now.AddHours(2)));
        quota.Reserve(now.AddDays(1)); Assert.Equal(1, quota.DayCount);
        Assert.Throws<ApiError>(() => quota.Reserve(now.AddDays(1).AddSeconds(59)));
        var budget = new PhoneOtpQuota(); budget.ReserveDailyBudget(now, 2); budget.ReserveDailyBudget(now, 2);
        Assert.Throws<ApiError>(() => budget.ReserveDailyBudget(now.AddHours(1), 2));
        budget.ReserveDailyBudget(now.AddDays(1), 2); Assert.Equal(1, budget.DayCount);
    }

    [Fact]
    public async Task PushDoesNotCallNetworkUntilConfigured()
    {
        var http = new FakeHttpFactory(); var tokens = new FakeAccessToken();
        var sender = new FcmPushSender(http, tokens, Config(), NullLogger<FcmPushSender>.Instance);
        Assert.False(sender.Configured);
        var result = await sender.Send(new(), new(), default);
        Assert.Equal(PushResultKind.Retry, result.Kind); Assert.Equal(0, http.Calls); Assert.Equal(0, tokens.Calls);
    }

    [Fact]
    public async Task PushPayloadTargetsRecipientAndKeepsPrivateNotificationTextOffLockScreen()
    {
        JsonObject? submitted = null;
        var http = new FakeHttpFactory(async request =>
        {
            Assert.Equal("https://fcm.googleapis.com/v1/projects/test-project/messages:send", request.RequestUri!.ToString());
            Assert.Equal("Bearer", request.Headers.Authorization!.Scheme);
            submitted = await request.Content!.ReadFromJsonAsync<JsonObject>();
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { name = "projects/test-project/messages/1" }) };
        });
        var notification = new Notification { UserId = Guid.NewGuid(), Title = "Private party", Body = "Sensitive price/phone", RefType = "deal", RefId = Guid.NewGuid() };
        var sender = Sender(http);
        Assert.Equal(PushResultKind.Success, (await sender.Send(new() { Token = "unit-test-device-token" }, notification, default)).Kind);
        var data = submitted!["message"]!["data"]!;
        Assert.Equal(notification.UserId.ToString(), data["user_id"]!.GetValue<string>());
        Assert.Equal(notification.Id.ToString(), data["notification_id"]!.GetValue<string>());
        Assert.Equal(notification.RefId.ToString(), data["ref_id"]!.GetValue<string>());
        Assert.DoesNotContain("Sensitive", submitted.ToJsonString());
        Assert.DoesNotContain("Private party", submitted.ToJsonString());
        Assert.Equal("santiye_updates", submitted["message"]!["android"]!["notification"]!["channel_id"]!.GetValue<string>());
    }

    [Theory]
    [InlineData(404, "UNREGISTERED", PushResultKind.InvalidToken)]
    [InlineData(400, "INVALID_ARGUMENT", PushResultKind.PermanentFailure)]
    [InlineData(403, "SENDER_ID_MISMATCH", PushResultKind.Retry)]
    [InlineData(429, "QUOTA_EXCEEDED", PushResultKind.Retry)]
    [InlineData(503, "UNAVAILABLE", PushResultKind.Retry)]
    public async Task PushClassifiesProviderErrorsWithoutDeletingValidDevices(int status, string code, PushResultKind expected)
    {
        var http = new FakeHttpFactory(_ => Task.FromResult(new HttpResponseMessage((HttpStatusCode)status)
        {
            Content = JsonContent.Create(new { error = new { details = new[] { new Dictionary<string, string>
                { ["@type"] = "type.googleapis.com/google.firebase.fcm.v1.FcmError", ["errorCode"] = code } } } })
        }));
        var result = await Sender(http).Send(new() { Token = "unit-test-device-token" }, new(), default);
        Assert.Equal(expected, result.Kind); Assert.Equal(code, result.Code);
    }

    [Fact]
    public async Task PushHonorsRetryAfterAndBackoffIsBounded()
    {
        var response = new HttpResponseMessage(HttpStatusCode.TooManyRequests) { Content = new StringContent("{}") };
        response.Headers.RetryAfter = new(TimeSpan.FromSeconds(120));
        var result = await Sender(new FakeHttpFactory(_ => Task.FromResult(response))).Send(new(), new(), default);
        Assert.Equal(TimeSpan.FromSeconds(120), result.RetryAfter);
        Assert.Equal(TimeSpan.FromSeconds(60), PushDispatcher.RetryDelay(1));
        Assert.Equal(TimeSpan.FromHours(1), PushDispatcher.RetryDelay(50));
    }

    private static FcmPushSender Sender(FakeHttpFactory http) => new(http, new FakeAccessToken(),
        Config(("Push:Enabled", "true"), ("Push:Firebase:ProjectId", "test-project"), ("Push:Firebase:ServiceAccountPath", "not-read-by-fake-token")), NullLogger<FcmPushSender>.Instance);

    private sealed class FakeAccessToken : IPushAccessTokenProvider
    {
        public int Calls { get; private set; }
        public Task<string> Get(CancellationToken cancellationToken) { Calls++; return Task.FromResult("unit-test-token"); }
    }

    private sealed class FakeHttpFactory(Func<HttpRequestMessage, Task<HttpResponseMessage>>? handler = null) : HttpMessageHandler, IHttpClientFactory
    {
        public int Calls { get; private set; }
        public Func<HttpRequestMessage, Task<HttpResponseMessage>>? Handler { get; set; } = handler;
        public HttpClient CreateClient(string name) => new(this, disposeHandler: false);
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        { Calls++; return Handler?.Invoke(request) ?? throw new InvalidOperationException("No network expected."); }
    }

    private sealed class TestEnvironment(string environment) : IWebHostEnvironment
    {
        public string ApplicationName { get; set; } = "UnitTests";
        public string EnvironmentName { get; set; } = environment;
        public string ContentRootPath { get; set; } = "";
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
        public string WebRootPath { get; set; } = "";
        public IFileProvider WebRootFileProvider { get; set; } = new NullFileProvider();
    }
}

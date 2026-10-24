using System.Net;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Services.Push;

public sealed class SinglePushProbeTests
{
    [Fact]
    public void TargetMustBeUniqueLatestIosOfConfirmedAccount()
    {
        var actor = Guid.NewGuid(); var now = DateTimeOffset.UtcNow;
        var latest = new PushDevice { UserId = actor, Platform = "ios", RegisteredAt = now };
        var old = new PushDevice { UserId = actor, Platform = "ios", RegisteredAt = now.AddMinutes(-1) };
        Assert.Same(latest, SingleIosTarget.Select([latest, old], actor));
        Assert.Throws<ProbeError>(() => SingleIosTarget.Select([], actor));
        Assert.Throws<ProbeError>(() => SingleIosTarget.Select([latest, new() { UserId = actor, Platform = "ios", RegisteredAt = now }], actor));
        Assert.Throws<ProbeError>(() => SingleIosTarget.Select([new() { UserId = Guid.NewGuid(), Platform = "ios" }], actor));
        Assert.Throws<ProbeError>(() => SingleIosTarget.Select([new() { UserId = actor, Platform = "android" }], actor));
        Assert.Throws<ProbeError>(() => SingleIosTarget.Select([new() { UserId = actor, Platform = "ios", RegisteredAt = now.AddHours(-2) }], actor));
    }
    [Fact]
    public async Task ExistingFcmSenderSendsExactTestTextToOneTokenOnce()
    {
        var actor = Guid.NewGuid(); var calls = 0;
        var transport = new SinglePushTransport("CANARY-DEVICE-TOKEN") { InnerHandler = new TestHandler(request => {
            calls++;
            Assert.Equal("https://fcm.googleapis.com/v1/projects/santiye-agi/messages:send", request.RequestUri!.AbsoluteUri);
            var message = JsonNode.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult())!["message"]!;
            Assert.Equal("CANARY-DEVICE-TOKEN", message["token"]!.ToString());
            Assert.Equal("Şantiye Ağı — Bildirim testi", message["notification"]!["title"]!.ToString());
            Assert.Equal(actor.ToString(), message["data"]!["user_id"]!.ToString());
            Assert.Equal("default", message["apns"]!["payload"]!["aps"]!["sound"]!.ToString());
            Assert.Null(message["topic"]); Assert.Null(message["condition"]);
            return new(HttpStatusCode.OK) { Content = new StringContent("{\"name\":\"projects/santiye-agi/messages/CANARY-PROVIDER-ID\"}") };
        }) };
        using var http = new HttpClient(transport);
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?> {
            ["Push:Enabled"] = "true", ["Push:Firebase:ProjectId"] = "santiye-agi", ["Push:Firebase:ServiceAccountPath"] = "unused-mock" }).Build();
        var sender = new FcmPushSender(new OneClientFactory(http), new TestToken(), config, NullLogger<FcmPushSender>.Instance);
        var device = new PushDevice { UserId = actor, Token = "CANARY-DEVICE-TOKEN", Platform = "ios" };
        var notification = new Notification { UserId = actor };
        Assert.Equal(PushResultKind.Success, (await sender.Send(device, notification, default)).Kind);
        Assert.Equal(200, transport.Status); Assert.Equal(1, transport.RequestCount);
        await Assert.ThrowsAsync<ProbeError>(() => sender.Send(device, notification, default));
        Assert.Equal(1, calls);
    }
    [Fact]
    public async Task DifferentTokenOrTopicCannotReachProvider()
    {
        using var http = new HttpClient(new SinglePushTransport("expected") { InnerHandler = new TestHandler(_ => throw new Exception("Network forbidden")) });
        using var request = new HttpRequestMessage(HttpMethod.Post, "https://fcm.googleapis.com/v1/projects/santiye-agi/messages:send") {
            Content = new StringContent("{\"message\":{\"token\":\"wrong\",\"topic\":\"all\"}}") };
        await Assert.ThrowsAsync<ProbeError>(() => http.SendAsync(request));
    }
    private sealed class TestToken : IPushAccessTokenProvider { public Task<string> Get(CancellationToken ct) => Task.FromResult("CANARY-OAUTH"); }
    private sealed class TestHandler(Func<HttpRequestMessage, HttpResponseMessage> handler) : HttpMessageHandler
    { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct) => Task.FromResult(handler(request)); }
}

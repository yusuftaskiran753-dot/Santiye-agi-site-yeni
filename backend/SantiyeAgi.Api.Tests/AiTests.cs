using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Options;
using SantiyeAgi.Api.AI;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.Tests;

public sealed class AiTests
{
    internal static readonly string ValidResult = """{"intent":"ilan_ver","kategori":"yuk","nereden":"İstanbul","nereye":"Ankara","il":"İstanbul","arac":"tir","makine":null,"malzeme":null,"pozisyon":null,"yuk_cinsi":"Demir","ton":24,"fiyat":28000,"gun":1,"ozet":"İstanbul'dan Ankara'ya yarın 24 ton demir göndermek istiyorsunuz.","cevap":null}""";

    internal static HttpResponseMessage ProviderResponse(string text, string finish = "STOP") => new(HttpStatusCode.OK)
    {
        Content = new StringContent(JsonSerializer.Serialize(new
        {
            candidates = new[] { new { finishReason = finish, content = new { parts = new object[] { new { text = "Provider thought must not be returned", thought = true }, new { text } } } } }
        }), Encoding.UTF8, "application/json")
    };

    internal sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> handler) : HttpMessageHandler
    {
        public int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            Interlocked.Increment(ref Calls);
            return handler(request, ct);
        }
    }

    private static AiOptions Config() => new() { Enabled = true, ApiKey = "LOCAL-FAKE-GEMINI-KEY-NEVER-USED-OUTSIDE-TEST" };

    [Fact]
    public async Task GeminiUsesFixedHttpsHostHeaderKeySchemaAndPlainUserData()
    {
        using var handler = new Handler(async (request, ct) =>
        {
            Assert.Equal("generativelanguage.googleapis.com", request.RequestUri!.Host);
            Assert.Equal("https", request.RequestUri.Scheme);
            Assert.Equal("/v1beta/models/gemini-3.5-flash-lite:generateContent", request.RequestUri.AbsolutePath);
            Assert.Empty(request.RequestUri.Query);
            Assert.Equal(Config().ApiKey, request.Headers.GetValues("x-goog-api-key").Single());
            var body = JsonNode.Parse(await request.Content!.ReadAsStringAsync(ct))!.AsObject();
            Assert.False(body.ContainsKey("tools"));
            Assert.Equal("application/json", body["generationConfig"]!["responseMimeType"]!.GetValue<string>());
            Assert.Equal(2048, body["generationConfig"]!["maxOutputTokens"]!.GetValue<int>());
            Assert.Equal(1, body["generationConfig"]!["candidateCount"]!.GetValue<int>());
            var userText = JsonNode.Parse(body["contents"]![0]!["parts"]![0]!["text"]!.GetValue<string>())!;
            Assert.Equal("Ankara", userText["il"]!.GetValue<string>());
            Assert.Equal("24 ton demir göndereceğim", userText["istek"]!.GetValue<string>());
            Assert.DoesNotContain(Config().ApiKey, body.ToJsonString());
            return ProviderResponse(ValidResult);
        });
        using var http = new HttpClient(handler);
        var result = await new GeminiClient(http, Options.Create(Config())).Understand(AiInput.Validate("24 ton demir göndereceğim", "Ankara"), default);
        Assert.Equal("ilan_ver", result["intent"]!.GetValue<string>());
        Assert.Equal("Demir", result["yuk_cinsi"]!.GetValue<string>());
        Assert.Equal(28000, result["fiyat"]!.GetValue<decimal>());
        Assert.DoesNotContain("thought", result.ToJsonString());
        Assert.Equal(1, handler.Calls);
    }

    [Fact]
    public void SanitizerDropsUnsupportedFieldsInvalidEnumsCitiesAndUnboundedNumbers()
    {
        using var doc = JsonDocument.Parse("""{"intent":"ara","ozet":"Kısa özet","kategori":"admin","nereden":"Gebze","nereye":"ankara","arac":"spaceship","makine":"robot","pozisyon":"owner","ton":-1,"fiyat":1e200,"gun":366,"cevap":"İlanınız yayınlandı","credits":999999,"premium":true} """);
        var result = AiValidation.Sanitize(doc.RootElement);
        Assert.Equal("Ankara", result["nereye"]!.GetValue<string>());
        foreach (var name in new[] { "kategori", "nereden", "arac", "makine", "pozisyon", "ton", "fiyat", "gun", "cevap" }) Assert.Null(result[name]);
        Assert.False(result.ContainsKey("credits")); Assert.False(result.ContainsKey("premium"));
        Assert.Equal(15, result.Count);
    }

    [Fact]
    public void SanitizerLimitsStringsAndKeepsTodayZeroAndQuestionAnswer()
    {
        var body = new JsonObject { ["intent"] = "soru", ["ozet"] = new string('Ö', 400), ["cevap"] = "\u202e" + new string('A', 1000), ["yuk_cinsi"] = new string('D', 100), ["gun"] = 0 };
        using var doc = JsonDocument.Parse(body.ToJsonString());
        var result = AiValidation.Sanitize(doc.RootElement);
        Assert.Equal(160, result["ozet"]!.GetValue<string>().Length);
        Assert.Equal(600, result["cevap"]!.GetValue<string>().Length);
        Assert.Equal(60, result["yuk_cinsi"]!.GetValue<string>().Length);
        Assert.Equal(0, result["gun"]!.GetValue<int>());
        Assert.DoesNotContain('\u202e', result["cevap"]!.GetValue<string>());
    }

    [Theory]
    [InlineData("[]")]
    [InlineData("{}")]
    [InlineData("{\"intent\":\"ara\",\"ozet\":\"\"}")]
    [InlineData("{\"intent\":\"grant_credits\",\"ozet\":\"Yanlış\"}")]
    public void SanitizerRejectsMissingOrUnknownIntentAndEmptySummary(string json)
    {
        using var document = JsonDocument.Parse(json);
        Assert.Equal("SERVER", Assert.Throws<ApiError>(() => AiValidation.Sanitize(document.RootElement)).Code);
    }

    [Theory]
    [InlineData(400, "CONFIG")]
    [InlineData(401, "CONFIG")]
    [InlineData(403, "CONFIG")]
    [InlineData(404, "CONFIG")]
    [InlineData(429, "RATE_LIMIT")]
    [InlineData(503, "SERVER")]
    public async Task ProviderErrorsAreRedactedWithoutRetries(int status, string code)
    {
        using var handler = new Handler((_, _) => Task.FromResult(new HttpResponseMessage((HttpStatusCode)status) { Content = new StringContent("SECRET PROVIDER RESPONSE " + Config().ApiKey) }));
        using var http = new HttpClient(handler);
        var exception = await Assert.ThrowsAsync<ApiError>(() => new GeminiClient(http, Options.Create(Config())).Understand(AiInput.Validate("Tır lazım", ""), default));
        Assert.Equal(code, exception.Code); Assert.Null(exception.Detail);
        Assert.DoesNotContain(Config().ApiKey, exception.ToString());
        Assert.DoesNotContain("SECRET PROVIDER RESPONSE", exception.ToString());
        Assert.Equal(1, handler.Calls);
    }

    [Theory]
    [InlineData("not json", "STOP")]
    [InlineData("{}", "STOP")]
    [InlineData("[]", "STOP")]
    [InlineData("{}", "MAX_TOKENS")]
    [InlineData("{}", "SAFETY")]
    public async Task MalformedBlockedOrTruncatedProviderOutputFailsHonestFallback(string body, string finish)
    {
        using var handler = new Handler((_, _) => Task.FromResult(ProviderResponse(body, finish)));
        using var http = new HttpClient(handler);
        var error = await Assert.ThrowsAsync<ApiError>(() => new GeminiClient(http, Options.Create(Config())).Understand(AiInput.Validate("Tır lazım", ""), default));
        Assert.Equal("SERVER", error.Code);
    }

    [Fact]
    public async Task DisabledAndUnsafeModelConfigurationNeverContactProvider()
    {
        using var handler = new Handler((_, _) => throw new InvalidOperationException("Should not be called"));
        using var http = new HttpClient(handler);
        var disabled = Config(); disabled.Enabled = false;
        var invalidModel = Config(); invalidModel.Model = "../another-host?key=stolen";
        var missingKey = Config(); missingKey.ApiKey = "";
        foreach (var config in new[] { disabled, invalidModel, missingKey })
        {
            var error = await Assert.ThrowsAsync<ApiError>(() => new GeminiClient(http, Options.Create(config)).Understand(AiInput.Validate("Tır lazım", "Ankara"), default));
            Assert.Equal("CONFIG", error.Code);
        }
        Assert.Equal(0, handler.Calls);
    }

    [Fact]
    public async Task TimeoutAndOversizedProviderResponsesAreBounded()
    {
        using var slow = new Handler(async (_, ct) => { await Task.Delay(Timeout.InfiniteTimeSpan, ct); return ProviderResponse(ValidResult); });
        using var http = new HttpClient(slow);
        var config = Config(); config.TimeoutSeconds = 1;
        var error = await Assert.ThrowsAsync<ApiError>(() => new GeminiClient(http, Options.Create(config)).Understand(AiInput.Validate("Tır lazım", ""), default));
        Assert.Equal("SERVER", error.Code);
        using var huge = new Handler((_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(new string('A', 32769)) }));
        using var hugeHttp = new HttpClient(huge);
        Assert.Equal("SERVER", (await Assert.ThrowsAsync<ApiError>(() => new GeminiClient(hugeHttp, Options.Create(Config())).Understand(AiInput.Validate("Tır lazım", ""), default))).Code);
    }

    [Fact]
    public async Task InputRejectsOversizeWrongTypesAndControlCharacters()
    {
        Assert.Throws<ApiError>(() => AiInput.Validate(new string('a', 401), "Ankara"));
        Assert.Throws<ApiError>(() => AiInput.Validate("a", "Ankara"));
        Assert.Throws<ApiError>(() => AiInput.Validate("ab\0cd", "Ankara"));
        Assert.Throws<ApiError>(() => AiInput.Validate("ab", new string('c', 41)));
        Assert.Equal("İstanbul", AiInput.Validate("  Yük lazım  ", "istanbul").City);
        foreach (var json in new[] { "[]", "{\"text\":42}", "{\"text\":\"tır lazım\",\"city\":42}", "{}" })
        {
            var context = new DefaultHttpContext(); context.Request.ContentType = "application/json";
            context.Request.Body = new MemoryStream(Encoding.UTF8.GetBytes(json));
            await Assert.ThrowsAsync<ApiError>(() => AiInput.Read(context.Request, default));
        }
        var oversized = new DefaultHttpContext(); oversized.Request.ContentType = "application/json";
        oversized.Request.Body = new MemoryStream(new byte[8193]); // no Content-Length: streaming cap still applies
        Assert.Equal(413, (await Assert.ThrowsAsync<ApiError>(() => AiInput.Read(oversized.Request, default))).Status);
    }
}

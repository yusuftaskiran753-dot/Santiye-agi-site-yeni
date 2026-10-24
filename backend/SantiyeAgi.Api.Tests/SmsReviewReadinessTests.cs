using System.Text.Json;
using Microsoft.Extensions.Configuration;
using SantiyeAgi.Api.Auth;

namespace SantiyeAgi.Api.Tests;

public sealed class SmsReviewReadinessTests
{
    [Fact]
    public void EnabledPasswordLoginWithoutAccountsIsNotSafeToActivate()
    {
        var result = SmsReviewReadiness.Evaluate(true, [], []);
        Assert.False(result.ReadyForRequiredSms);
        Assert.Equal("REVIEW_ACCOUNTS_NOT_READY", result.Code);
        Assert.Equal(2, result.ExitCode);
    }

    [Fact]
    public void EveryMappingMustResolveToACompleteNormallyVerifiedProfile()
    {
        var verified = Guid.NewGuid();
        var notVerified = Guid.NewGuid();
        var incomplete = Guid.NewGuid();
        var missing = Guid.NewGuid();
        var result = SmsReviewReadiness.Evaluate(true, [verified, notVerified, incomplete, missing, null, Guid.Empty],
            [new(verified, true, true), new(notVerified, true, false), new(incomplete, false, true)]);
        Assert.True(result.ReadOnly);
        Assert.True(result.PasswordLoginEnabled);
        Assert.Equal(6, result.ConfiguredAccountCount);
        Assert.Equal(1, result.VerifiedAccountCount);
        Assert.Equal(5, result.MissingOrInvalidAccountCount);
        Assert.False(result.ReadyForRequiredSms);
    }

    [Fact]
    public void DifferentCredentialsMayPointToTheSameVerifiedUser()
    {
        var id = Guid.NewGuid();
        var result = SmsReviewReadiness.Evaluate(true, [id, id], [new(id, true, true)]);
        Assert.True(result.ReadyForRequiredSms);
        Assert.Equal(2, result.ConfiguredAccountCount);
        Assert.Equal(2, result.VerifiedAccountCount);
        Assert.Equal(0, result.MissingOrInvalidAccountCount);
        Assert.Equal(0, result.ExitCode);
    }

    [Theory]
    [InlineData(true, false)]
    [InlineData(false, true)]
    [InlineData(false, false)]
    public void VerificationAndCompletedProfileAreBothRequired(bool profileComplete, bool phoneVerified)
    {
        var id = Guid.NewGuid();
        var result = SmsReviewReadiness.Evaluate(true, [id], [new(id, profileComplete, phoneVerified)]);
        Assert.False(result.ReadyForRequiredSms);
        Assert.Equal(1, result.MissingOrInvalidAccountCount);
    }

    [Fact]
    public void UnboundUserCannotMakeTheConfiguredAccountReady()
    {
        var result = SmsReviewReadiness.Evaluate(true, [Guid.NewGuid()], [new(Guid.NewGuid(), true, true)]);
        Assert.False(result.ReadyForRequiredSms);
        Assert.Equal(0, result.VerifiedAccountCount);
    }

    [Fact]
    public async Task DisabledLoginDoesNotInspectInactiveCredentialOrDatabaseSettings()
    {
        var provider = new GuardedProvider(new()
        {
            ["Auth:AccountLogin:Enabled"] = "false",
            ["Auth:AccountLogin:Accounts:0:UserId"] = Guid.NewGuid().ToString(),
            ["Auth:AccountLogin:Accounts:0:Username"] = "private-username",
            ["Auth:AccountLogin:Accounts:0:PasswordHash"] = "private-password-hash"
        }, rejectUserIds: true);
        var result = await SmsReviewReadiness.Check(Config(provider), default);
        Assert.Equal("READY", result.Code);
        Assert.False(result.PasswordLoginEnabled);
        Assert.Equal(0, result.ConfiguredAccountCount);
        Assert.Equal(0, provider.ForbiddenReads);
    }

    [Fact]
    public async Task InvalidAccountIdFailsClosedWithoutReadingCredentialsOrDatabase()
    {
        var provider = new GuardedProvider(new()
        {
            ["Auth:AccountLogin:Enabled"] = "true",
            ["Auth:AccountLogin:Accounts:0:UserId"] = "not-a-user-id",
            ["Auth:AccountLogin:Accounts:0:Username"] = "private-username",
            ["Auth:AccountLogin:Accounts:0:PasswordHash"] = "private-password-hash"
        });
        var result = await SmsReviewReadiness.Check(Config(provider), default);
        Assert.False(result.ReadyForRequiredSms);
        Assert.Equal(1, result.ConfiguredAccountCount);
        Assert.Equal(1, result.MissingOrInvalidAccountCount);
        Assert.Equal("REVIEW_ACCOUNTS_NOT_READY", result.Code);
        Assert.Equal(0, provider.ForbiddenReads);
    }

    [Fact]
    public async Task MalformedEnabledSettingProducesOnlyFixedFailureFields()
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Auth:AccountLogin:Enabled"] = "private-invalid-setting"
        }).Build();
        var result = await SmsReviewReadiness.Check(configuration, default);
        Assert.Equal("SMS_REVIEW_CHECK_FAILED", result.Code);
        Assert.False(result.ReadyForRequiredSms);
        Assert.Equal(1, result.ExitCode);
        Assert.DoesNotContain("private", JsonSerializer.Serialize(result));
    }

    [Fact]
    public async Task MissingDatabaseConfigurationCannotReportAConfiguredAccountAsReady()
    {
        var id = Guid.NewGuid();
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Auth:AccountLogin:Enabled"] = "true",
            ["Auth:AccountLogin:Accounts:0:UserId"] = id.ToString()
        }).Build();
        var result = await SmsReviewReadiness.Check(configuration, default);
        Assert.Equal("SMS_REVIEW_CHECK_FAILED", result.Code);
        Assert.False(result.ReadyForRequiredSms);
        Assert.DoesNotContain(id.ToString(), JsonSerializer.Serialize(result));
    }

    [Fact]
    public void ReportContainsOnlyTheDocumentedAggregateFields()
    {
        var id = Guid.NewGuid();
        var result = SmsReviewReadiness.Evaluate(true, [id], [new(id, true, true)]);
        using var json = JsonDocument.Parse(JsonSerializer.Serialize(result));
        Assert.Equal(new[] { "ReadOnly", "PasswordLoginEnabled", "ConfiguredAccountCount", "VerifiedAccountCount",
            "MissingOrInvalidAccountCount", "ReadyForRequiredSms", "Code" },
            json.RootElement.EnumerateObject().Select(x => x.Name).ToArray());
        Assert.DoesNotContain(id.ToString(), json.RootElement.GetRawText());
    }

    private static IConfiguration Config(GuardedProvider provider) => new ConfigurationBuilder().Add(new Source(provider)).Build();
    private sealed class Source(GuardedProvider provider) : IConfigurationSource
    {
        public IConfigurationProvider Build(IConfigurationBuilder builder) => provider;
    }
    private sealed class GuardedProvider(Dictionary<string, string?> data, bool rejectUserIds = false) : ConfigurationProvider
    {
        public int ForbiddenReads { get; private set; }
        public override void Load() => Data = data;
        public override bool TryGet(string key, out string? value)
        {
            if (key.EndsWith(":Username", StringComparison.OrdinalIgnoreCase) ||
                key.Contains("Password", StringComparison.OrdinalIgnoreCase) ||
                key.StartsWith("ConnectionStrings:", StringComparison.OrdinalIgnoreCase) ||
                (rejectUserIds && key.EndsWith(":UserId", StringComparison.OrdinalIgnoreCase)))
            {
                ForbiddenReads++;
                throw new InvalidOperationException("Unexpected sensitive configuration read.");
            }
            return base.TryGet(key, out value);
        }
    }
}

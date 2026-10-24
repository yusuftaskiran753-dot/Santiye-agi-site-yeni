using System.Text.Json.Nodes;
using SantiyeAgi.Api.Domain;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.Tests;

public class DomainTests
{
    private static readonly Guid Customer = Guid.NewGuid(), Provider = Guid.NewGuid();
    private static JsonObject Deal(string status = "active") => new() { ["customer_id"] = Customer.ToString(), ["provider_id"] = Provider.ToString(), ["created_by"] = Customer.ToString(), ["status"] = status, ["milestones"] = new JsonArray(), ["log"] = new JsonArray() };

    [Fact]
    public void CancellationRequiresTheOtherParty()
    {
        var pending = DealRules.Apply(Deal(), Customer, "A", "cancel", null, null);
        Assert.Equal("active", pending.Text("status"));
        Assert.Equal("WAITING_OTHER", Assert.Throws<ApiError>(() => DealRules.Apply(pending, Customer, "A", "cancel", null, null)).Code);
        var completed = DealRules.Apply(pending, Provider, "B", "cancel", null, null);
        Assert.Equal("cancelled", completed.Text("status"));
    }
    [Fact]
    public void OnlyTheReporterCanResolveADispute()
    {
        var disputed = DealRules.Apply(Deal(), Customer, "A", "dispute", null, "Sorun");
        Assert.Equal("FORBIDDEN", Assert.Throws<ApiError>(() => DealRules.Apply(disputed, Provider, "B", "resolve", null, null)).Code);
        Assert.Equal("active", DealRules.Apply(disputed, Customer, "A", "resolve", null, null).Text("status"));
    }
    [Fact]
    public void AnUnrelatedUserCannotAct()
    {
        Assert.Equal("FORBIDDEN", Assert.Throws<ApiError>(() => DealRules.Apply(Deal(), Guid.NewGuid(), "X", "note", null, "x")).Code);
    }
    [Fact]
    public void ProviderCannotCompleteOnBehalfOfCustomer()
    {
        Assert.Throws<ApiError>(() => DealRules.Apply(Deal(), Provider, "B", "complete", null, null));
    }
    [Fact]
    public void CanonicalFingerprintDoesNotDependOnFieldOrder()
    {
        Assert.Equal(Mutations.Canonical(JsonNode.Parse("{\"a\":1,\"b\":{\"x\":2,\"y\":3}}")), Mutations.Canonical(JsonNode.Parse("{\"b\":{\"y\":3,\"x\":2},\"a\":1}")));
    }
    [Fact]
    public void ClosedOrUnavailableMachineCannotBeRequested()
    {
        Assert.False(ListingRules.Available("makine", new() { ["available"] = false }));
        Assert.False(ListingRules.Available("malzeme", new() { ["stock"] = "yok" }));
    }
}

using System.Runtime.CompilerServices;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.Billing;

public sealed class StoreVerifier(GoogleStoreClient google, AppleStoreClient apple) : IStoreVerifier
{
    public Task<VerifiedStorePurchase> Verify(string platform, string productId, string reference, CancellationToken ct) => platform switch
    {
        "android" => google.Verify(productId, reference, ct),
        "ios" => apple.Verify(productId, reference, ct),
        _ => throw new ApiError("BAD_INPUT")
    };
    public Task Acknowledge(VerifiedStorePurchase purchase, CancellationToken ct) => purchase.Platform == "android" ? google.Acknowledge(purchase, ct) : Task.CompletedTask;
    public async IAsyncEnumerable<StoreVoid> GoogleVoids([EnumeratorCancellation] CancellationToken ct)
    {
        await foreach (var item in google.Voids(ct)) yield return item;
    }
}

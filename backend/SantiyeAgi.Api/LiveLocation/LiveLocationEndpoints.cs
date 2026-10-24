using Microsoft.Extensions.DependencyInjection.Extensions;
using SantiyeAgi.Api.Endpoints;

namespace SantiyeAgi.Api.LiveLocation;

public static class LiveLocationEndpoints
{
    public static IServiceCollection AddLiveLocationServices(this IServiceCollection services)
    {
        services.TryAddSingleton(TimeProvider.System);
        services.AddScoped<LiveLocationService>();
        services.AddHostedService<LiveLocationCleanup>();
        return services;
    }

    public static void MapLiveLocation(this WebApplication app)
    {
        var api = app.MapGroup("/api/v1/deals").RequireAuthorization().RequireRateLimiting("api");
        api.MapPost("/{id:guid}/location/prepare", (HttpContext context, Guid id, LiveLocationService service) =>
        {
            context.RequestAborted.ThrowIfCancellationRequested();
            return service.Prepare(ApiEndpoints.Actor(context), id, Guid.Parse(context.User.FindFirst("sid")!.Value));
        });
        api.MapPut("/{id:guid}/location", (HttpContext context, Guid id, ShareLocationInput input, LiveLocationService service) =>
            service.Put(ApiEndpoints.Actor(context), id, input, Guid.Parse(context.User.FindFirst("sid")!.Value)));
        api.MapDelete("/{id:guid}/location", async (HttpContext context, Guid id, LiveLocationService service) =>
        {
            await service.Stop(ApiEndpoints.Actor(context), id, Guid.Parse(context.User.FindFirst("sid")!.Value));
            return Results.NoContent();
        });
        api.MapGet("/{id:guid}/locations", (HttpContext context, Guid id, LiveLocationService service) =>
            service.Get(ApiEndpoints.Actor(context), id, Guid.Parse(context.User.FindFirst("sid")!.Value)));
    }
}

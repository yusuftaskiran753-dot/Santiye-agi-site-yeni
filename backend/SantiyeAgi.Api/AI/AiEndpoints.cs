using System.Text.Json.Nodes;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Options;
using SantiyeAgi.Api.Endpoints;

namespace SantiyeAgi.Api.AI;

public static class AiEndpoints
{
    public static IServiceCollection AddAiServices(this IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<AiOptions>(configuration.GetSection("AI"));
        services.TryAddSingleton(TimeProvider.System);
        services.AddScoped<AiQuota>();
        services.AddHttpClient<IGeminiClient, GeminiClient>(http => http.Timeout = Timeout.InfiniteTimeSpan)
            .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler { AllowAutoRedirect = false, ConnectTimeout = TimeSpan.FromSeconds(3), PooledConnectionLifetime = TimeSpan.FromMinutes(5) })
            .RedactLoggedHeaders(["x-goog-api-key"]);
        return services;
    }

    public static void MapAi(this WebApplication app)
    {
        var api = app.MapGroup("/api/v1/ai").RequireAuthorization().RequireRateLimiting("api");
        api.MapGet("/options", (IOptions<AiOptions> options, HttpContext context) =>
        {
            context.Response.Headers.CacheControl = "no-store";
            return Results.Ok(new { enabled = options.Value.IsConfigured });
        });
        api.MapPost("/understand", async (HttpContext context, AiQuota quota, IGeminiClient gemini) =>
        {
            context.Response.Headers.CacheControl = "no-store";
            var input = await AiInput.Read(context.Request, context.RequestAborted);
            var reservation = await quota.Reserve(ApiEndpoints.Actor(context), context.RequestAborted);
            try
            {
                var result = await gemini.Understand(input, context.RequestAborted);
                return Results.Ok(new JsonObject { ["result"] = result, ["source"] = "gemini" });
            }
            finally { await quota.Release(reservation); }
        });
    }
}

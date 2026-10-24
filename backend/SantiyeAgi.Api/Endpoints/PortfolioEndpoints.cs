using Microsoft.AspNetCore.Mvc;
using SantiyeAgi.Api.Infrastructure;
using SantiyeAgi.Api.Services;

namespace SantiyeAgi.Api.Endpoints;

public static class PortfolioEndpoints
{
    public static void MapPortfolio(this WebApplication app)
    {
        var api = app.MapGroup("/api/v1").RequireAuthorization().RequireRateLimiting("api");
        api.MapGet("/profiles/{owner:guid}/portfolio", (Guid owner, HttpContext ctx, PortfolioService service) => service.List(ApiEndpoints.Actor(ctx), owner));
        api.MapGet("/portfolio/{id:guid}/image", async (Guid id, HttpContext ctx, PortfolioService service) =>
        {
            var bytes = await service.Image(ApiEndpoints.Actor(ctx), id);
            ctx.Response.Headers.CacheControl = "no-store";
            ctx.Response.Headers.XContentTypeOptions = "nosniff";
            return Results.File(bytes, "image/jpeg");
        });
        api.MapPost("/portfolio", async (HttpContext ctx, PortfolioService service) =>
        {
            if (!ctx.Request.HasFormContentType) throw new ApiError("BAD_INPUT");
            var form = await ctx.Request.ReadFormAsync(ctx.RequestAborted);
            if (form.Files.Count != 1 || !Guid.TryParse(form["id"], out var id)) throw new ApiError("BAD_INPUT");
            return await service.Upload(ApiEndpoints.Actor(ctx), id, form["caption"].ToString(), form.Files[0], ctx.RequestAborted);
        }).WithMetadata(new RequestSizeLimitAttribute(PortfolioService.MaxBytes + 65536)).RequireRateLimiting("portfolio-upload");
        api.MapDelete("/portfolio/{id:guid}", async (Guid id, HttpContext ctx, PortfolioService service) =>
        {
            await service.Delete(ApiEndpoints.Actor(ctx), id);
            return Results.NoContent();
        });
    }
}

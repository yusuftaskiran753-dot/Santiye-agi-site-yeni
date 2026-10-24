using System.Security.Cryptography;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using SkiaSharp;
using SantiyeAgi.Api.Data;
using SantiyeAgi.Api.Infrastructure;

namespace SantiyeAgi.Api.Services;

public sealed class PortfolioService(AppDbContext db, MarketService market, Mutations mutations)
{
    public const int MaxBytes = 8 * 1024 * 1024;
    public const int MaxPhotos = 20;
    private static readonly SemaphoreSlim ImageSlots = new(2);

    private async Task Visible(Guid actor, Guid owner)
    {
        await market.ProfileUser(owner);
        await market.CheckBlock(actor, owner);
    }
    private static JsonObject Info(PortfolioPhoto p) => new()
    {
        ["id"] = p.Id.ToString(), ["owner_id"] = p.OwnerId.ToString(), ["caption"] = p.Caption,
        ["width"] = p.Width, ["height"] = p.Height, ["created_at"] = p.CreatedAt
    };
    public async Task<JsonArray> List(Guid actor, Guid owner)
    {
        await Visible(actor, owner);
        var photos = await db.PortfolioPhotos.AsNoTracking().Where(x => x.OwnerId == owner)
            .OrderByDescending(x => x.CreatedAt).ThenByDescending(x => x.Id)
            .Select(x => new PortfolioPhoto { Id = x.Id, OwnerId = x.OwnerId, Caption = x.Caption,
                Width = x.Width, Height = x.Height, CreatedAt = x.CreatedAt }).ToListAsync();
        return new JsonArray(photos.Select(p => (JsonNode)Info(p)).ToArray());
    }
    public async Task<byte[]> Image(Guid actor, Guid id)
    {
        var photo = await db.PortfolioPhotos.AsNoTracking().SingleOrDefaultAsync(x => x.Id == id)
            ?? throw new ApiError("NOT_FOUND", 404);
        await Visible(actor, photo.OwnerId);
        return photo.Data;
    }
    public async Task<JsonNode?> Upload(Guid actor, Guid id, string caption, IFormFile file, CancellationToken ct)
    {
        if (id == Guid.Empty || caption.Length > 200 || caption.Any(char.IsControl) || file.Length <= 0 || file.Length > MaxBytes)
            throw new ApiError("BAD_INPUT", detail: "Fotoğraf en fazla 8 MB, açıklama en fazla 200 karakter olmalı.");
        await market.ProfileUser(actor);
        await using var input = new MemoryStream();
        await file.CopyToAsync(input, ct);
        var raw = input.ToArray();
        // Dosya adı/MIME yerine gerçek görüntüyü doğrula; yeniden kodlama EXIF/GPS verisini kaldırır.
        var encoded = await Normalize(raw, ct);
        var fingerprint = new JsonObject { ["id"] = id.ToString(), ["caption"] = caption,
            ["sha256"] = Convert.ToHexString(SHA256.HashData(raw)) };
        return await mutations.Run(actor, id, "portfolio-upload", fingerprint, async () =>
        {
            await market.ProfileUser(actor);
            if (await db.PortfolioPhotos.CountAsync(x => x.OwnerId == actor) >= MaxPhotos)
                throw new ApiError("QUOTA", 409, "Profilinizde en fazla 20 iş fotoğrafı bulunabilir.");
            if (await db.PortfolioPhotos.AnyAsync(x => x.Id == id)) throw new ApiError("DUPLICATE", 409);
            var photo = new PortfolioPhoto { Id = id, OwnerId = actor, Caption = caption.Trim(),
                Data = encoded.Bytes, Width = encoded.Width, Height = encoded.Height };
            db.PortfolioPhotos.Add(photo);
            return Info(photo);
        });
    }
    public Task<JsonNode?> Delete(Guid actor, Guid id) => mutations.Run(actor, null, "portfolio-delete", new(), async () =>
    {
        var photo = await db.PortfolioPhotos.FindAsync(id) ?? throw new ApiError("NOT_FOUND", 404);
        if (photo.OwnerId != actor) throw new ApiError("FORBIDDEN", 403);
        db.PortfolioPhotos.Remove(photo);
        return null;
    });
    internal static async Task<(byte[] Bytes, int Width, int Height)> Normalize(byte[] raw, CancellationToken ct)
    {
        await ImageSlots.WaitAsync(ct);
        try
        {
            using var stream = new MemoryStream(raw);
            using var codec = SKCodec.Create(stream);
            if (codec is null || codec.EncodedFormat is not (SKEncodedImageFormat.Jpeg or SKEncodedImageFormat.Png or SKEncodedImageFormat.Webp)
                || codec.Info.Width <= 0 || codec.Info.Height <= 0 || codec.Info.Width > 8192 || codec.Info.Height > 8192
                || (long)codec.Info.Width * codec.Info.Height > 12_000_000)
                throw new ApiError("BAD_INPUT", detail: "JPG, PNG veya WebP fotoğraf seçin; görüntü en fazla 12 megapiksel olmalı.");
            using var bitmap = new SKBitmap(codec.Info.Width, codec.Info.Height);
            if (codec.GetPixels(bitmap.Info, bitmap.GetPixels()) != SKCodecResult.Success)
                throw new ApiError("BAD_INPUT", detail: "Fotoğraf okunamadı.");
            var rotated = codec.EncodedOrigin is SKEncodedOrigin.LeftTop or SKEncodedOrigin.RightTop or SKEncodedOrigin.RightBottom or SKEncodedOrigin.LeftBottom;
            var originalWidth = rotated ? bitmap.Height : bitmap.Width;
            var originalHeight = rotated ? bitmap.Width : bitmap.Height;
            var scale = Math.Min(1d, 1600d / Math.Max(originalWidth, originalHeight));
            var width = Math.Max(1, (int)Math.Round(originalWidth * scale));
            var height = Math.Max(1, (int)Math.Round(originalHeight * scale));
            using var normalized = new SKBitmap(width, height);
            using (var canvas = new SKCanvas(normalized))
            {
                canvas.Clear(SKColors.White);
                canvas.Scale((float)width / originalWidth, (float)height / originalHeight);
                switch (codec.EncodedOrigin)
                {
                    case SKEncodedOrigin.TopRight: canvas.Translate(bitmap.Width, 0); canvas.Scale(-1, 1); break;
                    case SKEncodedOrigin.BottomRight: canvas.Translate(bitmap.Width, bitmap.Height); canvas.RotateDegrees(180); break;
                    case SKEncodedOrigin.BottomLeft: canvas.Translate(0, bitmap.Height); canvas.Scale(1, -1); break;
                    case SKEncodedOrigin.LeftTop: canvas.RotateDegrees(90); canvas.Scale(1, -1); break;
                    case SKEncodedOrigin.RightTop: canvas.Translate(bitmap.Height, 0); canvas.RotateDegrees(90); break;
                    case SKEncodedOrigin.RightBottom: canvas.Translate(bitmap.Height, bitmap.Width); canvas.RotateDegrees(90); canvas.Scale(-1, 1); break;
                    case SKEncodedOrigin.LeftBottom: canvas.Translate(0, bitmap.Width); canvas.RotateDegrees(-90); break;
                }
                using var image = SKImage.FromBitmap(bitmap);
                canvas.DrawImage(image, 0, 0, new SKSamplingOptions(SKFilterMode.Linear));
            }
            using var result = SKImage.FromBitmap(normalized);
            using var data = result.Encode(SKEncodedImageFormat.Jpeg, 85);
            return (data.ToArray(), width, height);
        }
        finally { ImageSlots.Release(); }
    }
}

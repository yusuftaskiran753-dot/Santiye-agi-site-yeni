using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using SantiyeAgi.Api.Data;

namespace SantiyeAgi.Api.Auth;

public sealed class TokenService(IConfiguration config)
{
    public string SigningKey => config["Auth:SigningKey"] ?? throw new InvalidOperationException("Auth:SigningKey required");
    public string Issuer => config["Auth:Issuer"] ?? "SantiyeAgi";
    public string Audience => config["Auth:Audience"] ?? "SantiyeAgi.Mobile";
    public static string Hash(string secret) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(secret)));
    public static string NewRefresh() => Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
    public string ChallengeHash(string phone, string code) => Convert.ToHexString(HMACSHA256.HashData(Encoding.UTF8.GetBytes(SigningKey), Encoding.UTF8.GetBytes(phone + ":" + code)));
    public JsonObject Issue(User user, Session session, string refresh)
    {
        var expires = DateTime.UtcNow.AddMinutes(15);
        var access = new JsonWebTokenHandler().CreateToken(new SecurityTokenDescriptor
        {
            Issuer = Issuer, Audience = Audience, Expires = expires,
            Subject = new ClaimsIdentity([new("sub", user.Id.ToString()), new("sid", session.Id.ToString())]),
            SigningCredentials = new(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(SigningKey)), SecurityAlgorithms.HmacSha256)
        });
        return new() { ["access_token"] = access, ["refresh_token"] = refresh, ["user_id"] = user.Id.ToString(), ["expires_at"] = expires, ["phone_verified"] = user.PhoneVerified };
    }
}

namespace SantiyeAgi.Api.Auth;

public static class AuthPolicy
{
    public static bool RequiresPhone(IConfiguration config) =>
        config.GetValue<bool?>("Auth:RequirePhoneVerification") ?? true;
}

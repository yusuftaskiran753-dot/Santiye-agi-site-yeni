using SantiyeAgi.Api.Auth;

namespace SantiyeAgi.Api.Tests;

public class AccountPasswordTests
{
    [Fact]
    public void HashesAreSaltedAndWrongCredentialsFail()
    {
        const string password = "Only-a-local-test-password-723!";
        var first = AccountPassword.Hash(password);
        var second = AccountPassword.Hash(password);
        Assert.NotEqual(first, second);
        Assert.DoesNotContain(password, first);
        Assert.True(AccountPassword.Verify(password, first));
        Assert.False(AccountPassword.Verify(password + "x", first));
        Assert.False(AccountPassword.Verify("short", first));
    }

    [Theory]
    [InlineData("")]
    [InlineData("pbkdf2-sha256$2147483647$bad$bad")]
    [InlineData("pbkdf2-sha256$600000$bad$bad")]
    public void MalformedOrUnboundedParametersAreRejected(string encoded) =>
        Assert.False(AccountPassword.Verify("Only-a-local-test-password-723!", encoded));
}

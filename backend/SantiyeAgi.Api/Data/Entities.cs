namespace SantiyeAgi.Api.Data;

public sealed class HaulPoint
{
    public Guid Id { get; set; }
    public Guid OwnerId { get; set; }
    public string Data { get; set; } = "{}";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class PortfolioPhoto
{
    public Guid Id { get; set; }
    public Guid OwnerId { get; set; }
    public string Caption { get; set; } = "";
    public byte[] Data { get; set; } = [];
    public int Width { get; set; }
    public int Height { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed class User
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string? Phone { get; set; }
    public bool PhoneVerified { get; set; }
    public string Name { get; set; } = "";
    public string Company { get; set; } = "";
    public string Role { get; set; } = "nakliyeci";
    public string City { get; set; } = "";
    public bool ProfileComplete { get; set; }
    public int Credits { get; set; }
    public DateTimeOffset? PremiumUntil { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}
public sealed class Session
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string RefreshHash { get; set; } = "";
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? RevokedAt { get; set; }
}
public sealed class PhoneChallenge
{
    public string Phone { get; set; } = "";
    public string CodeHash { get; set; } = "";
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset SentAt { get; set; }
    public int Attempts { get; set; }
}
public sealed class Listing
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OwnerId { get; set; }
    public string Kind { get; set; } = "";
    public string Status { get; set; } = "active";
    public bool Hidden { get; set; }
    public string Data { get; set; } = "{}";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? BoostedUntil { get; set; }
}
public sealed class TradeRequest
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OwnerId { get; set; }
    public Guid RequesterId { get; set; }
    public Guid ListingId { get; set; }
    public string Kind { get; set; } = "";
    public string Status { get; set; } = "pending";
    public Guid? DealId { get; set; }
    public string Data { get; set; } = "{}";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}
public sealed class Deal
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Code { get; set; } = "";
    public Guid? CustomerId { get; set; }
    public Guid? ProviderId { get; set; }
    public Guid? CreatedBy { get; set; }
    public Guid? RequestId { get; set; }
    public string Status { get; set; } = "pending";
    public string Data { get; set; } = "{}";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}
public sealed class Rating
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid DealId { get; set; }
    public Guid? FromId { get; set; }
    public Guid ToId { get; set; }
    public int Stars { get; set; }
    public string Comment { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}
public sealed class Block
{
    public Guid BlockerId { get; set; }
    public Guid BlockedId { get; set; }
}
public sealed class Unlock
{
    public Guid UserId { get; set; }
    public Guid ListingId { get; set; }
    public string Kind { get; set; } = "";
    public string Method { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}
public sealed class Notification
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Title { get; set; } = "";
    public string Body { get; set; } = "";
    public string RefType { get; set; } = "";
    public Guid? RefId { get; set; }
    public DateTimeOffset? ReadAt { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}
public sealed class Report
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ReporterId { get; set; }
    public string TargetType { get; set; } = "";
    public Guid TargetId { get; set; }
    public string Reason { get; set; } = "";
    public string Note { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}
public sealed class ClientOperation
{
    public Guid UserId { get; set; }
    public Guid Id { get; set; }
    public string Kind { get; set; } = "";
    public string Fingerprint { get; set; } = "";
    public string Result { get; set; } = "null";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}
public sealed class CreditEntry
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public int Delta { get; set; }
    public string Reason { get; set; } = "";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

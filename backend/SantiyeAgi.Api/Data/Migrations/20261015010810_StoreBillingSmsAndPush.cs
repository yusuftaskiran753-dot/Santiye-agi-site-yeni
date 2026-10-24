using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SantiyeAgi.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class StoreBillingSmsAndPush : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "PhoneOtpQuotas",
                schema: "santiye",
                columns: table => new
                {
                    Phone = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    LastAttemptAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    HourStart = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    HourCount = table.Column<int>(type: "integer", nullable: false),
                    DayStart = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    DayCount = table.Column<int>(type: "integer", nullable: false),
                    DevelopmentChallenge = table.Column<bool>(type: "boolean", nullable: false),
                    ChallengeGeneration = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PhoneOtpQuotas", x => x.Phone);
                });

            migrationBuilder.CreateTable(
                name: "PushDevices",
                schema: "santiye",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    InstallationId = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    SessionId = table.Column<Guid>(type: "uuid", nullable: false),
                    Token = table.Column<string>(type: "character varying(4096)", maxLength: 4096, nullable: false),
                    TokenHash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    Platform = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    RegisteredAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PushDevices", x => x.Id);
                    table.ForeignKey(
                        name: "FK_PushDevices_Sessions_SessionId",
                        column: x => x.SessionId,
                        principalSchema: "santiye",
                        principalTable: "Sessions",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_PushDevices_Users_UserId",
                        column: x => x.UserId,
                        principalSchema: "santiye",
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "PushOutbox",
                schema: "santiye",
                columns: table => new
                {
                    NotificationId = table.Column<Guid>(type: "uuid", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ExpandedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PushOutbox", x => x.NotificationId);
                    table.ForeignKey(
                        name: "FK_PushOutbox_Notifications_NotificationId",
                        column: x => x.NotificationId,
                        principalSchema: "santiye",
                        principalTable: "Notifications",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "StoreCreditDebts",
                schema: "santiye",
                columns: table => new
                {
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Amount = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_StoreCreditDebts", x => x.UserId);
                    table.ForeignKey(
                        name: "FK_StoreCreditDebts_Users_UserId",
                        column: x => x.UserId,
                        principalSchema: "santiye",
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "StorePurchases",
                schema: "santiye",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: true),
                    Platform = table.Column<string>(type: "character varying(10)", maxLength: 10, nullable: false),
                    KeyHash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    ProtectedReference = table.Column<string>(type: "text", nullable: false),
                    ProductId = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Kind = table.Column<string>(type: "text", nullable: false),
                    State = table.Column<string>(type: "text", nullable: false),
                    Environment = table.Column<string>(type: "text", nullable: false),
                    CreditsAwarded = table.Column<int>(type: "integer", nullable: false),
                    CreditsRevoked = table.Column<int>(type: "integer", nullable: false),
                    ReportedRefundCredits = table.Column<int>(type: "integer", nullable: false),
                    VoidRefundCredits = table.Column<int>(type: "integer", nullable: false),
                    EntitledUntil = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    CheckedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    NextCheckAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    Acknowledged = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_StorePurchases", x => x.Id);
                    table.ForeignKey(
                        name: "FK_StorePurchases_Users_UserId",
                        column: x => x.UserId,
                        principalSchema: "santiye",
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "PushDeliveries",
                schema: "santiye",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    NotificationId = table.Column<Guid>(type: "uuid", nullable: false),
                    DeviceId = table.Column<Guid>(type: "uuid", nullable: false),
                    Attempts = table.Column<int>(type: "integer", nullable: false),
                    NextAttemptAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    CompletedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    LastResult = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PushDeliveries", x => x.Id);
                    table.ForeignKey(
                        name: "FK_PushDeliveries_Notifications_NotificationId",
                        column: x => x.NotificationId,
                        principalSchema: "santiye",
                        principalTable: "Notifications",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_PushDeliveries_PushDevices_DeviceId",
                        column: x => x.DeviceId,
                        principalSchema: "santiye",
                        principalTable: "PushDevices",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "StoreRefunds",
                schema: "santiye",
                columns: table => new
                {
                    EventHash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    PurchaseId = table.Column<Guid>(type: "uuid", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_StoreRefunds", x => x.EventHash);
                    table.ForeignKey(
                        name: "FK_StoreRefunds_StorePurchases_PurchaseId",
                        column: x => x.PurchaseId,
                        principalSchema: "santiye",
                        principalTable: "StorePurchases",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_PhoneOtpQuotas_LastAttemptAt",
                schema: "santiye",
                table: "PhoneOtpQuotas",
                column: "LastAttemptAt");

            migrationBuilder.CreateIndex(
                name: "IX_PushDeliveries_CompletedAt_NextAttemptAt",
                schema: "santiye",
                table: "PushDeliveries",
                columns: new[] { "CompletedAt", "NextAttemptAt" });

            migrationBuilder.CreateIndex(
                name: "IX_PushDeliveries_DeviceId",
                schema: "santiye",
                table: "PushDeliveries",
                column: "DeviceId");

            migrationBuilder.CreateIndex(
                name: "IX_PushDeliveries_NotificationId_DeviceId",
                schema: "santiye",
                table: "PushDeliveries",
                columns: new[] { "NotificationId", "DeviceId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_PushDevices_SessionId",
                schema: "santiye",
                table: "PushDevices",
                column: "SessionId");

            migrationBuilder.CreateIndex(
                name: "IX_PushDevices_TokenHash",
                schema: "santiye",
                table: "PushDevices",
                column: "TokenHash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_PushDevices_UserId_InstallationId",
                schema: "santiye",
                table: "PushDevices",
                columns: new[] { "UserId", "InstallationId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_PushOutbox_ExpandedAt_CreatedAt",
                schema: "santiye",
                table: "PushOutbox",
                columns: new[] { "ExpandedAt", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_StorePurchases_NextCheckAt",
                schema: "santiye",
                table: "StorePurchases",
                column: "NextCheckAt");

            migrationBuilder.CreateIndex(
                name: "IX_StorePurchases_Platform_KeyHash",
                schema: "santiye",
                table: "StorePurchases",
                columns: new[] { "Platform", "KeyHash" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_StorePurchases_UserId",
                schema: "santiye",
                table: "StorePurchases",
                column: "UserId");

            migrationBuilder.CreateIndex(
                name: "IX_StoreRefunds_PurchaseId",
                schema: "santiye",
                table: "StoreRefunds",
                column: "PurchaseId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "PhoneOtpQuotas",
                schema: "santiye");

            migrationBuilder.DropTable(
                name: "PushDeliveries",
                schema: "santiye");

            migrationBuilder.DropTable(
                name: "PushOutbox",
                schema: "santiye");

            migrationBuilder.DropTable(
                name: "StoreCreditDebts",
                schema: "santiye");

            migrationBuilder.DropTable(
                name: "StoreRefunds",
                schema: "santiye");

            migrationBuilder.DropTable(
                name: "PushDevices",
                schema: "santiye");

            migrationBuilder.DropTable(
                name: "StorePurchases",
                schema: "santiye");
        }
    }
}

using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SantiyeAgi.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddAiAndLiveLocation : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "AiUsage",
                schema: "santiye",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    LeaseUntil = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AiUsage", x => x.Id);
                    table.ForeignKey(
                        name: "FK_AiUsage_Users_UserId",
                        column: x => x.UserId,
                        principalSchema: "santiye",
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "LiveLocationShares",
                schema: "santiye",
                columns: table => new
                {
                    DealId = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Generation = table.Column<Guid>(type: "uuid", nullable: false),
                    Lat = table.Column<double>(type: "double precision", nullable: true),
                    Lng = table.Column<double>(type: "double precision", nullable: true),
                    Accuracy = table.Column<double>(type: "double precision", nullable: true),
                    Heading = table.Column<double>(type: "double precision", nullable: true),
                    Speed = table.Column<double>(type: "double precision", nullable: true),
                    FixAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    StartedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ExpiresAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    StoppedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    UntilDelivered = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_LiveLocationShares", x => new { x.DealId, x.UserId });
                    table.CheckConstraint("live_duration_cap", "\"ExpiresAt\" <= \"StartedAt\" + INTERVAL '24 hours'");
                    table.CheckConstraint("live_lat_range", "\"Lat\" IS NULL OR (\"Lat\" >= -90 AND \"Lat\" <= 90)");
                    table.CheckConstraint("live_lng_range", "\"Lng\" IS NULL OR (\"Lng\" >= -180 AND \"Lng\" <= 180)");
                    table.ForeignKey(
                        name: "FK_LiveLocationShares_Deals_DealId",
                        column: x => x.DealId,
                        principalSchema: "santiye",
                        principalTable: "Deals",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_LiveLocationShares_Users_UserId",
                        column: x => x.UserId,
                        principalSchema: "santiye",
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_AiUsage_CreatedAt",
                schema: "santiye",
                table: "AiUsage",
                column: "CreatedAt");

            migrationBuilder.CreateIndex(
                name: "IX_AiUsage_LeaseUntil",
                schema: "santiye",
                table: "AiUsage",
                column: "LeaseUntil");

            migrationBuilder.CreateIndex(
                name: "IX_AiUsage_UserId_CreatedAt",
                schema: "santiye",
                table: "AiUsage",
                columns: new[] { "UserId", "CreatedAt" });

            migrationBuilder.CreateIndex(
                name: "IX_LiveLocationShares_ExpiresAt",
                schema: "santiye",
                table: "LiveLocationShares",
                column: "ExpiresAt");

            migrationBuilder.CreateIndex(
                name: "IX_LiveLocationShares_StoppedAt",
                schema: "santiye",
                table: "LiveLocationShares",
                column: "StoppedAt");

            migrationBuilder.CreateIndex(
                name: "IX_LiveLocationShares_UserId",
                schema: "santiye",
                table: "LiveLocationShares",
                column: "UserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "AiUsage",
                schema: "santiye");

            migrationBuilder.DropTable(
                name: "LiveLocationShares",
                schema: "santiye");
        }
    }
}

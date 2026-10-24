using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SantiyeAgi.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddPortfolioPhotos : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "PortfolioPhotos",
                schema: "santiye",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    OwnerId = table.Column<Guid>(type: "uuid", nullable: false),
                    Caption = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Data = table.Column<byte[]>(type: "bytea", nullable: false),
                    Width = table.Column<int>(type: "integer", nullable: false),
                    Height = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PortfolioPhotos", x => x.Id);
                    table.ForeignKey(
                        name: "FK_PortfolioPhotos_Users_OwnerId",
                        column: x => x.OwnerId,
                        principalSchema: "santiye",
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_PortfolioPhotos_OwnerId_CreatedAt",
                schema: "santiye",
                table: "PortfolioPhotos",
                columns: new[] { "OwnerId", "CreatedAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "PortfolioPhotos",
                schema: "santiye");
        }
    }
}

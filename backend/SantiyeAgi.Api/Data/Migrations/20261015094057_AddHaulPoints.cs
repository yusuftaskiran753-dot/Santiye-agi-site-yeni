using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SantiyeAgi.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddHaulPoints : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "HaulPoints",
                schema: "santiye",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    OwnerId = table.Column<Guid>(type: "uuid", nullable: false),
                    Data = table.Column<string>(type: "jsonb", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_HaulPoints", x => x.Id);
                    table.ForeignKey(
                        name: "FK_HaulPoints_Users_OwnerId",
                        column: x => x.OwnerId,
                        principalSchema: "santiye",
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_HaulPoints_OwnerId",
                schema: "santiye",
                table: "HaulPoints",
                column: "OwnerId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "HaulPoints",
                schema: "santiye");
        }
    }
}

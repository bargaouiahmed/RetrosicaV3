using downloader.Db;
using Microsoft.EntityFrameworkCore;

namespace downloader.Controllers;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<DownloadJob> DownloadJobs => Set<DownloadJob>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<DownloadJob>(entity =>
        {
            entity.HasKey(job => job.Id);
            entity.HasIndex(job => new { job.VideoId, job.Format }).IsUnique();
            entity.HasIndex(job => new { job.Status, job.ExpiresAt });
            entity.Property(job => job.VideoId).HasMaxLength(11);
            entity.Property(job => job.Format).HasMaxLength(8);
            entity.Property(job => job.Status).HasMaxLength(16);
        });
    }
}

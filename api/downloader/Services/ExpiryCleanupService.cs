using downloader.Controllers;
using Microsoft.EntityFrameworkCore;

namespace downloader.Services;

public sealed class ExpiryCleanupService(
    IDbContextFactory<AppDbContext> dbFactory,
    IConfiguration configuration,
    IHostEnvironment environment,
    ILogger<ExpiryCleanupService> logger) : BackgroundService
{
    private readonly string _dataDirectory = Path.GetFullPath(
        configuration["DataDirectory"] ?? Path.Combine(environment.ContentRootPath, "data"));

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try { await CleanupAsync(stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception error) { logger.LogError(error, "Download retention cleanup failed"); }
            await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
        }
    }

    private async Task CleanupAsync(CancellationToken cancellationToken)
    {
        await using var db = await dbFactory.CreateDbContextAsync(cancellationToken);
        var expired = await db.DownloadJobs
            .Where(job => job.Status == "completed" && job.ExpiresAt <= DateTimeOffset.UtcNow)
            .ToListAsync(cancellationToken);
        foreach (var job in expired)
        {
            if (!string.IsNullOrWhiteSpace(job.FilePath) && File.Exists(job.FilePath))
            {
                try { File.Delete(job.FilePath); }
                catch (IOException error)
                {
                    logger.LogWarning(error, "Could not delete expired MP3 {Path}", job.FilePath);
                    continue;
                }
            }
            db.DownloadJobs.Remove(job);
        }
        await db.SaveChangesAsync(cancellationToken);

        var workDirectory = Path.Combine(_dataDirectory, "work");
        if (!Directory.Exists(workDirectory)) return;
        var activeJobs = await db.DownloadJobs
            .Where(job => job.Status == "queued" || job.Status == "downloading")
            .Select(job => job.Id)
            .ToHashSetAsync(cancellationToken);
        foreach (var directory in Directory.EnumerateDirectories(workDirectory))
        {
            try
            {
                var name = Path.GetFileName(directory);
                if (Guid.TryParseExact(name, "N", out var jobId) && activeJobs.Contains(jobId))
                    continue;
                if (Directory.GetLastWriteTimeUtc(directory) < DateTime.UtcNow.AddHours(-2))
                    Directory.Delete(directory, recursive: true);
            }
            catch (IOException error) { logger.LogDebug(error, "Could not delete work directory {Path}", directory); }
        }
    }
}

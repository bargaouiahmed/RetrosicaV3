using System.Threading.Channels;
using downloader.Controllers;
using downloader.Db;
using Microsoft.EntityFrameworkCore;
using YoutubeDLSharp;
using YoutubeDLSharp.Options;

namespace downloader.Services;

public sealed class DownloadCoordinator(
    IDbContextFactory<AppDbContext> dbFactory,
    ILogger<DownloadCoordinator> logger,
    IConfiguration configuration,
    IHostEnvironment environment) : BackgroundService
{
    private readonly Channel<Guid> _queue = Channel.CreateBounded<Guid>(
        new BoundedChannelOptions(100) { FullMode = BoundedChannelFullMode.Wait });
    private readonly SemaphoreSlim _parallelism = new(2, 2);
    private readonly SemaphoreSlim _requestGate = new(1, 1);
    private readonly string _dataDirectory = Path.GetFullPath(
        configuration["DataDirectory"] ?? Path.Combine(environment.ContentRootPath, "data"));

    public async Task<DownloadJob> QueueAsync(string videoId, CancellationToken cancellationToken)
    {
        await _requestGate.WaitAsync(cancellationToken);
        try
        {
            await using var db = await dbFactory.CreateDbContextAsync(cancellationToken);
            var now = DateTimeOffset.UtcNow;
            var job = await db.DownloadJobs.SingleOrDefaultAsync(
                item => item.VideoId == videoId && item.Format == "mp3", cancellationToken);
            var shouldQueue = false;

            if (job is { Status: "completed" } && job.ExpiresAt > now &&
                job.FilePath is not null && File.Exists(job.FilePath))
            {
                job.CacheHits++;
                job.ExpiresAt = now.AddHours(Math.Min(
                    Math.Pow(2, job.CacheHits), (DateTimeOffset.MaxValue - now).TotalHours));
            }
            else if (job is { Status: "queued" or "downloading" })
            {
                job.CacheHits++;
            }
            else
            {
                var staleFile = job?.FilePath ?? Path.Combine(_dataDirectory, "files", $"{videoId}.mp3");
                if (File.Exists(staleFile)) File.Delete(staleFile);
                if (job is null)
                {
                    job = new DownloadJob { Id = Guid.NewGuid(), VideoId = videoId };
                    db.DownloadJobs.Add(job);
                }
                job.Status = "queued";
                job.CreatedAt = now;
                job.CompletedAt = null;
                job.ExpiresAt = null;
                job.FilePath = null;
                job.CacheHits = 0;
                job.ProgressPercentage = 0;
                job.ErrorMessage = null;
                shouldQueue = true;
            }

            await db.SaveChangesAsync(cancellationToken);
            if (shouldQueue) await _queue.Writer.WriteAsync(job.Id, cancellationToken);
            return job;
        }
        finally
        {
            _requestGate.Release();
        }
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        Directory.CreateDirectory(Path.Combine(_dataDirectory, "files"));
        Directory.CreateDirectory(Path.Combine(_dataDirectory, "work"));

        await using (var db = await dbFactory.CreateDbContextAsync(stoppingToken))
        {
            var interrupted = await db.DownloadJobs
                .Where(job => job.Status == "downloading")
                .ToListAsync(stoppingToken);
            foreach (var job in interrupted) job.Status = "queued";
            await db.SaveChangesAsync(stoppingToken);

            var queuedIds = await db.DownloadJobs
                .Where(job => job.Status == "queued")
                .Select(job => job.Id)
                .ToListAsync(stoppingToken);
            foreach (var id in queuedIds) await _queue.Writer.WriteAsync(id, stoppingToken);
        }

        await Task.WhenAll(Enumerable.Range(0, 2).Select(_ => ConsumeAsync(stoppingToken)));
    }

    private async Task ConsumeAsync(CancellationToken cancellationToken)
    {
        await foreach (var id in _queue.Reader.ReadAllAsync(cancellationToken))
        {
            await _parallelism.WaitAsync(cancellationToken);
            try { await ProcessAsync(id, cancellationToken); }
            finally { _parallelism.Release(); }
        }
    }

    private async Task ProcessAsync(Guid id, CancellationToken cancellationToken)
    {
        await using var db = await dbFactory.CreateDbContextAsync(cancellationToken);
        var job = await db.DownloadJobs.SingleOrDefaultAsync(item => item.Id == id, cancellationToken);
        if (job is null || job.Status != "queued") return;

        job.Status = "downloading";
        await db.SaveChangesAsync(cancellationToken);
        var workDirectory = Path.Combine(_dataDirectory, "work", id.ToString("N"));
        Directory.CreateDirectory(workDirectory);
        try
        {
            var downloader = new YoutubeDL
            {
                YoutubeDLPath = configuration["YtDlpPath"] ?? "yt-dlp",
                FFmpegPath = configuration["FfmpegPath"] ?? "ffmpeg",
                OutputFolder = workDirectory
            };
            var latestProgress = -1;
            var progress = new InlineProgress<DownloadProgress>(value =>
            {
                var percentage = Math.Clamp((int)Math.Round(value.Progress * 100), 0, 99);
                if (percentage == latestProgress) return;
                latestProgress = percentage;
                SaveProgressAsync(id, percentage, cancellationToken).GetAwaiter().GetResult();
            });
            var url = $"https://www.youtube.com/watch?v={job.VideoId}";
            var result = await downloader.RunAudioDownload(
                url,
                AudioConversionFormat.Mp3,
                cancellationToken,
                progress);

            if (!result.Success || string.IsNullOrWhiteSpace(result.Data) || !File.Exists(result.Data))
                throw new InvalidOperationException(string.Join("\n", result.ErrorOutput));

            var finalPath = Path.Combine(_dataDirectory, "files", $"{job.VideoId}.mp3");
            if (File.Exists(finalPath)) File.Delete(finalPath);
            File.Move(result.Data, finalPath);

            await db.Entry(job).ReloadAsync(cancellationToken);
            job.Status = "completed";
            job.ProgressPercentage = 100;
            job.FilePath = finalPath;
            job.CompletedAt = DateTimeOffset.UtcNow;
            job.ExpiresAt = job.CompletedAt.Value.AddHours(Math.Pow(2, job.CacheHits));
            job.ErrorMessage = null;
            await db.SaveChangesAsync(cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            job.Status = "queued";
            await db.SaveChangesAsync(CancellationToken.None);
            throw;
        }
        catch (Exception error)
        {
            logger.LogError(error, "Download job {JobId} failed", id);
            job.Status = "failed";
            job.ErrorMessage = string.IsNullOrWhiteSpace(error.Message)
                ? "The media download failed."
                : error.Message[..Math.Min(error.Message.Length, 500)];
            await db.SaveChangesAsync(CancellationToken.None);
        }
        finally
        {
            try { Directory.Delete(workDirectory, recursive: true); }
            catch (IOException error) { logger.LogWarning(error, "Could not remove work directory {Path}", workDirectory); }
        }
    }

    private async Task SaveProgressAsync(Guid id, int percentage, CancellationToken cancellationToken)
    {
        await using var db = await dbFactory.CreateDbContextAsync(cancellationToken);
        await db.DownloadJobs.Where(job => job.Id == id && job.Status == "downloading")
            .ExecuteUpdateAsync(update => update.SetProperty(job => job.ProgressPercentage, percentage), cancellationToken);
    }

    private sealed class InlineProgress<T>(Action<T> report) : IProgress<T>
    {
        public void Report(T value) => report(value);
    }
}

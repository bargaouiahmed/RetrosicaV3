using downloader.Controllers;
using downloader.Db;
using downloader.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace downloader.Api;

[ApiController]
[Route("api/downloads")]
public sealed class DownloadsController(
    DownloadCoordinator coordinator,
    IDbContextFactory<AppDbContext> dbFactory,
    IConfiguration configuration) : ControllerBase
{
    [HttpPost]
    [ProducesResponseType<DownloadJobResponse>(StatusCodes.Status202Accepted)]
    public async Task<IActionResult> Create([FromBody] CreateDownloadRequest request, CancellationToken cancellationToken)
    {
        if (!string.Equals(request.Format ?? "mp3", "mp3", StringComparison.OrdinalIgnoreCase))
            return BadRequest(new { error = "Only MP3 downloads are supported." });
        if (!TryGetVideoId(request.Url, out var videoId))
            return BadRequest(new { error = "Provide a valid YouTube video URL or ID." });

        var job = await coordinator.QueueAsync(videoId, cancellationToken);
        var response = Map(job);
        return AcceptedAtAction(nameof(Get), new { id = job.Id }, response);
    }

    [HttpPost("file")]
    [Produces("audio/mpeg")]
    public async Task<IActionResult> CreateAndStreamFile(
        [FromBody] CreateDownloadRequest request,
        CancellationToken cancellationToken)
    {
        if (!string.Equals(request.Format ?? "mp3", "mp3", StringComparison.OrdinalIgnoreCase))
            return BadRequest(new { error = "Only MP3 downloads are supported." });
        if (!TryGetVideoId(request.Url, out var videoId))
            return BadRequest(new { error = "Provide a valid YouTube video URL or ID." });

        var queuedJob = await coordinator.QueueAsync(videoId, cancellationToken);
        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();
            await using var db = await dbFactory.CreateDbContextAsync(cancellationToken);
            var job = await db.DownloadJobs.SingleOrDefaultAsync(
                item => item.Id == queuedJob.Id, cancellationToken);
            if (job is null) return NotFound();

            if (job.Status == "completed" && job.FilePath is not null &&
                System.IO.File.Exists(job.FilePath))
            {
                return PhysicalFile(
                    job.FilePath,
                    "audio/mpeg",
                    $"{job.VideoId}.mp3",
                    enableRangeProcessing: true);
            }

            if (job.Status == "failed")
                return StatusCode(StatusCodes.Status502BadGateway, new
                {
                    error = job.ErrorMessage ?? "The MP3 conversion failed."
                });

            await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken);
        }
    }

    [HttpGet("{id:guid}")]
    [ProducesResponseType<DownloadJobResponse>(StatusCodes.Status200OK)]
    public async Task<IActionResult> Get(Guid id, CancellationToken cancellationToken)
    {
        await using var db = await dbFactory.CreateDbContextAsync(cancellationToken);
        var job = await db.DownloadJobs.SingleOrDefaultAsync(item => item.Id == id, cancellationToken);
        return job is null ? NotFound() : Ok(Map(job));
    }

    [HttpGet("{id:guid}/file")]
    public async Task<IActionResult> File(Guid id, CancellationToken cancellationToken)
    {
        await using var db = await dbFactory.CreateDbContextAsync(cancellationToken);
        var job = await db.DownloadJobs.SingleOrDefaultAsync(item => item.Id == id, cancellationToken);
        if (job is null) return NotFound();
        if (job.Status != "completed" || job.FilePath is null || !System.IO.File.Exists(job.FilePath))
            return Conflict(new { error = "The MP3 is not available yet." });
        return PhysicalFile(job.FilePath, "audio/mpeg", $"{job.VideoId}.mp3", enableRangeProcessing: true);
    }

    private DownloadJobResponse Map(DownloadJob job)
    {
        var baseUrl = configuration["PublicBaseUrl"]?.TrimEnd('/');
        var fileUrl = job.Status == "completed"
            ? $"{baseUrl ?? string.Empty}/api/downloads/{job.Id}/file"
            : null;
        return new DownloadJobResponse(
            job.Id,
            job.VideoId,
            job.Status,
            job.ProgressPercentage,
            fileUrl,
            job.ErrorMessage,
            job.ExpiresAt);
    }

    private static bool TryGetVideoId(string? input, out string videoId)
    {
        videoId = string.Empty;
        if (string.IsNullOrWhiteSpace(input)) return false;
        var value = input.Trim();
        if (System.Text.RegularExpressions.Regex.IsMatch(value, "^[A-Za-z0-9_-]{11}$"))
        {
            videoId = value;
            return true;
        }

        if (!value.Contains("://", StringComparison.Ordinal)) value = $"https://{value}";
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri)) return false;
        var host = uri.Host.ToLowerInvariant();
        var youtubeHost = host is "youtube.com" or "www.youtube.com" or "m.youtube.com" or "music.youtube.com" or "youtu.be" || host.EndsWith(".youtube.com", StringComparison.Ordinal);
        if (!youtubeHost) return false;

        string? id = host == "youtu.be"
            ? uri.AbsolutePath.Trim('/').Split('/').FirstOrDefault()
            : uri.AbsolutePath == "/watch"
                ? Microsoft.AspNetCore.WebUtilities.QueryHelpers.ParseQuery(uri.Query).GetValueOrDefault("v").FirstOrDefault()
                : uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries) is ["shorts" or "embed" or "live", var routeId, ..]
                    ? routeId
                    : null;
        if (id is null || !System.Text.RegularExpressions.Regex.IsMatch(id, "^[A-Za-z0-9_-]{11}$")) return false;
        videoId = id;
        return true;
    }
}

public sealed record CreateDownloadRequest(string Url, string? Format = "mp3");
public sealed record DownloadJobResponse(
    Guid Id,
    string VideoId,
    string Status,
    int Progress,
    string? DownloadUrl,
    string? Error,
    DateTimeOffset? ExpiresAt);

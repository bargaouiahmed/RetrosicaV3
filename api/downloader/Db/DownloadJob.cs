namespace downloader.Db;

public class DownloadJob
{
    public Guid Id { get; set; }
    public required string VideoId { get; set; }
    public string Format { get; set; } = "mp3";
    public string Status { get; set; } = "queued";
    public string? FilePath { get; set; }
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? CompletedAt { get; set; }
    public DateTimeOffset? ExpiresAt { get; set; }
    public int CacheHits { get; set; }
    public int ProgressPercentage { get; set; }
    public string? ErrorMessage { get; set; }
}

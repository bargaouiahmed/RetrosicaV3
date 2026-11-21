using System.Collections.Concurrent;
using System.Text.Json;
using System.Threading.Channels;
using downloader.Api;

namespace downloader.Services;

public sealed record TtsJobStatus(
    string Id,
    string State,
    string? Error,
    DateTime CreatedAtUtc,
    DateTime? CompletedAtUtc = null,
    DateTime? DownloadedAtUtc = null,
    DateTime? ExpiresAtUtc = null);

public sealed class TtsJobQueue(
    IConfiguration configuration,
    KokoroSynthesisService synthesis,
    ILogger<TtsJobQueue> logger) : BackgroundService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly Channel<string> _pending = Channel.CreateUnbounded<string>();
    private readonly ConcurrentDictionary<string, Job> _jobs = new();
    private readonly string _directory = Path.Combine(
        configuration["DataDirectory"] ?? Path.Combine(AppContext.BaseDirectory, "data"),
        "tts-jobs");

    public override async Task StartAsync(CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(_directory);
        await RecoverJobsAsync(cancellationToken);
        await base.StartAsync(cancellationToken);
    }

    public async Task<TtsJobStatus> EnqueueAsync(
        TtsGenerationRequest request,
        CancellationToken cancellationToken)
    {
        var id = Guid.NewGuid().ToString("N");
        var job = new Job(id, request, "queued", null, DateTime.UtcNow);
        await WriteJsonAsync(RequestPath(id), request, cancellationToken);
        await PersistStatusAsync(job, cancellationToken);
        _jobs[id] = job;
        await _pending.Writer.WriteAsync(id, cancellationToken);
        return job.Status;
    }

    public TtsJobStatus? GetStatus(string id) =>
        _jobs.TryGetValue(id, out var job) ? job.Status : null;

    public async Task<TtsJobStatus?> WaitForCompletionAsync(string id, CancellationToken cancellationToken)
    {
        if (!_jobs.TryGetValue(id, out var job)) return null;
        if (job.State is "queued" or "generating")
            await job.Completion.Task.WaitAsync(cancellationToken);
        return job.Status;
    }

    public async Task<TtsJobStatus?> RetryAsync(string id, CancellationToken cancellationToken)
    {
        if (!_jobs.TryGetValue(id, out var job) || job.State != "failed" || !File.Exists(RequestPath(id)))
            return null;

        job.Error = null;
        job.State = "queued";
        job.ExpiresAtUtc = null;
        job.Completion = NewCompletion();
        await PersistStatusAsync(job, cancellationToken);
        await _pending.Writer.WriteAsync(id, cancellationToken);
        return job.Status;
    }

    public async Task MarkDownloadedAsync(string id, CancellationToken cancellationToken)
    {
        if (!_jobs.TryGetValue(id, out var job) || job.State != "completed") return;

        job.DownloadedAtUtc = DateTime.UtcNow;
        job.ExpiresAtUtc = job.DownloadedAtUtc.Value.AddHours(1);
        await PersistStatusAsync(job, cancellationToken);
    }

    public string AudioPath(string id) => Path.Combine(_directory, $"{id}.mp3");

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var cleanup = CleanupExpiredJobsAsync(stoppingToken);
        try
        {
            await foreach (var id in _pending.Reader.ReadAllAsync(stoppingToken))
            {
                if (!_jobs.TryGetValue(id, out var job)) continue;
                try
                {
                    job.State = "generating";
                    job.Error = null;
                    await PersistStatusAsync(job, stoppingToken);
                    var request = await ReadJsonAsync<TtsGenerationRequest>(RequestPath(id), stoppingToken)
                        ?? throw new FileNotFoundException("The queued TTS request is missing.");
                    var temporaryAudio = AudioPath(id) + ".tmp";
                    await synthesis.SynthesizeMp3ToFileAsync(request, temporaryAudio, stoppingToken);
                    File.Move(temporaryAudio, AudioPath(id), overwrite: true);
                    job.State = "completed";
                    job.CompletedAtUtc = DateTime.UtcNow;
                    job.ExpiresAtUtc = job.CompletedAtUtc.Value.AddHours(1);
                    await PersistStatusAsync(job, stoppingToken);
                    File.Delete(RequestPath(id));
                    job.Completion.TrySetResult();
                }
                catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
                {
                    job.State = "queued";
                    await PersistStatusAsync(job, CancellationToken.None);
                    job.Completion.TrySetCanceled(stoppingToken);
                    throw;
                }
                catch (Exception error)
                {
                    job.State = "failed";
                    job.Error = error.Message;
                    job.ExpiresAtUtc = DateTime.UtcNow.AddHours(1);
                    await PersistStatusAsync(job, CancellationToken.None);
                    job.Completion.TrySetResult();
                    logger.LogError(error, "KokoroSharp job {JobId} failed", id);
                }
            }
        }
        finally
        {
            try { await cleanup; }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
        }
    }

    private async Task RecoverJobsAsync(CancellationToken cancellationToken)
    {
        foreach (var statusFile in Directory.EnumerateFiles(_directory, "*.status.json"))
        {
            cancellationToken.ThrowIfCancellationRequested();
            var id = Path.GetFileName(statusFile)[..^".status.json".Length];
            if (!Guid.TryParseExact(id, "N", out _)) continue;
            var saved = await ReadJsonAsync<TtsJobStatus>(statusFile, cancellationToken);
            if (saved is null) continue;

            var request = await ReadJsonAsync<TtsGenerationRequest>(RequestPath(id), cancellationToken);
            var state = saved.State;
            if (state is "queued" or "generating")
            {
                if (request is null)
                {
                    state = "failed";
                    saved = saved with { Error = "The queued TTS request could not be recovered." };
                }
                else
                {
                    state = "queued";
                    saved = saved with { State = state, Error = null };
                }
            }
            if (state == "completed" && !File.Exists(AudioPath(id)))
            {
                state = request is null ? "failed" : "queued";
                saved = saved with { State = state, Error = "The generated audio file is missing." };
            }

            var expiresAtUtc = saved.ExpiresAtUtc;
            if (state is "completed" or "failed" && expiresAtUtc is null)
                expiresAtUtc = DateTime.UtcNow.AddHours(1);
            var job = new Job(
                id,
                request,
                state,
                saved.Error,
                saved.CreatedAtUtc,
                saved.CompletedAtUtc,
                saved.DownloadedAtUtc,
                expiresAtUtc);
            if (state is "completed" or "failed") job.ExpiresAtUtc = expiresAtUtc;
            _jobs[id] = job;
            await PersistStatusAsync(job, cancellationToken);
            if (state is "queued" or "generating")
                await _pending.Writer.WriteAsync(id, cancellationToken);
            else
                job.Completion.TrySetResult();
        }
    }

    private async Task CleanupExpiredJobsAsync(CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(5));
        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            var now = DateTime.UtcNow;
            foreach (var job in _jobs.Values.Where(job =>
                         job.State is "completed" or "failed" &&
                         job.ExpiresAtUtc is not null &&
                         job.ExpiresAtUtc <= now))
            {
                _jobs.TryRemove(job.Id, out _);
                DeleteIfExists(StatusPath(job.Id));
                DeleteIfExists(RequestPath(job.Id));
                DeleteIfExists(AudioPath(job.Id));
                DeleteIfExists(AudioPath(job.Id) + ".tmp");
            }
        }
    }

    private async Task PersistStatusAsync(Job job, CancellationToken cancellationToken) =>
        await WriteJsonAsync(StatusPath(job.Id), job.Status, cancellationToken);

    private static async Task WriteJsonAsync<T>(string path, T value, CancellationToken cancellationToken)
    {
        var temporary = path + ".tmp";
        await using (var file = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
            await JsonSerializer.SerializeAsync(file, value, JsonOptions, cancellationToken);
        File.Move(temporary, path, overwrite: true);
    }

    private static async Task<T?> ReadJsonAsync<T>(string path, CancellationToken cancellationToken)
    {
        if (!File.Exists(path)) return default;
        await using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        return await JsonSerializer.DeserializeAsync<T>(file, JsonOptions, cancellationToken);
    }

    private string RequestPath(string id) => Path.Combine(_directory, $"{id}.request.json");
    private string StatusPath(string id) => Path.Combine(_directory, $"{id}.status.json");

    private static void DeleteIfExists(string path)
    {
        if (File.Exists(path)) File.Delete(path);
    }

    private static TaskCompletionSource NewCompletion() =>
        new(TaskCreationOptions.RunContinuationsAsynchronously);

    private sealed class Job(
        string id,
        TtsGenerationRequest? request,
        string state,
        string? error,
        DateTime createdAtUtc,
        DateTime? completedAtUtc = null,
        DateTime? downloadedAtUtc = null,
        DateTime? expiresAtUtc = null)
    {
        public string Id { get; } = id;
        public TtsGenerationRequest? Request { get; } = request;
        public string State { get; set; } = state;
        public string? Error { get; set; } = error;
        public DateTime CreatedAtUtc { get; } = createdAtUtc;
        public DateTime? CompletedAtUtc { get; set; } = completedAtUtc;
        public DateTime? DownloadedAtUtc { get; set; } = downloadedAtUtc;
        public DateTime? ExpiresAtUtc { get; set; } = expiresAtUtc;
        public TaskCompletionSource Completion { get; set; } = NewCompletion();

        public TtsJobStatus Status => new(
            Id,
            State,
            Error,
            CreatedAtUtc,
            CompletedAtUtc,
            DownloadedAtUtc,
            ExpiresAtUtc);
    }
}

using System.Diagnostics;
using System.ComponentModel;
using System.Threading.Channels;
using KokoroSharp;
using KokoroSharp.Processing;
using downloader.Services;
using Microsoft.AspNetCore.Mvc;

namespace downloader.Api;

[ApiController]
[Route("api/tts")]
public sealed class TtsController(
    IConfiguration configuration,
    ILogger<TtsController> logger,
    KokoroSynthesisService synthesisService,
    TtsJobQueue jobs) : ControllerBase
{
    private static readonly Dictionary<string, string[]> Voices = new(StringComparer.OrdinalIgnoreCase)
    {
        ["en"] = ["af_heart", "af_bella", "af_sarah", "af_nicole", "am_michael", "am_adam", "bm_george", "bf_emma"],
        ["fr"] = ["ff_siwis"]
    };

    [HttpGet("voices")]
    public IActionResult GetVoices([FromQuery] string language)
    {
        if (!Voices.TryGetValue(language, out var voices))
            return BadRequest(new { error = "Choose English or French." });

        return Ok(voices.Select(voice => new
        {
            id = voice,
            label = voice switch
            {
                "af_heart" => "American · Heart",
                "af_bella" => "American · Bella",
                "af_sarah" => "American · Sarah",
                "af_nicole" => "American · Nicole",
                "am_michael" => "American · Michael",
                "am_adam" => "American · Adam",
                "bm_george" => "British · George",
                "bf_emma" => "British · Emma",
                "ff_siwis" => "French · Siwis",
                _ => voice
            }
        }));
    }

    [HttpPost("jobs")]
    public async Task<IActionResult> CreateJob(
        [FromBody] TtsGenerationRequest request,
        CancellationToken cancellationToken)
    {
        var validationError = Validate(request);
        if (validationError is not null) return BadRequest(new { error = validationError });
        var job = await jobs.EnqueueAsync(request, cancellationToken);
        return AcceptedAtAction(nameof(GetJob), new { id = job.Id }, job);
    }

    [HttpGet("jobs/{id}")]
    public IActionResult GetJob(string id)
    {
        if (!Guid.TryParseExact(id, "N", out _)) return NotFound();
        var job = jobs.GetStatus(id);
        return job is null ? NotFound() : Ok(job);
    }

    [HttpPost("jobs/{id}/retry")]
    public async Task<IActionResult> RetryJob(string id, CancellationToken cancellationToken)
    {
        if (!Guid.TryParseExact(id, "N", out _)) return NotFound();
        var job = await jobs.RetryAsync(id, cancellationToken);
        return job is null ? Conflict(new { error = "This recording cannot be retried." }) : Accepted(job);
    }

    [HttpGet("jobs/{id}/file")]
    public async Task<IActionResult> GetJobFile(string id, CancellationToken cancellationToken)
    {
        if (!Guid.TryParseExact(id, "N", out _)) return NotFound();
        var job = await jobs.WaitForCompletionAsync(id, cancellationToken);
        if (job is null) return NotFound();
        if (job.State != "completed")
            return StatusCode(StatusCodes.Status502BadGateway,
                new { error = job.Error ?? "The recording could not be generated." });

        var audioPath = jobs.AudioPath(id);
        Response.StatusCode = StatusCodes.Status200OK;
        Response.ContentType = "audio/mpeg";
        Response.ContentLength = new FileInfo(audioPath).Length;
        Response.Headers.ContentDisposition = "attachment; filename=retrosica-voice.mp3";
        Response.Headers.CacheControl = "no-store";
        await using (var audio = new FileStream(audioPath, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            await audio.CopyToAsync(Response.Body, cancellationToken);
            await Response.Body.FlushAsync(cancellationToken);
        }
        await jobs.MarkDownloadedAsync(id, cancellationToken);
        return new EmptyResult();
    }

    [HttpPost("stream")]
    public async Task<IActionResult> Stream([FromBody] TtsGenerationRequest request, CancellationToken cancellationToken)
    {
        var validationError = Validate(request);
        if (validationError is not null) return BadRequest(new { error = validationError });

        await synthesisService.Gate.WaitAsync(cancellationToken);
        try
        {
            var synthesizer = await synthesisService.GetSynthesizerAsync(cancellationToken);
            var voice = KokoroVoiceManager.GetVoice(request.Voice);
            var chunks = Channel.CreateUnbounded<float[]>(new UnboundedChannelOptions { SingleReader = true, SingleWriter = false });
            var pipeline = new KokoroTTSPipelineConfig { Speed = (float)request.Speed };

            using var encoder = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = configuration["FfmpegPath"] ?? "ffmpeg",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardInput = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                }
            };
            foreach (var argument in new[]
            {
                "-hide_banner", "-loglevel", "error", "-f", "s16le", "-ar", "24000", "-ac", "1",
                "-i", "pipe:0", "-codec:a", "libmp3lame", "-b:a", "128k", "-f", "mp3", "pipe:1"
            }) encoder.StartInfo.ArgumentList.Add(argument);

            try
            {
                if (!encoder.Start())
                    return StatusCode(StatusCodes.Status503ServiceUnavailable, new { error = "The MP3 encoder could not start." });
            }
            catch (Exception error) when (error is Win32Exception or InvalidOperationException)
            {
                logger.LogError(error, "Could not start FFmpeg for Kokoro audio encoding");
                return StatusCode(StatusCodes.Status503ServiceUnavailable, new { error = "FFmpeg is not installed on this server." });
            }

            var encoderError = encoder.StandardError.ReadToEndAsync(cancellationToken);
            try
            {
                synthesizer.Synthesize(
                    request.Text,
                    voice,
                    samples => chunks.Writer.TryWrite(samples),
                    () => chunks.Writer.TryComplete(),
                    pipeline);
            }
            catch (Exception error)
            {
                chunks.Writer.TryComplete(error);
                encoder.Kill(entireProcessTree: true);
                logger.LogError(error, "KokoroSharp failed to start synthesis");
                return StatusCode(StatusCodes.Status502BadGateway, new { error = "Kokoro could not synthesize this text." });
            }

            Response.StatusCode = StatusCodes.Status200OK;
            Response.ContentType = "audio/mpeg";
            Response.Headers.ContentDisposition = "inline; filename=retrosica-voice.mp3";
            Response.Headers.CacheControl = "no-store";

            var encodeTask = EncodeChunksAsync(chunks.Reader, encoder.StandardInput.BaseStream, cancellationToken);
            var copyTask = encoder.StandardOutput.BaseStream.CopyToAsync(Response.Body, 16 * 1024, cancellationToken);
            await Task.WhenAll(encodeTask, copyTask);
            await encoder.WaitForExitAsync(cancellationToken);
            var details = await encoderError;
            if (encoder.ExitCode != 0)
                logger.LogError("FFmpeg exited with code {ExitCode}: {Error}", encoder.ExitCode, details);
            return new EmptyResult();
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            return new EmptyResult();
        }
        catch (Exception error)
        {
            logger.LogError(error, "KokoroSharp streaming synthesis failed");
            if (!Response.HasStarted)
                return StatusCode(StatusCodes.Status502BadGateway, new { error = "Kokoro could not generate the recording." });
            throw;
        }
        finally { synthesisService.Gate.Release(); }
    }

    private static async Task EncodeChunksAsync(ChannelReader<float[]> chunks, Stream ffmpegInput, CancellationToken cancellationToken)
    {
        var bytes = new byte[32 * 1024];
        try
        {
            await foreach (var samples in chunks.ReadAllAsync(cancellationToken))
            {
                var offset = 0;
                while (offset < samples.Length)
                {
                    var count = Math.Min(samples.Length - offset, bytes.Length / 2);
                    for (var i = 0; i < count; i++)
                    {
                        var sample = (short)Math.Clamp((int)(samples[offset + i] * short.MaxValue), short.MinValue, short.MaxValue);
                        bytes[i * 2] = (byte)sample;
                        bytes[i * 2 + 1] = (byte)(sample >> 8);
                    }
                    await ffmpegInput.WriteAsync(bytes.AsMemory(0, count * 2), cancellationToken);
                    offset += count;
                }
            }
        }
        finally { await ffmpegInput.DisposeAsync(); }
    }

    private static string? Validate(TtsGenerationRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Text)) return "Enter text to record.";
        if (request.Text.Length > 500000) return "Text must be 500,000 characters or fewer.";
        if (!Voices.TryGetValue(request.Language, out var voices) || !voices.Contains(request.Voice))
            return "Choose a voice available for the selected language.";
        if (request.Speed is < 0.8 or > 1.2) return "Speech speed must be between 0.8 and 1.2.";
        return null;
    }
}

public sealed record TtsGenerationRequest(string Text, string Language, string Voice, double Speed = 1.0);

public sealed class KokoroSynthesisService(IConfiguration configuration, ILogger<KokoroSynthesisService> logger)
{
    private readonly SemaphoreSlim _loadGate = new(1, 1);
    private KokoroWavSynthesizer? _synthesizer;
    public SemaphoreSlim Gate { get; } = new(1, 1);

    public async Task<KokoroWavSynthesizer> GetSynthesizerAsync(CancellationToken cancellationToken)
    {
        if (_synthesizer is not null) return _synthesizer;
        await _loadGate.WaitAsync(cancellationToken);
        try
        {
            if (_synthesizer is not null) return _synthesizer;

            var dataDirectory = configuration["DataDirectory"] ?? Path.Combine(AppContext.BaseDirectory, "data");
            var modelDirectory = Path.Combine(dataDirectory, "kokoro");
            Directory.CreateDirectory(modelDirectory);
            var modelPath = Path.Combine(modelDirectory, "kokoro.onnx");
            if (!File.Exists(modelPath))
            {
                var temporaryPath = modelPath + ".tmp";
                logger.LogInformation("Downloading the KokoroSharp model to {ModelPath}", modelPath);
                using var client = new HttpClient { Timeout = TimeSpan.FromHours(1) };
                using var response = await client.GetAsync(
                    "https://github.com/Lyrcaxis/KokoroSharpBinaries/releases/download/v2.0.0/kokoro.onnx",
                    HttpCompletionOption.ResponseHeadersRead,
                    cancellationToken);
                response.EnsureSuccessStatusCode();
                await using (var source = await response.Content.ReadAsStreamAsync(cancellationToken))
                await using (var destination = new FileStream(temporaryPath, FileMode.Create, FileAccess.Write, FileShare.None))
                    await source.CopyToAsync(destination, cancellationToken);
                File.Move(temporaryPath, modelPath, overwrite: true);
            }

            var synthesizer = await Task.Run(() => KokoroWavSynthesizer.LoadModel(modelPath), cancellationToken);
            KokoroVoiceManager.LoadVoicesFromPath(Path.Combine(AppContext.BaseDirectory, "voices"));
            _synthesizer = synthesizer;
            return synthesizer;
        }
        finally { _loadGate.Release(); }
    }

    public async Task SynthesizeMp3ToFileAsync(
        TtsGenerationRequest request,
        string outputPath,
        CancellationToken cancellationToken)
    {
        await Gate.WaitAsync(cancellationToken);
        try
        {
            var synthesizer = await GetSynthesizerAsync(cancellationToken);
            var voice = KokoroVoiceManager.GetVoice(request.Voice);
            using var encoder = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = configuration["FfmpegPath"] ?? "ffmpeg",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardInput = true,
                    RedirectStandardError = true
                }
            };
            foreach (var argument in new[]
            {
                "-y", "-hide_banner", "-loglevel", "error", "-f", "s16le", "-ar", "24000", "-ac", "1",
                "-i", "pipe:0", "-codec:a", "libmp3lame", "-b:a", "128k", "-f", "mp3", outputPath
            }) encoder.StartInfo.ArgumentList.Add(argument);

            if (!encoder.Start()) throw new InvalidOperationException("FFmpeg could not start.");
            using var cancellationRegistration = cancellationToken.Register(() =>
            {
                try { if (!encoder.HasExited) encoder.Kill(entireProcessTree: true); }
                catch (InvalidOperationException) { }
            });
            var encoderError = encoder.StandardError.ReadToEndAsync();
            var chunks = Channel.CreateUnbounded<float[]>(new UnboundedChannelOptions
            {
                SingleReader = true,
                SingleWriter = false
            });
            try
            {
                synthesizer.Synthesize(
                    request.Text,
                    voice,
                    samples => chunks.Writer.TryWrite(samples),
                    () => chunks.Writer.TryComplete(),
                    new KokoroTTSPipelineConfig { Speed = (float)request.Speed });
            }
            catch (Exception error)
            {
                chunks.Writer.TryComplete(error);
                encoder.Kill(entireProcessTree: true);
                throw new InvalidOperationException("KokoroSharp could not start synthesis.", error);
            }

            await EncodeChunksAsync(chunks.Reader, encoder.StandardInput.BaseStream, cancellationToken);
            await encoder.WaitForExitAsync(cancellationToken);
            var details = await encoderError;
            if (encoder.ExitCode != 0)
                throw new InvalidOperationException($"FFmpeg exited with code {encoder.ExitCode}: {details}");
        }
        finally { Gate.Release(); }
    }

    private static async Task EncodeChunksAsync(
        ChannelReader<float[]> chunks,
        Stream ffmpegInput,
        CancellationToken cancellationToken)
    {
        var bytes = new byte[32 * 1024];
        try
        {
            await foreach (var samples in chunks.ReadAllAsync(cancellationToken))
            {
                var offset = 0;
                while (offset < samples.Length)
                {
                    var count = Math.Min(samples.Length - offset, bytes.Length / 2);
                    for (var i = 0; i < count; i++)
                    {
                        var sample = (short)Math.Clamp((int)(samples[offset + i] * short.MaxValue), short.MinValue, short.MaxValue);
                        bytes[i * 2] = (byte)sample;
                        bytes[i * 2 + 1] = (byte)(sample >> 8);
                    }
                    await ffmpegInput.WriteAsync(bytes.AsMemory(0, count * 2), cancellationToken);
                    offset += count;
                }
            }
        }
        finally { await ffmpegInput.DisposeAsync(); }
    }
}

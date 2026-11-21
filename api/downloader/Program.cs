using downloader.Controllers;
using downloader.Services;
using downloader.Api;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);
var connectionString = builder.Configuration.GetConnectionString("Postgres")
    ?? throw new InvalidOperationException("ConnectionStrings:Postgres is required.");

builder.Services.AddDbContextFactory<AppDbContext>(options => options.UseNpgsql(connectionString));
builder.Services.AddCors(options => options.AddPolicy("open", policy =>
    policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));
builder.Services.AddControllers();
builder.Services.AddOpenApi();
builder.Services.AddSingleton<DownloadCoordinator>();
builder.Services.AddSingleton<KokoroSynthesisService>();
builder.Services.AddSingleton<TtsJobQueue>();
builder.Services.AddHostedService(provider => provider.GetRequiredService<DownloadCoordinator>());
builder.Services.AddHostedService(provider => provider.GetRequiredService<TtsJobQueue>());
builder.Services.AddHostedService<ExpiryCleanupService>();

var app = builder.Build();
var dbFactory = app.Services.GetRequiredService<IDbContextFactory<AppDbContext>>();
var connected = false;
for (var attempt = 1; attempt <= 30 && !connected; attempt++)
{
    try
    {
        await using var db = await dbFactory.CreateDbContextAsync();
        await db.Database.EnsureCreatedAsync();
        connected = true;
    }
    catch (Exception error) when (attempt < 30)
    {
        app.Logger.LogWarning(error, "PostgreSQL is not ready yet (attempt {Attempt}/30)", attempt);
        await Task.Delay(TimeSpan.FromSeconds(2));
    }
}

app.UseCors("open");
if (app.Environment.IsDevelopment()) app.MapOpenApi();
app.MapGet("/healthz", () => Results.Ok(new { status = "ok" }));
app.MapControllers();
app.Run();

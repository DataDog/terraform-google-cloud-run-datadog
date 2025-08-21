// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache 2.0 License.

// This product includes software developped at
// Datadog (https://www.datadoghq.com/)
// Copyright 2025-present Datadog, Inc.

using Serilog;

var rawLogPath = Environment.GetEnvironmentVariable("DD_SERVERLESS_LOG_PATH");
var logFile = string.IsNullOrEmpty(rawLogPath) ? "/shared-volume/logs/app.log" : rawLogPath.Replace("*.log", "app.log");
Console.WriteLine($"logFile: {logFile}");

var builder = WebApplication.CreateBuilder(args);

// Configure Serilog for structured logging with Datadog correlation
builder.Host.UseSerilog((context, config) =>
{
    // Ensure the directory exists
    Directory.CreateDirectory(Path.GetDirectoryName(logFile)!);

    config.WriteTo.Console(new Serilog.Formatting.Json.JsonFormatter(renderMessage: true))
          .WriteTo.File(new Serilog.Formatting.Json.JsonFormatter(renderMessage: true), logFile);
});

var app = builder.Build();

app.MapGet("/", (ILogger<Program> logger) =>
{
    logger.LogInformation("Hello Datadog logger using Dotnet!");
    return Results.Ok("Hello Dotnet World!");
});
var port = Environment.GetEnvironmentVariable("PORT") ?? "8080";
app.Urls.Add($"http://*:{port}");

app.Run();
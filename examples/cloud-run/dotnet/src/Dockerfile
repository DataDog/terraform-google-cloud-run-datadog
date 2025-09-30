# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache 2.0 License.

# This product includes software developped at
# Datadog (https://www.datadoghq.com/)
# Copyright 2025-present Datadog, Inc.

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /app

COPY *.csproj ./
RUN dotnet restore dotnet.csproj

COPY . .
RUN dotnet publish dotnet.csproj -c Release -o out --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app

# Copy the built application
COPY --from=build /app/out .

ENV PORT=8080
EXPOSE 8080

# Datadog automatic instrumentation environment variables
ENV CORECLR_ENABLE_PROFILING=1 \
  CORECLR_PROFILER={846F5F1C-F9AE-4B07-969E-05C26BC060D8} \
  CORECLR_PROFILER_PATH=/app/datadog/linux-x64/Datadog.Trace.ClrProfiler.Native.so \
  DD_DOTNET_TRACER_HOME=/app/datadog

CMD ["dotnet", "dotnet.dll"]

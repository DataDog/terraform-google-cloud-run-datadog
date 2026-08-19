# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

require "fileutils"

# Mirror the Rails log into the shared volume the sidecar tails. Trace and span
# IDs are added to these lines by the injected tracer, not by this app.
LOG_FILE = (ENV["DD_SERVERLESS_LOG_PATH"] || "/shared-volume/logs/*.log").sub("*.log", "app.log")
FileUtils.mkdir_p(File.dirname(LOG_FILE))

Rails.logger.broadcast_to(ActiveSupport::TaggedLogging.logger(LOG_FILE))

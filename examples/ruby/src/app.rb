# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache 2.0 License.

# This product includes software developped at
# Datadog (https://www.datadoghq.com/)
# Copyright 2025-present Datadog, Inc.

require 'sinatra'
require 'logger'
require 'datadog/auto_instrument'
require 'fileutils'

LOG_FILE = (ENV['DD_SERVERLESS_LOG_PATH']&.gsub('*.log', 'app.log')) || '/shared-volume/logs/app.log'
puts "LOG_FILE: #{LOG_FILE}"

Datadog.configure do |c|
  # Add additional configuration here.
  # Activate integrations, change tracer settings, etc...
end

set :environment, :production
set :port, 8080
set :bind, '0.0.0.0'

# Create log directory if it doesn't exist
FileUtils.mkdir_p(File.dirname(LOG_FILE))

# Create logger that writes to file in shared volume
logger = Logger.new(LOG_FILE)
logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime}] #{severity}: [#{Datadog::Tracing.log_correlation}] #{msg}\n"
end

get '/' do
  logger.info "Hello Datadog logger using Ruby!"
  'Hello Ruby World!'
end
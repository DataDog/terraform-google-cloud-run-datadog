# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

# Only a default: when the tracer is injected it points BUNDLE_GEMFILE at its own
# gemfile, which layers the tracer on top of this app's Gemfile. Overwriting it
# here would drop the tracer back out of the bundle.
ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require 'bundler/setup'

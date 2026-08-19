# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

require_relative 'boot'

require 'rails'
require 'action_controller/railtie'

# Loads the bundle, which is how the injected tracer gets in: it is added to the
# bundle rather than required by the app, and its railtie takes it from there.
Bundler.require(*Rails.groups)

module CloudRunExample
  class Application < Rails::Application
    config.load_defaults 8.1
    config.eager_load = true
    # The example serves no cookies or sessions, so this only has to be present.
    config.secret_key_base = ENV.fetch('SECRET_KEY_BASE', 'cloud-run-datadog-example')
    config.logger = ActiveSupport::TaggedLogging.logger($stdout)
  end
end

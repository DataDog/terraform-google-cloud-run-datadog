# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

class HelloController < ActionController::Base
  def index
    Rails.logger.info 'Hello Datadog logger using Ruby!'
    render plain: 'Hello Ruby World!'
  end
end

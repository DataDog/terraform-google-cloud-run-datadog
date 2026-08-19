# Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
# This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "hello#index"
end

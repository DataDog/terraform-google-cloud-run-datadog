// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

package com.datadoghq.example;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@SpringBootApplication
@RestController
public class Application {

  private static final Logger LOGGER = LoggerFactory.getLogger(Application.class);

  private static final String DEFAULT_LOG_PATH = "/shared-volume/logs/*.log";

  public static void main(String[] args) {
    String logPath = System.getenv().getOrDefault("DD_SERVERLESS_LOG_PATH", DEFAULT_LOG_PATH);
    System.setProperty("APP_LOG_FILE", logPath.replace("*.log", "app.log"));

    SpringApplication.run(Application.class, args);
  }

  @GetMapping("/")
  public String hello() {
    LOGGER.info("Hello Datadog logger using Java!");

    return "Hello Java World!";
  }
}

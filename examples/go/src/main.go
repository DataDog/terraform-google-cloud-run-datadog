// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

// Unless explicitly stated otherwise all files in this repository are licensed
// under the Apache 2.0 License.

// This product includes software developped at
// Datadog (https://www.datadoghq.com/)
// Copyright 2025-present Datadog, Inc.

package main

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	httptrace "github.com/DataDog/dd-trace-go/contrib/net/http/v2"
	dd_logrus "github.com/DataDog/dd-trace-go/contrib/sirupsen/logrus/v2"
	"github.com/DataDog/dd-trace-go/v2/ddtrace/tracer"
	"github.com/sirupsen/logrus"
)

const PORT = "8080"

var LOG_FILE = func() string {
	log_file := os.Getenv("DD_SERVERLESS_LOG_PATH")
	if log_file != "" {
		log_file = strings.Replace(log_file, "*.log", "app.log", 1)
	} else {
		log_file = "/shared-volume/logs/app.log"
	}

	fmt.Printf("LOG_FILE: %s\n", log_file)
	return log_file
}()

func main() {
	tracer.Start()
	defer tracer.Stop()

	os.MkdirAll(filepath.Dir(LOG_FILE), 0755)
	logFile, err := os.OpenFile(LOG_FILE, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
	if err != nil {
		logrus.Fatalf("Failed to open log file: %v", err)
	}
	defer logFile.Close()

	// Configure logrus to write to file
	logrus.SetOutput(logFile)
	logrus.SetFormatter(&logrus.JSONFormatter{})
	logrus.AddHook(&dd_logrus.DDContextLogHook{})

	mux := httptrace.NewServeMux()

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		// Use the request context for trace-log correlation
		ctx := r.Context()
		logrus.WithContext(ctx).Info("Hello Datadog logger using Go!")

		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, "Hello Go World!")
	})

	logrus.Infof("Starting server on port %s", PORT)

	if err := http.ListenAndServe(":"+PORT, mux); err != nil {
		logrus.Fatalf("Server failed to start: %v", err)
	}
}
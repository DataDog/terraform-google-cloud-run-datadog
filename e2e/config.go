// Unless explicitly stated otherwise all files in this repository are licensed under the Apache-2.0 License.
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2026 Datadog, Inc.

package e2e

import (
	e2eshared "github.com/DataDog/terraform-google-cloud-run-datadog/e2e/shared"
)

// sharedCfg supplies the tool and platform names used for run-scoped resource names.
var sharedCfg = e2eshared.Config{
	Tool:     "tf",
	Platform: "cloud-run",
}

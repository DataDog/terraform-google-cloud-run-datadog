`tf-autogen` regenerates this Google Cloud Run module from `autogen_config.json`.
Install it once: `pipx install -e ~/dd/serverless-ci/terraform-autogen/`.
Never edit generated `versions.tf`, `autogen_config_schema.json`, `resource_impl.tf`, `resource_variables.tf`, or `outputs.tf`.
Instead, customize `main.tf`, `variables.tf`, and `autogen_config.json`.
Each `fields.impl` path makes generated code use a matching `local`. Nested fields read from an implemented parent local; exact nested overrides use underscore-separated flat local names.
After changing `autogen_config.json` or referenced `main.tf` locals, run `tf-autogen` and inspect the diff.
Fix unexpected generated output in the handwritten inputs, never in generated files.

# Agent notes: terraform-autogen

This module is scaffolded and kept up to date by `terraform-autogen` (`tf-autogen`),
a scheduled bot that regenerates files from `autogen_config.json` and opens a PR
with the diff.

## Generated files

These files are fully overwritten by `tf-autogen` on every run (see their
`DO NOT EDIT` headers):

- `versions.tf`
- `resource_impl.tf`
- `resource_variables.tf`
- `outputs.tf`
- `README.md` (via `terraform-docs`)

Hand-written files -- `main.tf`, `variables.tf`, `autogen_config.json` -- are
not touched by the tool and are where customization belongs.

## How `impl` fields work

`autogen_config.json`'s `fields.impl` list marks fields that are manually
implemented rather than passed straight through from the matching `var.*`. For
a top-level field, the generator points the field (or, for blocks, the
`for_each`) at a `local` of the same name, and expects that local to exist in
`main.tf`.

For *nested* fields inside a block, this only works if the exact dotted path
is also listed in `impl`, e.g. `"template.containers.some_field"`. The
generator then emits `local.template_containers_some_field` (dots become
underscores), so `main.tf` must define a local with that exact flat name. A
nested path missing from `impl` gets `var.<path>` instead, even when the
parent block is marked `impl` -- silently discarding any custom local.

## Required check for any change touching generated files' inputs

Before committing changes to `autogen_config.json` or any `main.tf` local a
generated file references, run `tf-autogen` and confirm it produces **no
diff** beyond what you intended (an unrelated provider version bump in
`versions.tf` is expected and fine).

Install the tool once with:

```sh
pipx install -e ~/dd/serverless-ci/terraform-autogen/
```

Then:

```sh
tf-autogen
git diff
```

If the diff reverts something in a generated file, fix `autogen_config.json` /
`main.tf` -- not the generated file itself.

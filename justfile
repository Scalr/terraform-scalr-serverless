roots := "aws azure"

# List recipes.
default:
    @just --list

# Install dependencies and the git hook.
setup:
    uv sync
    uv run prek install

# Run every pre-commit hook on all files.
lint:
    uv run prek run --all-files

# Format Terraform files.
fmt:
    tofu fmt -recursive

# Validate each root module without a backend.
validate:
    #!/usr/bin/env bash
    set -euo pipefail
    for root in {{ roots }}; do
        echo "== $root"
        tofu -chdir="$root" init -backend=false -input=false >/dev/null
        tofu -chdir="$root" validate
    done

# Run the Python tests and the Terraform tests of each root module.
test:
    #!/usr/bin/env bash
    set -euo pipefail
    uv run pytest
    for root in {{ roots }}; do
        echo "== $root"
        tofu -chdir="$root" init -backend=false -input=false >/dev/null
        tofu -chdir="$root" test
    done

# Check local links and anchors in Markdown files.
lychee *paths:
    lychee --offline {{ if paths == "" { "." } else { paths } }}

# Check local and external links in Markdown files.
lychee-online *paths:
    lychee {{ if paths == "" { "." } else { paths } }}

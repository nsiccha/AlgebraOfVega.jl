#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# The landing gate uses a fresh checkout, without a docs Manifest.
KB_ENV_SETUP_STRICT=1 kb-env-setup "$PWD" docs "$HOME/github/nsiccha/Claude"
export JULIA_LOAD_PATH=@:@stdlib
exec julia --startup-file=no --project=docs docs/lint.jl

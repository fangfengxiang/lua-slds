#!/bin/sh
set -eu

# Run from the repository root. Overrides allow an isolated interpreter/toolchain.
cd "$(dirname "$0")/.."
rm -f luacov.stats.out luacov.report.out
"${SLDS_BUSTED:-busted}" --coverage --pattern=spec
"${SLDS_LUA:-lua}" -e 'require("luacov.reporter").report()'
"${SLDS_LUA:-lua}" scripts/check-coverage.lua

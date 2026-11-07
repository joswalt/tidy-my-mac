#!/bin/bash
# Rule lint (spec 006 §6 step 1): loads every Rules/*.json file with the app's own loader
# (unknown fields are errors) and runs RuleEngine's linter. Runs in CI and locally.
set -euo pipefail
cd "$(dirname "$0")/.."
swift run -q --package-path Packages/TidyCore tidy-rule-lint Rules

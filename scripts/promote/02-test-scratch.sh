#!/usr/bin/env bash
# Step 2. Run every test in the scratch org with coverage. Do not promote unless this passes.
set -euo pipefail
ORG="${1:?usage: $0 <scratch-org-alias>}"
mkdir -p tmp
sf apex run test -o "$ORG" --test-level RunLocalTests --code-coverage --result-format human --wait 30 --output-dir tmp/test-results
echo "Coverage report: tmp/test-results (look for org-wide coverage and any class under 75%)"

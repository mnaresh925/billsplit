#!/usr/bin/env bash
# Step 4. Quick deploy a validation that passed in the last 10 days. Skips re-running tests.
set -euo pipefail
ORG="${1:?usage: $0 <prod-alias> <validated-job-id>}"
JOB="${2:?missing validated job id}"
read -r -p "Deploy validated job $JOB to $ORG now? Type yes: " A
[ "$A" = "yes" ] || { echo "Cancelled"; exit 1; }
sf project deploy quick -o "$ORG" --job-id "$JOB" --wait 30

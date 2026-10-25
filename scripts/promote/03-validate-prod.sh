#!/usr/bin/env bash
# Step 3. Check-only deploy to production. Nothing changes in prod. Prints a job id for the quick deploy.
# Usage: scripts/promote/03-validate-prod.sh <prod-alias> [all|specified]
#   all        RunLocalTests: every non-managed test in the org (default, strictest)
#   specified  RunSpecifiedTests: only this project's tests (use if unrelated Apex in prod fails)
set -euo pipefail
ORG="${1:?usage: $0 <prod-alias> [all|specified]}"
MODE="${2:-all}"
cd "$(dirname "$0")/../.."
if [ "$MODE" = "specified" ]; then
  TESTS=$(paste -sd' ' scripts/promote/test-classes.txt)
  ARGS=(--test-level RunSpecifiedTests)
  for t in $TESTS; do ARGS+=(--tests "$t"); done
else
  ARGS=(--test-level RunLocalTests)
fi
sf project deploy validate -o "$ORG" -x manifest/package.xml "${ARGS[@]}" --wait 60 --verbose | tee tmp-validate.log
echo
echo "If it passed, note the job id above and run:"
echo "  scripts/promote/04-quick-deploy.sh $ORG <jobId>"

#!/usr/bin/env bash
# Step 1. Pull whatever exists in the scratch org into the repo, so the repo matches what you actually tested.
# Usage: scripts/promote/01-sync-from-scratch.sh <scratch-alias>
set -euo pipefail
ORG="${1:?usage: $0 <scratch-org-alias>}"
cd "$(dirname "$0")/../.."

echo ">> Retrieving everything in manifest/package.xml from $ORG"
sf project retrieve start -o "$ORG" -x manifest/package.xml --ignore-conflicts

echo ">> Experience Cloud site metadata (not in the manifest because names differ per org)"
sf org list metadata -m Network -o "$ORG" || true
sf org list metadata -m ExperienceBundle -o "$ORG" || true
sf org list metadata -m CustomSite -o "$ORG" || true
cat <<'MSG'

If the lists above show your Owner Portal site, retrieve it too, using the exact names shown:
  sf project retrieve start -o <alias> -m "Network:Owner Portal" -m "CustomSite:Owner_Portal" -m "ExperienceBundle:Owner_Portal1"
Then check that the site profile membership still names 'Bill Split Owner Portal'.

Review what changed against the last commit. Lines that differ are fixes you made in the org:
  git status
  git diff
Commit them:
  git add -A && git commit -m "Sync scratch org changes before release"
MSG

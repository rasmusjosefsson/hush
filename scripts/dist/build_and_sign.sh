#!/usr/bin/env bash
set -euo pipefail

# Build, sign, and (optionally) create a DMG in one step.
#
# This is a convenience wrapper that runs build_app_bundle.sh followed by
# sign_notarize.sh.  All environment variables accepted by those scripts
# are passed through.
#
# Quick local build (ad-hoc signed DMG):
#   ./scripts/dist/build_and_sign.sh
#
# Distribution build (notarized):
#   SIGN_IDENTITY="Developer ID Application: ..." SKIP_NOTARIZE=0 \
#     ./scripts/dist/build_and_sign.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/build_app_bundle.sh"
"$SCRIPT_DIR/sign_notarize.sh"

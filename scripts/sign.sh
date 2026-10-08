#!/bin/sh
# Sign and notarize AntigravityHub.app for direct distribution.
#
# Produces ./dist/AntigravityHub.app — a build that Gatekeeper recognises as
# "identified developer" and lets users open without the untrusted-developer
# warning.
#
#   ./scripts/sign.sh                    full pipeline
#   ./scripts/sign.sh --sign-only        just re-sign with Developer ID, no notary
#   ./scripts/sign.sh --notary-only      upload the existing build, do not re-sign
#
# Prerequisites:
#   1. Run ./build.sh first — it produces build/AntigravityHub.app
#   2. Have a Developer ID Application certificate in your keychain
#      (Xcode > Settings > Accounts > Manage Certificates > +)
#   3. Have an App Store Connect API key for notarytool:
#      https://developer.apple.com/account/resources/authkeys/list
#      Download the .p8, then set the three KEY_* vars below or pass them
#      via environment
#
# What this does:
#   - Hardened runtime on
#   - Replace ad-hoc signature with Developer ID
#   - Staple a notarisation ticket (so Gatekeeper validates offline)
#
# This script intentionally stops on the first error. A failed notarisation
# submission is a paper trail you want to look at, not skip past.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUT="$ROOT/build/AntigravityHub.app"
OUTPUT="$ROOT/dist/AntigravityHub.app"

# ----- Configuration ----------------------------------------------------

MODE="${1:-all}"

if [ "$MODE" = "--ad-hoc" ]; then
    echo "==> Using ad-hoc signature mode"
    IDENTITY="-"
else
    # Keychain identity name, as it appears in `security find-identity`.
    # Default: the first Developer ID Application identity found.
    if [ -z "${IDENTITY:-}" ]; then
        IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null \
            | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
        if [ -z "$IDENTITY" ]; then
            echo "❌ No Developer ID Application identity found in keychain." >&2
            echo "   Open Xcode > Settings > Accounts > Manage Certificates > +, " >&2
            echo "   create a Developer ID Application certificate, then re-run." >&2
            echo "   (Or run ./scripts/sign.sh --ad-hoc for a local test package)." >&2
            exit 1
        fi
    fi

    # Notary credentials. Either an API key (preferred) or apple-id + password.
    if [ "$MODE" != "--sign-only" ]; then
        if [ -n "${KEY_ID:-}" ] && [ -n "${KEY_ISSUER:-}" ] && [ -n "${KEY_PATH:-}" ]; then
            NOTARY_AUTH=(--key "$KEY_PATH" --key-id "$KEY_ID" --issuer "$KEY_ISSUER")
        elif [ -n "${APPLE_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]; then
            NOTARY_AUTH=(--apple-id "$APPLE_ID" --password "$NOTARY_PASSWORD")
        else
            echo "❌ No notary credentials. Set KEY_ID / KEY_ISSUER / KEY_PATH" >&2
            echo "   (recommended — see https://developer.apple.com/account/resources/authkeys/list)" >&2
            echo "   or APPLE_ID / NOTARY_PASSWORD." >&2
            echo "   (Or run ./scripts/sign.sh --sign-only to sign without notarization)." >&2
            exit 1
        fi
    fi
fi

# ----- Steps ------------------------------------------------------------

if [ ! -d "$INPUT" ]; then
    echo "❌ $INPUT not found. Run ./build.sh first." >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
rm -rf "$OUTPUT"
cp -R "$INPUT" "$OUTPUT"

case "$MODE" in
    --notary-only)
        echo "==> Skipping re-sign, uploading existing build"
        ;;
    --ad-hoc)
        echo "==> Signing (ad-hoc): $OUTPUT"
        codesign --force --deep --sign - "$OUTPUT"
        echo "==> Verifying signature"
        codesign --verify --deep --strict --verbose=2 "$OUTPUT"
        ;;
    *)
        echo "==> Re-signing with: $IDENTITY"
        codesign \
            --force \
            --deep \
            --options runtime \
            --timestamp \
            --sign "$IDENTITY" \
            "$OUTPUT"

        echo "==> Verifying signature"
        codesign --verify --deep --strict --verbose=2 "$OUTPUT"
        spctl --assess --type execute --verbose=2 "$OUTPUT" || true
        ;;
esac

if [ "$MODE" != "--sign-only" ] && [ "$MODE" != "--ad-hoc" ]; then
    echo "==> Submitting for notarisation"
    # Create a zip because notarytool expects a file (or you can pass --dir).
    NOTARY_ZIP="$ROOT/dist/notary-submit.zip"
    rm -f "$NOTARY_ZIP"
    ditto -c -k --keepParent "$OUTPUT" "$NOTARY_ZIP"

    SUBMISSION_ID="$(xcrun notarytool submit "$NOTARY_ZIP" \
        "${NOTARY_AUTH[@]}" \
        --wait \
        --timeout 30m 2>&1 \
        | tee /dev/stderr \
        | awk '/^  id:/ {print $2; exit}')"

    if [ -z "$SUBMISSION_ID" ]; then
        echo "❌ Notary submission failed. Check output above." >&2
        exit 1
    fi

    echo "==> Submission ID: $SUBMISSION_ID"

    echo "==> Stapling ticket"
    xcrun stapler staple "$OUTPUT"
    xcrun stapler validate "$OUTPUT"

    rm -f "$NOTARY_ZIP"
fi

echo "==> Done. Signed build at: $OUTPUT"
echo "    Verify with: codesign -dv --verbose=2 \"$OUTPUT\""
echo "    Verify with: spctl --assess --type execute -vv \"$OUTPUT\""

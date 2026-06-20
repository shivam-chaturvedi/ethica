#!/usr/bin/env bash
# Add a real, scannable EAN-13 barcode image to the booted iOS Simulator's Photos library.
# The stock simulator "barcode" thumbnail is often not machine-readable.

set -euo pipefail

OUT="/tmp/ethica-test-barcode.png"
BARCODE="012345678905"

echo "→ Downloading test barcode (${BARCODE})..."
curl -sL "https://barcode.tec-it.com/barcode.ashx?data=${BARCODE}&code=EAN13&translate-esc=on" -o "$OUT"

echo "→ Adding to booted Simulator photo library..."
xcrun simctl addmedia booted "$OUT"

echo "✓ Done. Open Ethica → barcode scanner → photo picker → select the new barcode image."

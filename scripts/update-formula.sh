#!/usr/bin/env bash
set -euo pipefail

# Usage: ./scripts/update-formula.sh VERSION SHA256
# Updates Formula/envpocket.rb from template with placeholders

if [ $# -lt 2 ]; then
  echo "Usage: $0 VERSION SHA256"
  echo "Example: $0 0.5.3 abc123def456..."
  exit 1
fi

VERSION="$1"
SHA256="$2"

TEMPLATE="Formula/envpocket.rb.template"
OUTPUT="Formula/envpocket.rb"

if [ ! -f "$TEMPLATE" ]; then
  echo "Error: Template not found: $TEMPLATE"
  exit 1
fi

# Replace placeholders in template
sed "s/{{VERSION}}/$VERSION/g" "$TEMPLATE" | \
sed "s/{{SHA256}}/$SHA256/g" > "$OUTPUT"

echo "✓ Updated $OUTPUT with version $VERSION"

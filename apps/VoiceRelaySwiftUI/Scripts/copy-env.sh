#!/usr/bin/env bash
set -euo pipefail
SRC_DIR="$(cd "$(dirname "$0")"/../../.. && pwd)"
APP_BUILT_PATH="$CONFIGURATION_BUILD_DIR/$PRODUCT_NAME.app"
cp -f "$SRC_DIR/.env" "$APP_BUILT_PATH/.env" 2>/dev/null || true
echo "Copied .env to $APP_BUILT_PATH/.env"


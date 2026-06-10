#!/bin/sh
set -eu

case "${CONFIGURATION:-}" in
  Debug) exit 0 ;;
esac

frameworks_dir="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
[ -d "$frameworks_dir" ] || exit 0

rm -rf "$frameworks_dir/integration_test.framework"

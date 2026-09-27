#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
TEST_OUTPUT_DIR=$(mktemp -d /tmp/MovieInfoEdit-regression.XXXXXX)
trap 'rm -rf "$TEST_OUTPUT_DIR"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library \
  -target "$(uname -m)-apple-macos26.0" -module-cache-path "$TEST_OUTPUT_DIR/modules" \
  MovieInfoEdit/Models.swift MovieInfoEdit/MediaFiles.swift MovieInfoEdit/NFOStore.swift \
  MovieInfoEdit/WritePlan.swift MovieInfoEdit/SessionStore.swift MovieInfoEdit/LibraryReview.swift \
  Shared/NFOPreviewDocument.swift \
  Tests/MediaFileRegression.swift -o "$TEST_OUTPUT_DIR/media-tests"
"$TEST_OUTPUT_DIR/media-tests"

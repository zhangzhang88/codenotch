#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'This test build requires macOS and Xcode.' >&2
    exit 1
fi
command -v xcodegen >/dev/null || { echo 'Install xcodegen first: brew install xcodegen' >&2; exit 1; }
xcodebuild -version
xcodegen generate --spec project-local.yml
resolved=CodenotchQuotaTest.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
mkdir -p "$resolved"
cp Package.resolved "$resolved/Package.resolved"
# The test host has its own bundle identifier and preferences.
xcodebuild -project CodenotchQuotaTest.xcodeproj -scheme Codenotch \
    -destination "platform=macOS,arch=$(uname -m)" -configuration Debug \
    -derivedDataPath build/quota-tests \
    CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO test
# Use the upstream project's existing ad-hoc build/signing recipe. -o gen
# preserves the independently identified project generated above.
make -o gen build-ci PROJECT=CodenotchQuotaTest.xcodeproj CI_DIR=build/quota-test
echo 'Built test app: build/quota-test/DerivedData/Build/Products/Release/Codenotch.app'
echo 'No installed application was replaced or launched.'

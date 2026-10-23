#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
identity=$(./scripts/signing-identity.sh)
xcodebuild -project Dreadline.xcodeproj -scheme Dreadline -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGN_IDENTITY="$identity" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= ENABLE_DEBUG_DYLIB=NO CODE_SIGNING_ALLOWED=YES test "$@"

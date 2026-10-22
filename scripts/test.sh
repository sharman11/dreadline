#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
xcodebuild -project Dreadline.xcodeproj -scheme Dreadline -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test "$@"

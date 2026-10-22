#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
xcodebuild -project Dreadline.xcodeproj -scheme Dreadline -configuration Debug -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build "$@"

#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
./scripts/build.sh
open build/DerivedData/Build/Products/Debug/Dreadline.app

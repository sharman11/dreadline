#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
./scripts/build.sh
artifact_dir="build/Local-$(date +%Y%m%d-%H%M%S)"
if [[ -e "$artifact_dir" ]]; then
  print -u2 'Package directory already exists; wait a second and retry.'
  exit 2
fi
mkdir -p "$artifact_dir"
/usr/bin/ditto build/DerivedData/Build/Products/Debug/Dreadline.app "$artifact_dir/Dreadline.app"
/usr/bin/codesign --verify --deep --strict "$artifact_dir/Dreadline.app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$artifact_dir/Dreadline.app" "$artifact_dir/Dreadline-local.zip"
print "Ad hoc signed local package: $artifact_dir (not notarized)"

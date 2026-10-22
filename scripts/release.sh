#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  print -u2 'Set DEVELOPMENT_TEAM to your Apple Developer team ID. No upload/notarization is performed.'
  exit 2
fi
if [[ -e build/Dreadline.xcarchive || -e build/Dreadline.zip ]]; then
  print -u2 'Archive already exists. Move it aside before making another archive.'
  exit 2
fi
xcodebuild -project Dreadline.xcodeproj -scheme Dreadline -configuration Release -archivePath build/Dreadline.xcarchive DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" archive
/usr/bin/ditto -c -k --sequesterRsrc --keepParent build/Dreadline.xcarchive/Products/Applications/Dreadline.app build/Dreadline.zip
print 'Archive and local ZIP prepared. Developer ID export, notarization, and stapling remain manual release steps.'

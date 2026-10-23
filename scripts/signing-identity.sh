#!/bin/zsh
# Prints the code signing identity for local builds.
# A stable local certificate keeps macOS privacy grants (Accessibility) across rebuilds;
# ad hoc signing ("-") ties them to one exact binary, so every rebuild loses them.
# Builds use ENABLE_DEBUG_DYLIB=NO: hardened runtime rejects a separate debug dylib without a Team ID.
# Create the certificate once with: ./scripts/create-local-signing-cert.sh
if security find-certificate -c "Dreadline Local Signing" >/dev/null 2>&1; then
  print -r -- "Dreadline Local Signing"
else
  print -r -- "-"
fi

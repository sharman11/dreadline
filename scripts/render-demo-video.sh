#!/bin/zsh
# Renders the Dreadline trailer: ./scripts/render-demo-video.sh music.mp3 [out.mp4]
set -euo pipefail
cd "${0:A:h}/.."
music=${1:?usage: render-demo-video.sh music.mp3 [out.mp4]}
out=${2:-$PWD/build/demo/Dreadline-demo.mp4}
mkdir -p "${out:h}"
TEST_RUNNER_DEMO_VIDEO_MUSIC="${music:A}" TEST_RUNNER_DEMO_VIDEO_OUT="${out:A}" \
  ./scripts/test.sh -only-testing:DreadlineTests/DemoVideoTests
echo "Wrote $out"

#!/usr/bin/env bash
# Stream your Mac webcam into the iOS Simulator for Ethica barcode testing.
# Requires: Node.js 18+, Xcode Simulator booted, serve-sim (installed via npx).
#
# Usage:
#   ./scripts/simulator-mac-camera.sh              # launch app with Mac webcam
#   ./scripts/simulator-mac-camera.sh switch       # hot-swap webcam on running app
#   ./scripts/simulator-mac-camera.sh list         # list available Mac cameras
#   ./scripts/simulator-mac-camera.sh file <path>  # use a still image or video loop
#   ./scripts/simulator-mac-camera.sh stop         # stop the camera helper

set -euo pipefail

BUNDLE_ID="com.ArhamJain.ethica.Ethica"
CMD="${1:-start}"

run_serve_sim() {
  npx --yes serve-sim@latest "$@"
}

print_help() {
  cat <<EOF
Ethica — Simulator Mac Camera

The iOS Simulator has no real camera. This script injects your Mac webcam
into the simulator so live barcode scanning works during development.

Commands:
  start, webcam     Launch Ethica in the booted simulator with Mac webcam (default)
  switch            Switch the running simulator app to Mac webcam (no relaunch)
  list              List Mac camera devices
  file <path>       Launch with a still image or looping video as the camera feed
  stop              Stop the simulator camera helper
  help              Show this message

Examples:
  ./scripts/simulator-mac-camera.sh
  ./scripts/simulator-mac-camera.sh switch
  ./scripts/simulator-mac-camera.sh list
  ./scripts/simulator-mac-camera.sh file ~/Desktop/barcode.png
  ./scripts/simulator-mac-camera.sh webcam "MacBook Pro Camera"

Workflow (with Xcode):
  1. Boot a simulator (e.g. iPhone 17)
  2. Run this script once: ./scripts/simulator-mac-camera.sh switch
  3. Return to Ethica's barcode scanner — tap Retry Camera if needed

EOF
}

case "$CMD" in
  start|webcam)
    shift || true
    echo "→ Injecting Mac webcam into Simulator for ${BUNDLE_ID}"
    run_serve_sim camera "$BUNDLE_ID" --webcam "$@"
    ;;
  switch)
    shift || true
    echo "→ Switching Simulator camera feed to Mac webcam"
    run_serve_sim camera switch webcam "$@"
    ;;
  list)
    run_serve_sim camera --list-webcams
    ;;
  file)
    FILE_PATH="${2:-}"
    if [[ -z "$FILE_PATH" ]]; then
      echo "Usage: $0 file <path-to-image-or-video>"
      exit 1
    fi
    echo "→ Injecting file camera feed: ${FILE_PATH}"
    run_serve_sim camera "$BUNDLE_ID" --file "$FILE_PATH"
    ;;
  stop)
    run_serve_sim camera --stop-webcam
    ;;
  help|-h|--help)
    print_help
    ;;
  *)
    echo "Unknown command: ${CMD}"
    print_help
    exit 1
    ;;
esac

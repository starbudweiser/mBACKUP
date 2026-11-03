#!/bin/zsh
# Compile et lance les tests de logique (import, planification, rsync, bilans, traductions).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -swift-version 5 -target arm64-apple-macos15 -o build/tests \
  Sources/Model.swift Sources/Importer.swift Sources/RsyncCommand.swift Sources/L10n.swift tests/main.swift
build/tests
rm -rf build

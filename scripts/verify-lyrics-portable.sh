#!/usr/bin/env bash
# Run portable lyrics tests on macOS or Linux without launching the application.
set -euo pipefail
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if [[ -n "${SWIFTC:-}" ]]; then
  compiler="$SWIFTC"
elif command -v swiftc >/dev/null 2>&1; then
  compiler="$(command -v swiftc)"
elif command -v xcrun >/dev/null 2>&1; then
  compiler="$(xcrun --find swiftc)"
else
  printf '%s\n' 'error: Swift compiler not found. Install Swift or set SWIFTC to its executable path.' >&2
  exit 1
fi

required=(
  LyricsCore.swift LyricsStore.swift LyricsProvider.swift LyricsService.swift
  Tests/LyricsCoreTests.swift Tests/LyricsStoreTests.swift
  Tests/LyricsProviderTests.swift Tests/LyricsServiceTests.swift
  Tests/Fixtures/prototype.lrc
)
for source in "${required[@]}"; do
  if [[ ! -f "$source" ]]; then
    printf 'error: required lyrics test input is missing: %s\n' "$source" >&2
    exit 1
  fi
done

build_dir="$(mktemp -d "${TMPDIR:-/tmp}/lyrics-portable.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
mkdir -p "$build_dir/module-cache"

run_suite() {
  local name="$1"
  shift
  printf '\nRunning %s\n' "$name"
  "$compiler" -swift-version 5 -module-cache-path "$build_dir/module-cache" \
    "$@" -o "$build_dir/$name"
  "$build_dir/$name"
}

"$compiler" --version
run_suite LyricsCoreTests LyricsCore.swift Tests/LyricsCoreTests.swift
run_suite LyricsStoreTests LyricsCore.swift LyricsStore.swift Tests/LyricsStoreTests.swift
run_suite LyricsProviderTests LyricsCore.swift LyricsProvider.swift Tests/LyricsProviderTests.swift
run_suite LyricsServiceTests LyricsCore.swift LyricsStore.swift LyricsProvider.swift \
  LyricsService.swift Tests/LyricsServiceTests.swift
printf '\nPASS: all portable lyrics test suites\n'

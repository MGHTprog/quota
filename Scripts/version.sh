#!/usr/bin/env bash

resolve_app_version() {
  local root_dir="$1"
  local version="${VERSION:-}"

  if [[ -z "$version" ]]; then
    version="$(git -C "$root_dir" describe --tags --abbrev=0 --match "v[0-9]*" 2>/dev/null || true)"
  fi

  version="${version#v}"

  if [[ -z "$version" ]]; then
    version="0.0.0"
  fi

  printf "%s" "$version"
}

resolve_build_version() {
  local root_dir="$1"
  local build_version="${BUILD_VERSION:-}"

  if [[ -z "$build_version" ]]; then
    build_version="$(git -C "$root_dir" rev-list --count HEAD 2>/dev/null || true)"
  fi

  if [[ -z "$build_version" ]]; then
    build_version="0"
  fi

  printf "%s" "$build_version"
}

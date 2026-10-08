#!/usr/bin/env bash
# Fastlane match encrypts certificates/profiles before writing this private branch.
set -euo pipefail
repo_url="https://github.com/${GITHUB_REPOSITORY:?}.git"
git config --global user.name 'RepFlow Automation'
git config --global user.email 'repflow-automation@users.noreply.github.com'
git config --global credential.https://github.com.helper '!gh auth git-credential'
existing=$(git ls-remote --heads "$repo_url" refs/heads/signing)
if [[ -n "$existing" ]]; then exit 0; fi
signing_dir=$(mktemp -d "${RUNNER_TEMP:?}/repflow-signing.XXXXXX")
trap 'rm -rf "$signing_dir"' EXIT
git -C "$signing_dir" init -b signing
git -C "$signing_dir" commit --allow-empty -m 'Initialize private encrypted signing assets'
git -C "$signing_dir" remote add origin "$repo_url"
git -C "$signing_dir" push origin signing

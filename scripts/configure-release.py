#!/usr/bin/env python3
"""Configure a CI copy of project.yml; no credentials are written to the project."""
import argparse
import os
from pathlib import Path
import re

parser = argparse.ArgumentParser()
parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1] / 'project.yml')
args = parser.parse_args()
bundle = os.environ.get('APP_BUNDLE_ID', '')
team = os.environ.get('APPLE_TEAM_ID', '')
version = os.environ.get('APP_VERSION', '1.0.0')
run = os.environ.get('GITHUB_RUN_NUMBER', '')
attempt = os.environ.get('GITHUB_RUN_ATTEMPT', '')
if not re.fullmatch(r'[A-Za-z0-9]+(?:\.[A-Za-z0-9-]+){2,}', bundle) or bundle.startswith('com.example.'):
    raise SystemExit('APP_BUNDLE_ID must be your registered unique reverse-DNS identifier, not com.example.')
if not re.fullmatch(r'[A-Z0-9]{10}', team):
    raise SystemExit('APPLE_TEAM_ID must be the 10-character Apple Developer Team ID.')
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise SystemExit('APP_VERSION must be a numeric version, for example 1.0.0.')
if not run.isdigit() or not attempt.isdigit() or not 0 < int(run) <= 9999 or not 0 < int(attempt) <= 99:
    raise SystemExit('GitHub run/attempt must fit CFBundleVersion; increase APP_VERSION and reset the build scheme when necessary.')
text = args.project.read_text()
if 'com.example.RepFlow' not in text:
    raise SystemExit('Expected the original project.yml template. Check out a fresh source copy before releasing.')
text = text.replace('com.example.RepFlow', bundle)
text, version_count = re.subn(r"MARKETING_VERSION: '[^']+'", f"MARKETING_VERSION: '{version}'", text)
text, build_count = re.subn(r"CURRENT_PROJECT_VERSION: '[^']+'", f"CURRENT_PROJECT_VERSION: '{run}.{attempt}'", text)
if version_count != 1 or build_count != 1:
    raise SystemExit('Expected exactly one marketing version and build number.')
text = text.replace("    SWIFT_VERSION: '5.0'", f"    SWIFT_VERSION: '5.0'\n    DEVELOPMENT_TEAM: {team}")
args.project.write_text(text)
print(f'Release configured: {bundle}, version {version}, build {run}.{attempt}.')

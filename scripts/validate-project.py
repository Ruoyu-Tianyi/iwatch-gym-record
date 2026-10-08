#!/usr/bin/env python3
"""Check native bundle relationships and delivered resources without Apple SDKs.
This is not an Xcode build or an App Store validation.
"""
from pathlib import Path
import json
import plistlib
import re
import sys

root = Path(__file__).resolve().parents[1]
checks = 0

def require(condition, message):
    global checks
    if not condition:
        raise SystemExit('FAIL: ' + message)
    checks += 1

def plist(path):
    with (root / path).open('rb') as f:
        return plistlib.load(f)

phone = plist('Resources/Phone/Info.plist')
watch = plist('Resources/Watch/Info.plist')
entitlements = plist('Resources/Watch/RepFlowWatch.entitlements')
privacy = plist('Resources/PrivacyInfo.xcprivacy')
require(phone['CFBundleDisplayName'] == '组迹', 'Phone display name')
for label, info in [('Phone', phone), ('Watch', watch)]:
    require(info['CFBundleShortVersionString'] == '$(MARKETING_VERSION)', label + ' version follows build setting')
    require(info['CFBundleVersion'] == '$(CURRENT_PROJECT_VERSION)', label + ' build number follows build setting')
require(watch['WKApplication'] is True, 'Modern standalone watch app marker')
require(watch['WKRunsIndependentlyOfCompanionApp'] is True, 'Independent watch use')
require('workout-processing' in watch['WKBackgroundModes'], 'Workout background mode')
require(entitlements.get('com.apple.developer.healthkit') is True, 'HealthKit entitlement')
for key in ['NSHealthShareUsageDescription', 'NSHealthUpdateUsageDescription', 'NSMotionUsageDescription']:
    require(len(watch.get(key, '')) > 15, key + ' purpose text')
require(privacy['NSPrivacyTracking'] is False, 'Tracking disabled')
require(privacy['NSPrivacyCollectedDataTypes'] == [], 'No server collection declared')

project = (root / 'RepFlow.xcodeproj/project.pbxproj').read_text()
require('Embed Watch Content' in project, 'Watch app embedded in iPhone bundle')
require('RepFlowCore' in project, 'Local shared package linked')
bundle_ids = re.findall(r'PRODUCT_BUNDLE_IDENTIFIER = "?([^;"\s]+)"?;', project)
companion = watch['WKCompanionAppBundleIdentifier']
require(companion in bundle_ids, 'Companion bundle identifier matches phone target')
require(any(value.startswith(companion + '.') for value in bundle_ids), 'Watch bundle identifier is prefixed by companion identifier')
for scheme in ['RepFlow', 'RepFlowWatch']:
    require((root / f'RepFlow.xcodeproj/xcshareddata/xcschemes/{scheme}.xcscheme').exists(), scheme + ' shared scheme')
for folder in ['PhoneApp', 'WatchApp']:
    mains = [f for f in (root / folder).rglob('*.swift') if '@main' in f.read_text()]
    require(len(mains) == 1, folder + ' single entrypoint')
for target, platform in [('Phone', 'ios'), ('Watch', 'watchos')]:
    icon = root / 'Resources' / target / 'Assets.xcassets/AppIcon.appiconset'
    contents = json.loads((icon / 'Contents.json').read_text())
    for spec in contents['images']:
        require(spec['platform'] == platform, target + ' icon platform')
        require((icon / spec['filename']).is_file(), target + ' icon file')
        # PNG IHDR is width, height, bit depth, color type; type 2 is opaque RGB.
        blob = (icon / spec['filename']).read_bytes()
        require(blob[:8] == b'\x89PNG\r\n\x1a\n', target + ' PNG header')
        require(int.from_bytes(blob[16:20], 'big') == 1024 and int.from_bytes(blob[20:24], 'big') == 1024, target + ' 1024 icon')
        require(blob[25] == 2, target + ' opaque RGB icon')
print(f'PASS: {checks} project/resource checks. Apple SDK compilation remains a separate check.')

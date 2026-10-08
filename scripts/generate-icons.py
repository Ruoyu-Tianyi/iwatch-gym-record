#!/usr/bin/env python3
"""Generate the original RepFlow app mark. Optional; delivered PNGs are ready to use.
Requires Pillow: python3 -m pip install pillow
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
size = 1024
im = Image.new('RGB', (size, size), '#0C1515')
d = ImageDraw.Draw(im)
# A lifting bar and three rising repetitions enclosed by a progress arc.
d.arc((136, 136, 888, 888), 125, 415, fill='#C9F76B', width=58)
d.rounded_rectangle((306, 419, 718, 475), radius=28, fill='#C9F76B')
for bounds in [(282, 339, 338, 555), (686, 339, 742, 555)]:
    d.rounded_rectangle(bounds, radius=23, fill='#C9F76B')
for x, y in [(384, 611), (485, 581), (586, 551)]:
    d.rounded_rectangle((x, y, x + 58, 710), radius=22, fill='#FFFFFF')

for target, platform in [('Phone', 'ios'), ('Watch', 'watchos')]:
    catalog = root / 'Resources' / target / 'Assets.xcassets'
    icon = catalog / 'AppIcon.appiconset'
    accent = catalog / 'AccentColor.colorset'
    icon.mkdir(parents=True, exist_ok=True)
    accent.mkdir(parents=True, exist_ok=True)
    im.save(icon / 'AppIcon.png')
    (icon / 'Contents.json').write_text(json.dumps({
        'images': [{'filename': 'AppIcon.png', 'idiom': 'universal',
                    'platform': platform, 'size': '1024x1024'}],
        'info': {'author': 'xcode', 'version': 1}
    }, indent=2) + '\n')
    (accent / 'Contents.json').write_text(json.dumps({
        'colors': [{'idiom': 'universal', 'color': {'color-space': 'srgb',
                    'components': {'alpha': '1.000', 'red': '0.788',
                                   'green': '0.969', 'blue': '0.420'}}}],
        'info': {'author': 'xcode', 'version': 1}
    }, indent=2) + '\n')
    (catalog / 'Contents.json').write_text('{"info":{"author":"xcode","version":1}}\n')
print('Generated opaque 1024 px app icons for iPhone and Apple Watch.')

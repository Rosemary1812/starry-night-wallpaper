#!/usr/bin/env python3
"""Independent source-space QA regions for the three retained motion studies.

Does not read production mask geometry. Runs the bundled full-cycle checker.
"""
import json
from pathlib import Path
import subprocess
import sys
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
regions = {
    'the-scream': ([(0, .35, 1, 1), (0, 0, 1, .075)], (.3, .17, .65, .23)),
    'circular-forms': ([(0, 0, 1, .01), (0, .99, 1, 1)], (.15, .2, .30, .45)),
    'concentric-circles': ([(0, 0, 1, .015), (0, .985, 1, 1)], (.10, .12, .16, .23)),
}
records = json.loads((root/'docs/new-art-movements-sources.json').read_text())
for record in records:
    slug = record['slug']
    folder = root/'dist/motion-studies'/slug
    with Image.open(folder/'neutral.png') as im:
        size = im.size
    x,y,w,h = record['crop']
    def rectangle(draw, r):
        a,b,c,d = r
        draw.rectangle(((a-x)/w*size[0], (b-y)/h*size[1],
                        (c-x)/w*size[0], (d-y)/h*size[1]),fill=255)
    fixed = Image.new('L',size)
    for r in regions[slug][0]: rectangle(ImageDraw.Draw(fixed),r)
    fixed.save(folder/'expected-fixed.png')
    motion = Image.new('L',size)
    rectangle(ImageDraw.Draw(motion),regions[slug][1])
    motion.save(folder/'expected-motion.png')
    subprocess.run([sys.executable,str(root/'.agents/skills/author-painting-wallpaper/scripts/check-frames.py'),
        '--frames',str(folder),'--neutral',str(folder/'neutral.png'),
        '--protected-mask',str(folder/'expected-fixed.png'),'--motion-mask',str(folder/'expected-motion.png'),
        '--kind','native-metal','--fps','30','--duration','24','--min-motion-mean','0.02',
        '--report',str(folder/'metrics.json')],check=True)

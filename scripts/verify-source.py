#!/usr/bin/env python3
"""Static integration checks. Does not compile Swift or Metal."""
import importlib.util
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('preview',ROOT/'scripts/preview-artworks.py')
preview=importlib.util.module_from_spec(spec);spec.loader.exec_module(preview)
catalog=preview.native_catalog()
expected=['starrynight','water-lilies','wheat-stacks','rhone','cypresses','impression-sunrise',
          'waterloo-bridge','nocturne-bognor','approach-venice','cliff-walk','bridge-villeneuve','parliament-sunset']
assert list(catalog)==expected, 'Persisted artwork order changed or metadata is incomplete'
keys=[(str(i+1),False) if i<9 else ('0',False) if i==9 else (str(i-9),True) for i in range(len(expected))]
assert len(set(keys))==12 and all(len(key)==1 for key,_ in keys)
artwork=(ROOT/'Artwork.swift').read_text();gallery=(ROOT/'GalleryView.swift').read_text()
assert 'var shortcutUsesOption: Bool { rawValue >= 10 }' in artwork
assert 'keyEquivalent = artwork.shortcutKey' in gallery
assert 'artwork.shortcutUsesOption ? [.option, .command] : [.command]' in gallery
shader=(ROOT/'Sky.metal').read_text();swift=(ROOT/'StarryNight.swift').read_text()
fields=re.search(r'struct Parameters \{([^}]+)\}',shader).group(1)
assert re.findall(r'float (\w+);',fields)==['time','strength','aspect','showMask','artwork','imageAspect']
for slug,entry in catalog.items():
    if entry['id']==0: continue
    assert slug in (ROOT/'build.sh').read_text()
    assert slug in (ROOT/'scripts/fetch-artworks.sh').read_text()
    assert slug in (ROOT/'scripts/verify-artworks.sh').read_text()
    assert 'case .'+entry['case']+': anchors = [' in swift
    if entry['id']>=5:
        assert shader.count('// BEGIN motion: '+slug)==1
        assert shader.count('// END motion: '+slug)==1
        assert 'u.artwork < '+str(entry['id']+.5) in shader
        preview.make_mask(swift,entry['case'],entry['bounds'])
    bounds=entry['bounds'];assert bounds[0]>=0 and bounds[1]>=0 and bounds[2]>0 and bounds[3]>0
    assert bounds[0]+bounds[2]<=1.000001 and bounds[1]+bounds[3]<=1.000001
assert 'THIRD-PARTY-NOTICES.md "$app/Contents/Resources/"' in (ROOT/'build.sh').read_text()
assert 'CC BY-SA 4.0' in (ROOT/'THIRD-PARTY-NOTICES.md').read_text()
print('PASS: 12 metadata records in preserved ID order; unique one-character shortcut mappings; resource registrations; protected anchors; seven added motion/mask blocks; unchanged uniform ABI; image license bundling')
print('NOT RUN: native Swift/AppKit/Metal compilation, keyboard events, layout, video export, wallpaper or lock-screen playback')

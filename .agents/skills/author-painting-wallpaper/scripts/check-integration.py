#!/usr/bin/env python3
"""Check current source registrations without compiling or running the app."""
import argparse
import json
from pathlib import Path
import re
import sys
sys.dont_write_bytecode = True
from _repo import block, catalog, text


def compact(s):
    return re.sub(r'\s+', '', s)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--repo', type=Path, default=Path('.'))
    p.add_argument('--baseline', type=Path, help='Earlier source tree for persisted ID/slug prefix comparison')
    args = p.parse_args()
    errors, passed, not_run = [], [], ['Swift/Metal compilation', 'actual keyboard events', 'visual quality', 'license source-page verification', 'native gallery/export/wallpaper playback']
    try:
        entries = catalog(args.repo)
        source = text(args.repo, 'Artwork.swift')
        swift = text(args.repo, 'StarryNight.swift')
        shader = text(args.repo, 'Sky.metal')
        gallery = text(args.repo, 'GalleryView.swift')
        build = text(args.repo, 'build.sh')
        fetch = text(args.repo, 'scripts/fetch-artworks.sh')
        verify = text(args.repo, 'scripts/verify-artworks.sh')
        notices = text(args.repo, 'THIRD-PARTY-NOTICES.md')
        passed.append(f'{len(entries)} unique cases/slugs and complete metadata arrays')
        if args.baseline:
            old = catalog(args.baseline)
            if [(e['case'], e['filename']) for e in entries[:len(old)]] != [(e['case'], e['filename']) for e in old]:
                errors.append('Persisted artwork ID/slug prefix changed')
            else:
                passed.append(f'{len(old)} previous IDs/slugs preserved')
        else:
            not_run.append('Historical ID compatibility (supply --baseline)')
        sf = re.findall(r'var\s+(\w+)\s*:\s*(\w+)', block(swift, 'struct Parameters'))
        mf = re.findall(r'(\w+)\s+(\w+)\s*;', block(shader, 'struct Parameters'))
        if not sf or sf != [(name, 'Float' if typ == 'float' else typ) for typ, name in mf] or any(typ != 'Float' for _, typ in sf):
            errors.append('Unsupported or mismatched Swift/Metal Parameters layout')
        else:
            passed.append('Swift/Metal float field order and types agree')
        for e in entries:
            slug = e['filename']
            for name, body in [('build.sh', build), ('verify-artworks.sh', verify)]:
                if slug not in body:
                    errors.append(f'{slug}: missing registration in {name}')
            if e['id'] == 0:
                continue
            if slug not in fetch:
                errors.append(slug + ': missing download registration')
            if not re.search(r'case\s+\.' + re.escape(e['case']) + r'\s*:\s*anchors\s*=', swift):
                errors.append(slug + ': missing protected verification anchors')
            if not re.search(r'if\s+artwork\s*==\s*\.' + re.escape(e['case']) + r'\s*\{', swift):
                errors.append(slug + ': missing artwork mask branch')
            if not re.search(r'u\.artwork\s*<\s*' + re.escape(str(e['id'] + .5)) + r'\b', shader):
                # The original five-artwork renderer ends its chain with else.
                marker = re.search(r'else\s+if\s*\(u\.artwork\s*<\s*' + re.escape(str(e['id'] - .5)) + r'\)', shader)
                fallback = False
                if e['id'] == len(entries) - 1 and marker:
                    body = block(shader, marker.group(0))
                    opening = shader.index('{', marker.start())
                    fallback = bool(re.match(r'\s*else\s*\{', shader[opening + len(body) + 2:]))
                if not fallback:
                    errors.append(slug + ': missing shader selection threshold/final fallback')
        s, g = compact(source), compact(gallery)
        if 'keyEquivalent=String(artwork.rawValue+1)' in g:
            keys = [(str(e['id'] + 1), 'command') for e in entries]
        elif all(token in s for token in [
                'varshortcutKey:String{rawValue<9?String(rawValue+1):rawValue==9?"0":String(rawValue-9)}',
                'varshortcutUsesOption:Bool{rawValue>=10}']) and all(token in g for token in [
                'keyEquivalent=artwork.shortcutKey',
                'keyEquivalentModifierMask=artwork.shortcutUsesOption?[.option,.command]:[.command]']):
            keys = [(str(i + 1) if i < 9 else '0' if i == 9 else str(i - 9), 'option-command' if i >= 10 else 'command') for i in range(len(entries))]
        else:
            raise ValueError('Unsupported shortcut implementation; update checker and verify native key events')
        if any(len(k) != 1 for k, _ in keys) or len(set(keys)) != len(keys):
            errors.append('Shortcut is not a unique one-character key/modifier pair')
        else:
            passed.append('Unique one-character shortcut mappings')
        if 'THIRD-PARTY-NOTICES.md' not in build:
            errors.append('Build does not bundle third-party notices')
        if not notices.strip():
            errors.append('Third-party notices are empty')
        bounds = re.findall(r'CGRect\(x:\s*([-+.\d]+),\s*y:\s*([-+.\d]+),\s*width:\s*([-+.\d]+),\s*height:\s*([-+.\d]+)\)', source)
        if not bounds:
            errors.append('No supported imageBounds rectangles found')
        for raw in bounds:
            x, y, w, h = map(float, raw)
            if min(x, y) < 0 or min(w, h) <= 0 or x + w > 1.000001 or y + h > 1.000001:
                errors.append('Out-of-range crop bounds: ' + str(raw))
        if not errors:
            passed.append('Asset/shader/mask/sample registrations, crop ranges and notice bundling found')
    except (OSError, ValueError) as exc:
        errors.append(str(exc))
    report = {'stage': 'static integration only', 'status': 'FAIL' if errors else 'PASS', 'passed': passed, 'errors': errors, 'not_run': not_run}
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())

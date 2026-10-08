#!/usr/bin/env python3
"""Read-only capability, source, asset and optional provenance preflight."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import sys
from urllib.parse import urlparse
sys.dont_write_bytecode = True
from _repo import catalog, digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path('.'))
    parser.add_argument('--artwork', required=True)
    parser.add_argument('--assets-dir', type=Path)
    parser.add_argument('--provenance', type=Path)
    parser.add_argument('--image', type=Path, help='Inspect a new source image before catalog integration')
    args = parser.parse_args()
    root = args.repo.resolve()
    assets = args.assets_dir or Path(os.environ.get('STARRY_ASSETS_DIR', root / 'assets'))
    errors, warnings = [], []
    report = {'stage': 'read-only preflight', 'repo': str(root), 'errors': errors, 'warnings': warnings}
    try:
        entries = catalog(root)
        entry = next((e for e in entries if e['filename'] == args.artwork), None)
        if entry is None:
            if args.image is None or not re.fullmatch('[a-z0-9-]+', args.artwork):
                raise ValueError('Unknown artwork; supply --image for a new valid slug: ' + args.artwork)
            warnings.append('New artwork is not yet integrated in the catalog')
        report['artwork'] = entry
        report['catalog_count'] = len(entries)
        report['source_sha256'] = {n: digest(root / n) for n in ['Artwork.swift', 'StarryNight.swift', 'Sky.metal']}
        capabilities = {'platform': platform.system(), 'python': platform.python_version()}
        capabilities.update({name: shutil.which(name) for name in ['node', 'ffmpeg', 'zsh', 'xcrun']})
        capabilities.update({name: importlib.util.find_spec(name) is not None for name in ['PIL', 'numpy']})
        capabilities['native_candidate'] = platform.system() == 'Darwin' and bool(shutil.which('xcrun'))
        report['capabilities'] = capabilities
        if not capabilities['native_candidate']:
            warnings.append('Native AppKit/Metal, gallery, export and wallpaper playback NOT RUN; a compatible Mac is required')
        report['missing_build_assets'] = [str(assets / name) for name in
            [e['filename'] + '.jpg' for e in entries] + ['starry-night-flow.mp4'] if not (assets / name).is_file()]
        if report['missing_build_assets']:
            warnings.append('Full build assets are incomplete; see missing_build_assets')
        image = args.image or assets / (args.artwork + '.jpg')
        if not image.is_file():
            raise ValueError('Selected source image missing: ' + str(image))
        if not capabilities['PIL']:
            raise ValueError('Pillow is required to inspect the selected image')
        from PIL import Image
        with Image.open(image) as im:
            im.verify()
        with Image.open(image) as im:
            image_record = {'path': str(image.resolve()), 'sha256': digest(image), 'dimensions': list(im.size), 'mode': im.mode}
        report['image'] = image_record
        if args.provenance:
            record = json.loads(args.provenance.read_text())
            for key in ['slug', 'source_url', 'record_url', 'license', 'license_url', 'attribution', 'sha256', 'dimensions', 'derivative_obligations', 'changes']:
                if key not in record or record[key] in ['', None, []]:
                    errors.append('Missing provenance field: ' + key)
            for key in ['slug', 'source_url', 'record_url', 'license', 'license_url', 'attribution', 'sha256', 'derivative_obligations', 'changes']:
                if not isinstance(record.get(key), str) or not record.get(key, '').strip():
                    errors.append('Provenance field must be a nonempty string: ' + key)
            for key in ['source_url', 'record_url', 'license_url']:
                value = record.get(key, '')
                parsed = urlparse(value) if isinstance(value, str) else None
                if parsed is None or parsed.scheme not in ['http', 'https'] or not parsed.netloc:
                    errors.append('Invalid provenance URL: ' + key)
            if record.get('slug') != args.artwork:
                errors.append('Provenance slug does not match selected artwork')
            if record.get('sha256') != image_record['sha256']:
                errors.append('Provenance SHA-256 does not match image')
            if record.get('dimensions') != image_record['dimensions']:
                errors.append('Provenance dimensions do not match image')
            report['provenance'] = 'Record checked structurally; source rights require source-page review'
        else:
            warnings.append('No provenance record supplied; licensing/provenance gate NOT RUN')
        report['preview_helper_available'] = (root / 'scripts/preview-artworks.py').is_file()
    except (OSError, ValueError, KeyError, TypeError) as exc:
        errors.append(str(exc))
    report['status'] = 'FAIL' if errors else 'PASS_WITH_LIMITS'
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())

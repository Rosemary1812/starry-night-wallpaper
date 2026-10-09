#!/usr/bin/env python3
"""Synthetic regression tests for helpers; not painting/native quality evidence."""
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


class Helpers(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='painting-skill-tests-')
        cls.work = Path(cls.temp.name)
        cls.frames = cls.work / 'frames'
        cls.frames.mkdir()
        neutral = np.full((16, 24, 3), 100, dtype=np.uint8)
        Image.fromarray(neutral).save(cls.work / 'neutral.png')
        protected = np.zeros((16, 24), dtype=np.uint8)
        protected[:, :8] = 255
        Image.fromarray(protected).save(cls.work / 'protected.png')
        motion = np.zeros((16, 24), dtype=np.uint8)
        motion[:, 12:] = 255
        Image.fromarray(motion).save(cls.work / 'motion.png')
        for i in range(721):
            pixels = neutral.copy()
            pixels[:, 12:, 0] = round(100 + 12 * math.sin(2 * math.pi * i / 720))
            Image.fromarray(pixels).save(cls.frames / f'frame-{i:04d}.png')
        cls.common = ['--frames', str(cls.frames), '--neutral', str(cls.work / 'neutral.png'), '--protected-mask', str(cls.work / 'protected.png'), '--motion-mask', str(cls.work / 'motion.png'), '--min-motion-mean', '1', '--kind', 'cpu-reference']

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def invoke(self, script, args):
        done = subprocess.run([sys.executable, str(HERE / script)] + args, capture_output=True, text=True)
        self.assertIn(done.returncode, [0, 1], done.stderr)
        return done.returncode, json.loads(done.stdout)

    def test_full_24_second_sequence_and_before(self):
        code, result = self.invoke('check-frames.py', self.common + ['--before', str(self.frames)])
        self.assertEqual(code, 0, result)
        self.assertEqual(result['after']['playback_frames'], 720)
        self.assertEqual(result['after']['protected_changed_pixels'], 0)
        self.assertEqual(result['after_minus_before']['whole_frame_mean_temporal_range'], 0)

    def test_dense_midcycle_silhouette_failure(self):
        path = self.frames / 'frame-0357.png'
        original = path.read_bytes()
        try:
            pixels = np.array(Image.open(path)); pixels[7, 7, 0] += 1
            Image.fromarray(pixels).save(path)
            code, result = self.invoke('check-frames.py', self.common)
            self.assertEqual(code, 1)
            self.assertEqual(result['after']['protected_changed_pixels'], 1)
            self.assertEqual(result['after']['inner_boundary_max_rgb_delta'], 1)
        finally:
            path.write_bytes(original)

    def test_missing_frame_fails(self):
        path = self.frames / 'frame-0360.png'; original = path.read_bytes(); path.unlink()
        try:
            code, result = self.invoke('check-frames.py', self.common)
            self.assertEqual(code, 1); self.assertIn('missing', result['errors'][0])
        finally:
            path.write_bytes(original)

    def test_endpoint_change_fails(self):
        path = self.frames / 'frame-0720.png'; original = path.read_bytes()
        try:
            pixels = np.array(Image.open(path)); pixels[7, 18, 0] += 1
            Image.fromarray(pixels).save(path)
            code, result = self.invoke('check-frames.py', self.common)
            self.assertEqual(code, 1); self.assertEqual(result['after']['endpoint_max_rgb_delta'], 1)
        finally:
            path.write_bytes(original)

    def test_wraparound_jump_fails(self):
        path = self.frames / 'frame-0719.png'; original = path.read_bytes()
        try:
            pixels = np.array(Image.open(path)); pixels[:, 12:, 0] += 50
            Image.fromarray(pixels).save(path)
            code, result = self.invoke('check-frames.py', self.common)
            self.assertEqual(code, 1)
            self.assertTrue(any('Wraparound' in s for s in result['errors']))
        finally:
            path.write_bytes(original)

    def test_wraparound_outside_motion_roi_fails(self):
        path = self.frames / 'frame-0719.png'; original = path.read_bytes()
        try:
            pixels = np.array(Image.open(path)); pixels[:, 8:12, 0] += 100
            Image.fromarray(pixels).save(path)
            code, result = self.invoke('check-frames.py', self.common)
            self.assertEqual(code, 1)
            self.assertTrue(any('Wraparound' in s for s in result['errors']))
        finally:
            path.write_bytes(original)

    def test_nonbinary_mask_fails(self):
        bad = self.work / 'bad-mask.png'
        Image.fromarray(np.full((16, 24), 128, dtype=np.uint8)).save(bad)
        code, result = self.invoke('check-frames.py', self.common + ['--protected-mask', str(bad)])
        self.assertEqual(code, 1); self.assertIn('0/255', result['errors'][0])

    def test_encoded_requires_explicit_tolerances(self):
        code, result = self.invoke('check-frames.py', self.common + ['--kind', 'encoded-video'])
        self.assertEqual(code, 1); self.assertIn('explicit', result['errors'][0])

    def test_encoded_without_endpoint_is_limited(self):
        path = self.frames / 'frame-0720.png'; original = path.read_bytes(); path.unlink()
        try:
            code, result = self.invoke('check-frames.py', self.common + ['--kind', 'encoded-video', '--no-endpoint', '--max-protected-delta', '1', '--max-loop-delta', '1'])
            self.assertEqual(code, 0, result)
            self.assertIsNone(result['after']['endpoint_max_rgb_delta'])
            self.assertTrue(any('endpoint' in s for s in result['not_run']))
        finally:
            path.write_bytes(original)

    def test_new_source_preflight(self):
        path = self.work / 'new.jpg'
        Image.new('RGB', (50, 40), 'blue').save(path)
        code, result = self.invoke('preflight.py', ['--repo', str(ROOT), '--artwork', 'new-landscape', '--image', str(path)])
        self.assertEqual(code, 0, result); self.assertEqual(result['image']['dimensions'], [50, 40])
        self.assertTrue(any('not yet integrated' in s for s in result['warnings']))

    def test_unknown_slug_without_image_fails(self):
        code, result = self.invoke('preflight.py', ['--repo', str(ROOT), '--artwork', 'unknown'])
        self.assertEqual(code, 1); self.assertIn('Unknown artwork', result['errors'][0])

    def test_integration_notices_and_changed_baseline(self):
        # Exercise static integration in a temporary copy, without requiring the
        # checkout to contain later artwork additions or notice-bundling changes.
        fixture = self.work / 'integration'; fixture.mkdir()
        for name in ['Artwork.swift', 'StarryNight.swift', 'Sky.metal',
                     'GalleryView.swift', 'build.sh', 'scripts/fetch-artworks.sh',
                     'scripts/verify-artworks.sh', 'THIRD-PARTY-NOTICES.md']:
            target = fixture / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        build = fixture / 'build.sh'
        without_notices = ''.join(line for line in build.read_text().splitlines(keepends=True)
                                  if 'THIRD-PARTY-NOTICES.md' not in line)
        build.write_text(without_notices)
        code, result = self.invoke('check-integration.py', ['--repo', str(fixture), '--baseline', str(ROOT)])
        self.assertEqual(code, 1, result)
        self.assertEqual(result['errors'], ['Build does not bundle third-party notices'])

        # This synthetic source fixture is never built or used as native evidence.
        build.write_text(without_notices + '\ncp THIRD-PARTY-NOTICES.md "$app/Contents/Resources/"\n')
        code, result = self.invoke('check-integration.py', ['--repo', str(fixture), '--baseline', str(ROOT)])
        self.assertEqual(code, 0, result)
        self.assertIn('Swift/Metal compilation', result['not_run'])
        baseline = self.work / 'baseline'; baseline.mkdir(exist_ok=True)
        source = (ROOT / 'Artwork.swift').read_text()
        reordered = source.replace('case starryNight, waterLilies', 'case waterLilies, starryNight', 1)
        self.assertNotEqual(source, reordered)
        (baseline / 'Artwork.swift').write_text(reordered)
        code, result = self.invoke('check-integration.py', ['--repo', str(fixture), '--baseline', str(baseline)])
        self.assertEqual(code, 1)
        self.assertEqual(result['errors'], ['Persisted artwork ID/slug prefix changed'])


if __name__ == '__main__':
    unittest.main(verbosity=2)

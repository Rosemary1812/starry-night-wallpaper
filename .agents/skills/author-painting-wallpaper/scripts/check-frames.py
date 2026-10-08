#!/usr/bin/env python3
"""Check a complete lossless frame sequence; never certifies visual quality."""
import argparse
import json
import math
from pathlib import Path
import sys
import numpy as np
from PIL import Image


def frame(path, shape=None):
    with Image.open(path) as image:
        if image.format != 'PNG' or image.mode not in ['RGB', 'RGBA']:
            raise ValueError(f'{path}: require RGB/RGBA PNG, not a GIF/JPEG/palette preview')
        pixels = np.array(image)
    if pixels.shape[2] == 4 and np.any(pixels[:, :, 3] != 255):
        raise ValueError(f'{path}: transparent frames are unsupported')
    pixels = pixels[:, :, :3]
    if shape is not None and pixels.shape != shape:
        raise ValueError(f'{path}: dimensions do not match neutral frame')
    return pixels


def mask(path, shape):
    with Image.open(path) as image:
        if image.format != 'PNG' or image.mode not in ['1', 'L']:
            raise ValueError(f'{path}: require a binary grayscale PNG mask')
        pixels = np.array(image.convert('L'))
    if pixels.shape != shape[:2] or not np.all((pixels == 0) | (pixels == 255)):
        raise ValueError(f'{path}: mask must match frame dimensions and contain only 0/255')
    selected = pixels == 255
    if not np.any(selected):
        raise ValueError(f'{path}: mask selects no pixels')
    return selected


def inner_boundary(selected):
    eroded = selected.copy()
    for _ in range(2):
        pad = np.pad(eroded, 1, constant_values=False)
        eroded = np.logical_and.reduce([pad[y:y + selected.shape[0], x:x + selected.shape[1]] for y in range(3) for x in range(3)])
    return selected & ~eroded


def measure(directory, neutral, protected, motion, args):
    count = round(args.duration * args.fps)
    expected = [f'frame-{i:04d}.png' for i in range(count + (not args.no_endpoint))]
    actual = {p.name for p in directory.glob('frame-*.png')}
    missing, extra = sorted(set(expected) - actual), sorted(actual - set(expected))
    if missing or extra:
        raise ValueError(f'{directory}: expected {len(expected)} sequential frames; missing {missing[:4]}, extra {extra[:4]}')
    first = frame(directory / expected[0], neutral.shape)
    minimum, maximum = first.copy(), first.copy()
    previous = first
    boundary = inner_boundary(protected)
    changed_protected = np.zeros(protected.shape, dtype=bool)
    protected_max = boundary_max = 0
    adjacent, adjacent_roi = [], []
    roi = motion if motion is not None else np.ones(protected.shape, dtype=bool)
    for i in range(count):
        current = first if i == 0 else frame(directory / expected[i], neutral.shape)
        delta = np.max(np.abs(current.astype(np.int16) - neutral.astype(np.int16)), axis=2)
        protected_max = max(protected_max, int(delta[protected].max()))
        boundary_max = max(boundary_max, int(delta[boundary].max()))
        changed_protected |= protected & (delta > args.max_protected_delta)
        if i:
            step_delta = np.max(np.abs(current.astype(np.int16) - previous.astype(np.int16)), axis=2)
            adjacent.append(float(step_delta.mean()))
            adjacent_roi.append(float(step_delta[roi].mean()))
        np.minimum(minimum, current, out=minimum)
        np.maximum(maximum, current, out=maximum)
        previous = current
    temporal = np.max(maximum.astype(np.int16) - minimum.astype(np.int16), axis=2)
    seam_delta = np.max(np.abs(previous.astype(np.int16) - first.astype(np.int16)), axis=2)
    seam = float(seam_delta.mean())
    roi_seam = float(seam_delta[roi].mean())
    roi_adjacent95 = float(np.percentile(adjacent_roi, 95))
    roi_ratio = roi_seam / roi_adjacent95 if roi_adjacent95 > 0 else (0.0 if roi_seam == 0 else None)
    adjacent95 = float(np.percentile(adjacent, 95))
    ratio = seam / adjacent95 if adjacent95 > 0 else (0.0 if seam == 0 else None)
    endpoint_delta = None
    if not args.no_endpoint:
        endpoint = frame(directory / expected[-1], neutral.shape)
        endpoint_delta = int(np.max(np.abs(endpoint.astype(np.int16) - first.astype(np.int16))))
    result = {
        'directory': str(directory.resolve()), 'playback_frames': count, 'endpoint_present': not args.no_endpoint,
        'resolution': [neutral.shape[1], neutral.shape[0]],
        'protected_pixels': int(protected.sum()), 'protected_changed_pixels': int(changed_protected.sum()),
        'protected_max_rgb_delta': protected_max, 'inner_boundary_pixels': int(boundary.sum()),
        'inner_boundary_max_rgb_delta': boundary_max, 'endpoint_max_rgb_delta': endpoint_delta,
        'seam_metric_scope': 'whole frame',
        'seam_mean_rgb_delta': seam, 'adjacent_p95_mean_rgb_delta': adjacent95,
        'motion_roi_seam_mean_rgb_delta': roi_seam if motion is not None else None,
        'motion_roi_seam_to_adjacent_p95_ratio': roi_ratio if motion is not None else None,
        'seam_to_adjacent_p95_ratio': ratio,
        'motion_roi_pixels': int(motion.sum()) if motion is not None else None,
        'motion_mean_temporal_range': float(temporal[motion].mean()) if motion is not None else None,
        'whole_frame_mean_temporal_range': float(temporal.mean()),
        'failures': [],
    }
    if protected_max > args.max_protected_delta:
        result['failures'].append('Protected pixels exceed the stated tolerance')
    if endpoint_delta is not None and endpoint_delta > args.max_loop_delta:
        result['failures'].append('Loop endpoint exceeds the stated tolerance')
    if ratio is None or ratio > args.max_seam_ratio:
        result['failures'].append('Wraparound change exceeds the seam/adjacent threshold')
    if motion is not None and (roi_ratio is None or roi_ratio > args.max_seam_ratio):
        result['failures'].append('Intended-motion ROI wraparound exceeds the seam/adjacent threshold')
    if motion is not None and result['motion_mean_temporal_range'] < args.min_motion_mean:
        result['failures'].append('Intended-motion ROI is below the stated temporal-range threshold')
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--frames', type=Path, required=True)
    p.add_argument('--neutral', type=Path, required=True)
    p.add_argument('--protected-mask', type=Path, required=True)
    p.add_argument('--motion-mask', type=Path)
    p.add_argument('--kind', choices=['cpu-reference', 'native-metal', 'encoded-video'], required=True)
    p.add_argument('--fps', type=float, default=30)
    p.add_argument('--duration', type=float, default=24)
    p.add_argument('--max-protected-delta', type=float)
    p.add_argument('--max-loop-delta', type=float)
    p.add_argument('--max-seam-ratio', type=float, default=2)
    p.add_argument('--min-motion-mean', type=float)
    p.add_argument('--no-endpoint', action='store_true', help='Encoded-video only; never fabricate a final endpoint')
    p.add_argument('--before', type=Path)
    p.add_argument('--report', type=Path)
    args = p.parse_args()
    errors, not_run = [], ['Artistic quality and normal-speed visual review', 'Active-side silhouette dragging/halos', 'Native execution identity (kind is supplied by the caller)']
    result = {'stage': 'frame metrics', 'kind': args.kind, 'errors': errors, 'not_run': not_run}
    try:
        if not all(math.isfinite(value) for value in [args.duration, args.fps, args.max_seam_ratio]):
            raise ValueError('Timing and thresholds must be finite')
        if min(args.duration, args.fps) <= 0 or args.duration * args.fps < 2 or not math.isclose(args.duration * args.fps, round(args.duration * args.fps), abs_tol=1e-7):
            raise ValueError('duration × fps must be an integer of at least two playback frames')
        if args.kind == 'encoded-video' and (args.max_protected_delta is None or args.max_loop_delta is None):
            raise ValueError('Encoded-video evidence requires explicit protection and loop tolerances')
        if args.no_endpoint and args.kind != 'encoded-video':
            raise ValueError('--no-endpoint is only for an encoded video; raw render evidence requires a true endpoint')
        args.max_protected_delta = 0 if args.max_protected_delta is None else args.max_protected_delta
        args.max_loop_delta = 0 if args.max_loop_delta is None else args.max_loop_delta
        if (args.motion_mask is None) != (args.min_motion_mean is None):
            raise ValueError('--motion-mask and --min-motion-mean must be provided together')
        thresholds = [args.max_protected_delta, args.max_loop_delta, args.max_seam_ratio] + ([] if args.min_motion_mean is None else [args.min_motion_mean])
        if any(not math.isfinite(v) or v < 0 for v in thresholds):
            raise ValueError('Thresholds must be finite and nonnegative')
        neutral = frame(args.neutral)
        protected = mask(args.protected_mask, neutral.shape)
        motion = mask(args.motion_mask, neutral.shape) if args.motion_mask else None
        if motion is not None and np.any(motion & protected):
            raise ValueError('Intended-motion and expected-protected masks overlap')
        result['settings'] = {key: getattr(args, key) for key in ['fps', 'duration', 'max_protected_delta', 'max_loop_delta', 'max_seam_ratio', 'min_motion_mean']}
        result['after'] = measure(args.frames, neutral, protected, motion, args)
        errors.extend(result['after']['failures'])
        if args.before:
            result['before'] = measure(args.before, neutral, protected, motion, args)
            keys = ['protected_max_rgb_delta', 'protected_changed_pixels', 'inner_boundary_max_rgb_delta', 'whole_frame_mean_temporal_range']
            if motion is not None:
                keys.append('motion_mean_temporal_range')
            result['after_minus_before'] = {k: result['after'][k] - result['before'][k] for k in keys}
        if motion is None:
            not_run.append('Intended-region motion gate (supply motion mask and justified threshold)')
        if args.no_endpoint:
            not_run.append('Exact 24-second endpoint; encoded stream has no additional endpoint')
        if args.kind == 'encoded-video':
            not_run.append('Shader-level exact protection and loop equality; decoded codec evidence only')
    except (OSError, ValueError) as exc:
        errors.append(str(exc))
    result['status'] = 'FAIL' if errors else 'PASS_WITH_LIMITS'
    output = json.dumps(result, indent=2, allow_nan=False)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output + '\n')
    print(output)
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())

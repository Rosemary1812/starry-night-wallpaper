"""Encode native Metal frames as GIFs without changing their playback speed."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CAPTURE = ROOT / 'dist/readme-media'
MEDIA = ROOT / 'docs/media'
metadata = json.loads((CAPTURE / 'capture.json').read_text())
count, fps = metadata['frames'], metadata['fps']
delays = [10 * (round((i + 1) * 100 / fps) - round(i * 100 / fps)) for i in range(count)]
labels = ['The Starry Night', 'Water Lilies', 'Stacks of Wheat', 'Starry Night over the Rhone',
          'Wheat Field with Cypresses', 'Impression, Sunrise', 'Waterloo Bridge',
          'Nocturne: Bognor', 'Approach to Venice', 'Cliff Walk at Pourville',
          'The Bridge at Villeneuve', 'Parliament, Sunset']
font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 10)
featured = {'starrynight': 'starry-night-preview.gif', 'water-lilies': 'water-lilies.gif',
            'wheat-stacks': 'wheat-stacks.gif', 'rhone': 'rhone.gif', 'cypresses': 'cypresses.gif'}


def frames(artwork):
    width, height = artwork['width'], artwork['height']
    frame_bytes = width * height * 4
    with (CAPTURE / (artwork['filename'] + '.bgra')).open('rb') as source:
        for _ in range(count):
            data = source.read(frame_bytes)
            if len(data) != frame_bytes:
                raise ValueError(f"Incomplete recording: {artwork['filename']}")
            yield Image.frombytes('RGBA', (width, height), data, 'raw', 'BGRA').convert('RGB')
        if source.read(1):
            raise ValueError('Unexpected trailing frame data')


def save_gif(images, path, colors=128):
    # Use one palette throughout the loop so still subjects do not flicker.
    palette = images[0].quantize(colors=colors)
    encoded = [image.quantize(palette=palette, dither=Image.Dither.NONE) for image in images]
    encoded[0].save(path, save_all=True, append_images=encoded[1:], duration=delays,
                    loop=0, optimize=True, disposal=1)
    with Image.open(path) as gif:
        duration = 0
        for frame in range(gif.n_frames):
            gif.seek(frame)
            duration += gif.info['duration']
        assert gif.info['loop'] == 0 and duration == 24000, (path, duration)
        gif.seek(0)
        first = gif.convert('RGB').copy()
        gif.seek(gif.n_frames // 3)
        assert gif.convert('RGB').tobytes() != first.tobytes(), f'Static GIF: {path}'
        print(f'{path.name}: {gif.n_frames} frames, {duration / 1000:g}s, {path.stat().st_size / 1024**2:.1f} MiB')


MEDIA.mkdir(parents=True, exist_ok=True)
# Four columns, three rows; the order matches the app's gallery.
tile_w, tile_h, gap, caption = 160, 100, 10, 24
sheet_size = (4 * tile_w + 5 * gap, 3 * (tile_h + caption) + 4 * gap)
sheets = [Image.new('RGB', sheet_size, '#f4f1eb') for _ in range(count)]
for index, artwork in enumerate(metadata['artworks']):
    images = list(frames(artwork))
    images[0].save(CAPTURE / (artwork['filename'] + '.png'))
    if artwork['filename'] in featured:
        save_gif(images, MEDIA / featured[artwork['filename']])
    x = gap + (index % 4) * (tile_w + gap)
    y = gap + (index // 4) * (tile_h + caption + gap)
    for sheet, image in zip(sheets, images):
        sheet.paste(image.resize((tile_w, tile_h), Image.Resampling.LANCZOS), (x, y))
        ImageDraw.Draw(sheet).text((x, y + tile_h + 7), labels[index], font=font, fill='#292724')
save_gif(sheets, MEDIA / 'painting-collection.gif', colors=64)
# Keep thumbnails and metadata for inspection; discard the large raw recordings.
for artwork in metadata['artworks']:
    (CAPTURE / (artwork['filename'] + '.bgra')).unlink()

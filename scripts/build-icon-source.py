"""Prepare the original-painting crop used before removing the sky stars."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance, ImageOps

root = Path(__file__).resolve().parents[1]
painting = Image.open(root / 'assets/starrynight.jpg')
# Keep the cypress, both sky swirls, hills and village at their original proportions.
# The square uses the full painting height and excludes the moon on the far right.
size = painting.height
scene = painting.crop((0, 0, size, size))
scene = ImageOps.autocontrast(ImageOps.grayscale(scene), cutoff=0.5)
scene = ImageEnhance.Contrast(scene).enhance(1.15)
scene = scene.resize((864, 864), Image.Resampling.LANCZOS).convert('RGBA')
mask = Image.new('L', (864, 864))
ImageDraw.Draw(mask).rounded_rectangle((0, 0, 863, 863), radius=190, fill=255)
scene.putalpha(mask)
icon = Image.new('RGBA', (1024, 1024))
icon.paste(scene, (80, 80), scene)
output = root / 'dist/AppIcon-original-crop.png'
output.parent.mkdir(parents=True, exist_ok=True)
icon.save(output)

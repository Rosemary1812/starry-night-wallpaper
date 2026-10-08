"""Make the app icon from the star-free central swirl in The Starry Night."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps

root = Path(__file__).resolve().parents[1]
painting = Image.open(root / 'assets/starrynight.jpg')
# Coordinates refer to the repository's 4096 × 3243 source painting.
swirl = painting.crop((1500, 620, 2700, 1820))
swirl = ImageOps.autocontrast(ImageOps.grayscale(swirl), cutoff=0.5)
swirl = swirl.resize((864, 864), Image.Resampling.LANCZOS).convert('RGBA')
mask = Image.new('L', (864, 864))
ImageDraw.Draw(mask).rounded_rectangle((0, 0, 863, 863), radius=190, fill=255)
swirl.putalpha(mask)
icon = Image.new('RGBA', (1024, 1024))
icon.paste(swirl, (80, 80), swirl)
icon.save(root / 'Icons/AppIcon.png')

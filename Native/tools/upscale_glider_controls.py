#!/usr/bin/env python3
"""Rebuild native static cockpit atlases from Orbiter's original DDS files.

Requires Pillow. Build and runtime use the checked-in DDS files, not Pillow.
"""
from pathlib import Path
from PIL import Image, ImageFilter

root = Path(__file__).resolve().parents[2]
source = root / 'Src/Vessel/DeltaGlider/Textures'
target = root / 'Native/GliderTextures'
target.mkdir(exist_ok=True)
for name in ('dgip_01.dds', 'dgip_03.dds', 'dgip_04.dds', 'dgip_05.dds'):
    image = Image.open(source / name).convert('RGBA')
    # Enlarging the existing artwork does not reconstruct missing details.
    image = image.resize((image.width * 2, image.height * 2), Image.Resampling.LANCZOS)
    image = image.filter(ImageFilter.UnsharpMask(radius=1, percent=85, threshold=3))
    image.save(target / name)

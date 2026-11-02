#!/usr/bin/env python3
"""Transfer generated surface detail to the original, UV-aligned DG atlases.

Requires Pillow and NumPy only when regenerating the checked-in DDS assets.
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

root = Path(__file__).resolve().parents[2]
textures = root / 'Native/GliderTextures'
sources = root / 'Native/tools/texture_sources'
for name, original in (
    ('dgmk4_1', root / 'Src/Vessel/DeltaGlider/Textures2/dgmk4_1.dds'),
    ('dgmk4_4', root / 'Src/Vessel/DeltaGlider/Textures/dgmk4_4.dds'),
):
    base = Image.open(original).convert('RGBA').resize((2048, 2048), Image.Resampling.LANCZOS)
    generated = Image.open(sources / (name + '_generated.png')).convert('L').resize(base.size, Image.Resampling.LANCZOS)
    # Isolate fine luminance variations only. The model shifted atlas islands,
    # so its panel edges and colors must never replace the original layout.
    detail = np.asarray(generated, dtype=np.float32) - np.asarray(generated.filter(ImageFilter.GaussianBlur(3)), dtype=np.float32)
    detail = np.clip(detail * .7, -10, 10)
    # Protect original lines, labels, seams, and other high-contrast features.
    edges = base.convert('L').filter(ImageFilter.FIND_EDGES).filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(3))
    mask = np.clip(1 - np.asarray(edges, dtype=np.float32) / 18, 0, 1)
    rgba = np.asarray(base, dtype=np.uint8).copy()
    rgb = rgba[:, :, :3].astype(np.float32) + (detail * mask)[:, :, None]
    rgba[:, :, :3] = np.clip(np.rint(rgb), 0, 255).astype(np.uint8)
    Image.fromarray(rgba).save(textures / (name + '_ai.dds'))

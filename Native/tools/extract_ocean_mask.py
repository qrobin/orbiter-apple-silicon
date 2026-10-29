#!/usr/bin/env python3
"""Create an ocean mask from the alpha channel of NASA SVS 4439's land layer.

Usage: python3 extract_ocean_mask.py flat_bluemarble_8192x4096.tif OUTPUT.png
Source: https://svs.gsfc.nasa.gov/4439/ (flat_bluemarble_8192x4096.tif).
"""
import sys
from PIL import Image, ImageOps

with Image.open(sys.argv[1]) as source:
    if source.mode != 'RGBA':
        raise ValueError('Expected the RGBA NASA land layer')
    water = ImageOps.invert(source.getchannel('A'))
    water.resize((4096, 2048), Image.Resampling.LANCZOS).save(sys.argv[2], optimize=True)

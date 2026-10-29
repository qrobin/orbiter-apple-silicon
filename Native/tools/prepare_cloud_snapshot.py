#!/usr/bin/env python3
"""Prepare an 8K cloud opacity map and matching 2K regional weather map.

Usage: python3 prepare_cloud_snapshot.py SOURCE.jpg OUTPUT.png OUTPUT.r8
SOURCE.jpg is a downloaded snapshot of the 8192x4096 cloud map from
https://github.com/matteason/live-cloud-maps. The game uses the saved snapshot,
not a network connection. The source requires EUMETSAT attribution.
"""
import sys
from PIL import Image

image = Image.open(sys.argv[1]).convert('L')
if image.size != (8192,4096):
    raise ValueError('Expected an 8192 x 4096 satellite cloud map')
image.save(sys.argv[2], optimize=True)
weather = image.resize((2048,1024),Image.Resampling.LANCZOS)
with open(sys.argv[3],'wb') as target:
    target.write(weather.tobytes())

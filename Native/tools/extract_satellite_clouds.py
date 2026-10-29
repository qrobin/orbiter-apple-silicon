#!/usr/bin/env python3
"""Extract the NASA SVS 3615 cloud overlay from its matching clouded/clear maps.

Usage: python3 extract_satellite_clouds.py CLOUDS.jpg CLEAR.jpg OUTPUT.png [OUTPUT.r8]
The inputs are flat_earth03.jpg and earth_noClouds.0330.jpg from
https://svs.gsfc.nasa.gov/3615/. The result is an 8-bit cloud opacity map.
"""
import sys
import numpy as np
from PIL import Image

cloud = np.asarray(Image.open(sys.argv[1]).convert('RGB'), dtype=np.float32) / 255
clear = np.asarray(Image.open(sys.argv[2]).convert('RGB'), dtype=np.float32) / 255
if cloud.shape != clear.shape:
    raise ValueError('The NASA maps must have the same dimensions')
alpha = np.max(np.maximum(0, (cloud-clear)/(1-clear+.08)), axis=2)
alpha = np.clip((alpha-.045)/.82, 0, 1)
pixels = np.uint8(alpha*255)
Image.fromarray(pixels).save(sys.argv[3])
if len(sys.argv) > 4:
    pixels.tofile(sys.argv[4])

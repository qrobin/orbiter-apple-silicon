#!/usr/bin/env python3
"""Generate a seamless spectral ocean slope/height tile for the Metal water shader.

Usage: python3 generate_ocean_spectrum.py OUTPUT.png
A fixed random seed and a directional, band-limited k^-4 spectrum make this
reproducible. R/G store the two surface slopes; B stores wave height.
"""
import sys
import numpy as np
from PIL import Image

size, length = 1024, 16000.0
rng = np.random.default_rng(2010)
k = 2 * np.pi * np.fft.fftfreq(size, d=length / size)
kx, ky = np.meshgrid(k, k)
wave_number = np.hypot(kx, ky)
safe = np.maximum(wave_number, 1e-9)
long_cutoff, short_cutoff = 2*np.pi/1500, 2*np.pi/45
# Wind direction is mostly east-west; opposing waves remain possible.
directional = .12 + .88 * (kx/safe)**4
power = np.exp(-(long_cutoff/safe)**2-(safe/short_cutoff)**2)*directional/safe**4
power[0, 0] = 0
spectrum = np.fft.fft2(rng.standard_normal((size,size))) * np.sqrt(power)
height = np.fft.ifft2(spectrum).real
dx = np.fft.ifft2(1j*kx*spectrum).real
dy = np.fft.ifft2(1j*ky*spectrum).real
# Each channel has room for rare large crests without clipping most waves.
slope_scale = max(dx.std(), dy.std())*6
channels = [np.clip(.5 + dx/slope_scale,0,1),
            np.clip(.5 + dy/slope_scale,0,1),
            np.clip(.5 + height/(height.std()*6),0,1)]
pixels = np.uint8(np.round(np.stack(channels,axis=-1)*255))
Image.fromarray(pixels).save(sys.argv[1],optimize=True)

#!/usr/bin/env python3
"""Generate two seamless, directional ocean wave spectra for Metal.

Usage: python3 generate_ocean_spectrum.py LONG.png SHORT.png
R/G store surface slopes and B stores wave height. The two bands and their
scaled variants travel at distinct speeds in the shader. A fixed seed makes
the generated assets reproducible.
"""
import sys
import numpy as np
from PIL import Image

size, length = 1024, 16000.0
rng = np.random.default_rng(2010)
k = 2*np.pi*np.fft.fftfreq(size,d=length/size)
kx,ky = np.meshgrid(k,k)
wave_number = np.hypot(kx,ky)
safe = np.maximum(wave_number,1e-9)
directional = .12+.88*(kx/safe)**4

for wavelength,path in [(800.0,sys.argv[1]),(180.0,sys.argv[2])]:
    peak = 2*np.pi/wavelength
    # Narrow, overlapping bands allow each scale to move at its own speed.
    band = np.exp(-.5*(np.log(safe/peak)/.58)**2)
    power = band*directional/safe**4
    power[0,0] = 0
    spectrum = np.fft.fft2(rng.standard_normal((size,size)))*np.sqrt(power)
    height = np.fft.ifft2(spectrum).real
    dx = np.fft.ifft2(1j*kx*spectrum).real
    dy = np.fft.ifft2(1j*ky*spectrum).real
    slope_scale = max(dx.std(),dy.std())*6
    channels = [np.clip(.5+dx/slope_scale,0,1),
                np.clip(.5+dy/slope_scale,0,1),
                np.clip(.5+height/(height.std()*6),0,1)]
    pixels = np.uint8(np.round(np.stack(channels,axis=-1)*255))
    Image.fromarray(pixels).save(path,optimize=True)

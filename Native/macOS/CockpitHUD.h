#pragma once
#import <Cocoa/Cocoa.h>
#include "Flight.h"
// Transparent luminance mask for the original Delta-glider virtual HUD surface.
NSBitmapImageRep *makeCockpitHud(const native::Flight &flight);

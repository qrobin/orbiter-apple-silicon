#pragma once
#import <Cocoa/Cocoa.h>
#include "TransX/Session.h"
// Draw original TransX Sketchpad commands into a Cocoa view or MFD texture.
void paintTransX(const native::transx::Frame &frame,NSRect rect);
NSString *transxString(const std::string &text);

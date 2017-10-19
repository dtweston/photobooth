//
//  NSImage+BLETint.m
//  Host
//
//  Created by Dave Weston on 4/22/15.
//  Copyright (c) 2015 Binocracy. All rights reserved.
//

#import "NSImage+BLETint.h"

@implementation NSImage (BLETint)

- (NSImage *)imageTintedWithColor:(NSColor *)color
{
    NSImage *image = [self copy];
    
    if (color) {
        [image lockFocus];
        [color set];
        NSRect rect = NSZeroRect;
        rect.size = image.size;
        NSRectFillUsingOperation(rect, NSCompositeSourceAtop);
        [image unlockFocus];
    }
    
    return image;
}

@end

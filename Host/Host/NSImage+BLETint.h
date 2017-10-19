//
//  NSImage+BLETint.h
//  Host
//
//  Created by Dave Weston on 4/22/15.
//  Copyright (c) 2015 Binocracy. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NSImage (BLETint)

- (NSImage *)imageTintedWithColor:(NSColor *)color;

@end

//
//  ImageView.m
//  Host
//
//  Created by Dave Weston on 4/23/15.
//  Copyright (c) 2015 Binocracy. All rights reserved.
//

#import "ImageView.h"

@implementation ImageView
{
    CGImageRef _image;
    CALayer *_imageLayer;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _imageLayer = [CALayer layer];
        _imageLayer.frame = CGRectMake(0, 0, frameRect.size.width, frameRect.size.height);
        _imageLayer.contentsScale = 2.0;
        [_imageLayer setBackgroundColor:[[NSColor blueColor] CGColor]];
        [self setLayer:_imageLayer];
        [self setWantsLayer:YES];
    }
    
    return self;
}

- (void)setImage:(CGImageRef)image
{
    if (image != _image) {
        if (_image) {
            CFRelease(_image);
        }
        CFRetain(image);
        _image = image;
        
        [_imageLayer setContents:(__bridge id)(_image)];
    }
}

- (CGImageRef)image
{
    return _image;
}

@end

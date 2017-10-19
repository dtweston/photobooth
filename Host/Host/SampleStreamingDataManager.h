/**
 * @file  SampleStreamingDataManager.h
 * @brief CameraRemoteSampleApp
 *
 * Copyright 2014 Sony Corporation
 */

#import <Foundation/Foundation.h>

@protocol SampleStreamingDataDelegate <NSObject>

- (void)didFetchCgImage:(CGImageRef)cgImage;

- (void)didFetchImage:(NSImage *)image;

- (void)didStreamingStopped;

- (void)drawTakenPicture:(NSImage *)image;

@end

@interface SampleStreamingDataManager : NSObject <NSStreamDelegate>

- (void)start:(NSString *)url
    viewDelegate:(id<SampleStreamingDataDelegate>)viewDelegate;

- (void)stop;

- (BOOL)isStarted;

@end

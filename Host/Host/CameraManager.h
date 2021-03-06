//
//  CameraManager.h
//  Host
//
//  Created by Dave Weston on 4/22/15.
//  Copyright (c) 2015 Binocracy. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SampleStreamingDataDelegate;

@interface CameraManager : NSObject

- (instancetype)initWithBaseDirectory:(NSString *)baseDirectory streamingDelegate:(id<SampleStreamingDataDelegate>)delegate;
- (void)prepareOpenConnection;
- (void)start;
- (void)takePicture;

@end

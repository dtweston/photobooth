/**
 * @file  SampleDeviceDiscovery.h
 * @brief CameraRemoteSampleApp
 *
 * Copyright 2014 Sony Corporation
 */

#import <Foundation/Foundation.h>

@protocol SampleViewDelegate;

@protocol SampleDiscoveryDelegate <NSObject>

- (void)didReceiveDdUrl:(NSString *)ddUrl;

@end

@interface SampleDeviceDiscovery
    : NSObject <SampleDiscoveryDelegate, NSXMLParserDelegate>

- (void)discover:(id<SampleViewDelegate>)delegate;

@end

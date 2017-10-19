//
//  HostManager.h
//  Host
//
//  Created by Dave Weston on 4/21/15.
//  Copyright (c) 2015 Binocracy. All rights reserved.
//

#import <Foundation/Foundation.h>

@class HostManager;

@protocol HostManagerDelegate<NSObject>

- (void)hostManagerDidConnect:(HostManager *)hostManager;
- (void)hostManagerDidDisconnect:(HostManager *)hostManager;
- (void)hostManagerDidReceiveInvitation:(HostManager *)hostManager;
- (void)hostManager:(HostManager *)hostManager didReceiveCommand:(NSString *)command;

@end

@interface HostManager : NSObject

@property (nonatomic, weak) id<HostManagerDelegate> delegate;

- (void)start;

@end

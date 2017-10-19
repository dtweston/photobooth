//
//  ClientManager.h
//  Client
//
//  Created by Dave Weston on 4/22/15.
//  Copyright (c) 2015 Binocracy. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ClientManager;

@protocol ClientManagerDelegate <NSObject>

- (void)clientManagerStartConnecting:(ClientManager *)clientManager;
- (void)clientManagerDidConnect:(ClientManager *)clientManager;
- (void)clientManagerDidDisconnect:(ClientManager *)clientManager;

@end

@interface ClientManager : NSObject

@property (nonatomic, weak) id<ClientManagerDelegate> delegate;
- (void)start;
- (void)sendCommand:(NSString *)command;

@end

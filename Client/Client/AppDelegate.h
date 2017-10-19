//
//  AppDelegate.h
//  Client
//
//  Created by Dave Weston on 4/21/15.
//  Copyright (c) 2015 Binocracy. All rights reserved.
//

#import <UIKit/UIKit.h>

@class ClientManager;

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;
@property (nonatomic, strong) ClientManager *clientManager;


@end


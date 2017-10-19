//
//  ClientManager.m
//  Client
//
//  Created by Dave Weston on 4/22/15.
//  Copyright (c) 2015 Binocracy. All rights reserved.
//

#import "ClientManager.h"
#import <MultipeerConnectivity/MultipeerConnectivity.h>

@interface ClientManager ()<MCSessionDelegate, MCNearbyServiceBrowserDelegate>

@property (nonatomic, strong) MCSession *session;
@property (nonatomic, strong) MCPeerID *peer;
@property (nonatomic, strong) MCPeerID *host;
@property (nonatomic, strong) MCNearbyServiceBrowser *browser;

@end

@implementation ClientManager

- (instancetype)init
{
    self = [super init];
    if (self) {
        _peer = [[MCPeerID alloc] initWithDisplayName:@"Client"];
        _session = [[MCSession alloc] initWithPeer:_peer];
        _session.delegate = self;
        _browser = [[MCNearbyServiceBrowser alloc] initWithPeer:_peer serviceType:@"dweston-remote"];
        _browser.delegate = self;
    }
    
    return self;
}

- (void)start
{
    NSLog(@"Starting to browse");
    [self.browser startBrowsingForPeers];
}

- (void)sendCommand:(NSString *)command
{
    if (!self.host) {
        NSLog(@"Unable to send command: No host!");
        return;
    }
    
    NSData *data = [command dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    if (![self.session sendData:data toPeers:@[self.host] withMode:MCSessionSendDataReliable error:&error]) {
        NSLog(@"Unable to send command (%@) to host: %@", command, error);
    }
}

#pragma mark - MCNearbyServiceBrowserDelegate methods

- (void)browser:(MCNearbyServiceBrowser *)browser didNotStartBrowsingForPeers:(NSError *)error
{
    NSLog(@"Unable to start browsing: %@", error);
}

- (void)browser:(MCNearbyServiceBrowser *)browser foundPeer:(MCPeerID *)peerID withDiscoveryInfo:(NSDictionary *)info
{
    NSLog(@"Found peer: %@", peerID.displayName);
    self.host = peerID;
    [browser invitePeer:peerID toSession:self.session withContext:nil timeout:20];
    [self.delegate clientManagerStartConnecting:self];
}

- (void)browser:(MCNearbyServiceBrowser *)browser lostPeer:(MCPeerID *)peerID
{
    self.host = nil;
    NSLog(@"Lost peer: %@", peerID);
}

#pragma mark - MCSessionDelegate methods

- (void)session:(MCSession *)session peer:(MCPeerID *)peerID didChangeState:(MCSessionState)state
{
    if (state == MCSessionStateConnected) {
        NSLog(@"Connected with peer: %@ (%@)", peerID, session);
        [self.delegate clientManagerDidConnect:self];
    }
    else if (state == MCSessionStateConnecting) {
        NSLog(@"Connecting with peer: %@... (%@)", peerID, session);
    }
    else if (state == MCSessionStateNotConnected) {
        [self.delegate clientManagerDidDisconnect:self];
    }
    else {
        NSLog(@"State is %ld", (long)state);
    }
}

- (void)session:(MCSession *)session didReceiveData:(NSData *)data fromPeer:(MCPeerID *)peerID
{
}

- (void)session:(MCSession *)session didStartReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID withProgress:(NSProgress *)progress
{
    
}

- (void)session:(MCSession *)session didFinishReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID atURL:(NSURL *)localURL withError:(NSError *)error
{
    
}

- (void)session:(MCSession *)session didReceiveStream:(NSInputStream *)stream withName:(NSString *)streamName fromPeer:(MCPeerID *)peerID
{
    
}

- (void)session:(MCSession *)session didReceiveCertificate:(NSArray *)certificate fromPeer:(MCPeerID *)peerID certificateHandler:(void (^)(BOOL))certificateHandler
{
    if (certificateHandler) {
        certificateHandler(YES);
    }
}

@end

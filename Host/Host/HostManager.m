//
//  HostManager.m
//  Host
//
//  Created by Dave Weston on 4/21/15.
//  Copyright (c) 2015 Binocracy. All rights reserved.
//

#import "HostManager.h"
#import <MultipeerConnectivity/MultipeerConnectivity.h>

@interface HostManager ()<MCSessionDelegate,MCNearbyServiceAdvertiserDelegate>

@property (nonatomic, strong) MCSession *session;
@property (nonatomic, strong) MCPeerID *peer;
@property (nonatomic, strong) MCNearbyServiceAdvertiser *advertiser;

@end

@implementation HostManager

- (instancetype)init
{
    self = [super init];
    if (self) {
        _peer = [[MCPeerID alloc] initWithDisplayName:@"Host"];
        _session = [[MCSession alloc] initWithPeer:_peer];
        _session.delegate = self;
        _advertiser = [[MCNearbyServiceAdvertiser alloc] initWithPeer:_peer discoveryInfo:@{@"blah": @"103"} serviceType:@"dweston-remote"];
        _advertiser.delegate = self;
    }
    
    return self;
}

- (void)start
{
    NSLog(@"Starting to advertise");
    [self.advertiser startAdvertisingPeer];
}

#pragma mark - MCNearbyServiceAdvertiserDelegate methods

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didNotStartAdvertisingPeer:(NSError *)error
{
    NSLog(@"Unable to start advertising: %@", error);
}

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didReceiveInvitationFromPeer:(MCPeerID *)peerID withContext:(NSData *)context invitationHandler:(void (^)(BOOL, MCSession *))invitationHandler
{
    NSLog(@"Received invitation from peer: %@", peerID);
    NSLog(@"Accepting invitation...");
    [self.delegate hostManagerDidReceiveInvitation:self];
    invitationHandler(YES, self.session);
}

#pragma mark - MCSessionDelegate methods

- (void)session:(MCSession *)session peer:(MCPeerID *)peerID didChangeState:(MCSessionState)state
{
    if (state == MCSessionStateConnected) {
        [self.delegate hostManagerDidConnect:self];
        NSLog(@"Connected with peer: %@ (%@)", peerID, session);
    }
    else if (state == MCSessionStateConnecting) {
        NSLog(@"Connecting with peer: %@... (%@)", peerID, session);
    }
    else if (state == MCSessionStateNotConnected) {
        [self.delegate hostManagerDidDisconnect:self];
    }
}

- (void)session:(MCSession *)session didReceiveData:(NSData *)data fromPeer:(MCPeerID *)peerID
{
    NSString *command = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [self.delegate hostManager:self didReceiveCommand:command];
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

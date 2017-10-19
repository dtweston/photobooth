//
//  AppDelegate.m
//  Host
//
//  Created by Dave Weston on 4/21/15.
//  Copyright (c) 2015 Binocracy. All rights reserved.
//

#import "AppDelegate.h"

#import "HostManager.h"
#import "CameraManager.h"
#import "SampleDeviceDiscovery.h"
#import "SampleViewDelegate.h"
#import "SampleStreamingDataManager.h"
#import "DeviceList.h"
#import "NSImage+BLETint.h"
#import "ImageView.h"

@interface AppDelegate ()<SampleViewDelegate, SampleStreamingDataDelegate,HostManagerDelegate,NSWindowDelegate>

@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSView *view;
@property (weak) IBOutlet NSImageView *takePictureImageView;
@property (weak) IBOutlet NSImageView *liveViewImageView;
@property (strong) IBOutlet ImageView *liveImageView;

@property (weak) IBOutlet NSImageView *bluetoothImageView;

@property (nonatomic, strong) NSImage *btOff;
@property (nonatomic, strong) NSImage *btOn;
@property (nonatomic, strong) NSTimer *connectTimer;

@property (nonatomic, strong) NSTrackingArea *trackingArea;

@property (strong) HostManager *hostManager;
@property (strong) CameraManager *cameraManager;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    
    self.window.delegate = self;
    
    [DeviceList reset];
    SampleDeviceDiscovery *deviceDiscovery = [[SampleDeviceDiscovery alloc] init];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [deviceDiscovery discover:self];
    });
    
    [self.window setBackgroundColor:[NSColor blackColor]];
    [self.window setCollectionBehavior:NSWindowCollectionBehaviorDefault|NSWindowCollectionBehaviorFullScreenPrimary];
    
    self.liveImageView = [[ImageView alloc] initWithFrame:self.view.bounds];
    [self.liveImageView setAutoresizingMask:NSViewHeightSizable|NSViewWidthSizable];
    [self.view addSubview:self.liveImageView positioned:NSWindowAbove relativeTo:self.liveViewImageView];
    
    [self.bluetoothImageView setImage:self.btOff];
    [self.takePictureImageView setHidden:YES];
    
    self.hostManager = [[HostManager alloc] init];
    self.hostManager.delegate = self;
    [self.hostManager start];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (NSImage *)btOff
{
    if (_btOff) {
        return _btOff;
    }
    
    _btOff = [[NSImage imageNamed:@"bluetooth"] imageTintedWithColor:[NSColor redColor]];
    return _btOff;
}

- (NSImage *)btOn
{
    if (_btOn) {
        return _btOn;
    }
    
    _btOn = [[NSImage imageNamed:@"bluetooth"] imageTintedWithColor:[NSColor colorWithRed:0.4 green:0.8 blue:0.4 alpha:1.0]];
    return _btOn;
}

- (NSString *)baseDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *directoryPath = [paths[0] stringByAppendingPathComponent:@"photobooth"];
    
    return directoryPath;
}

- (void)didReceiveDeviceList:(BOOL)isReceived
{
    if ([DeviceList getSize] > 0) {
        [DeviceList selectDeviceAt:0];
        self.cameraManager = [[CameraManager alloc] initWithBaseDirectory:[self baseDirectory] streamingDelegate:self];
        [self.cameraManager prepareOpenConnection];
    }
    else {
        NSLog(@"Unable to find devices!");
    }
}

- (void)drawTakenPicture:(NSImage *)image
{
    NSInteger width = 0;
    NSInteger height = 0;
    for (NSImageRep *imageRep in image.representations) {
        if ([imageRep pixelsWide] > width)
            width = [imageRep pixelsWide];
        if ([imageRep pixelsHigh] > height)
            height = [imageRep pixelsHigh];
    }
    NSImage *finalImage = [[NSImage alloc] initWithSize:NSMakeSize(MIN(width, _takePictureImageView.frame.size.width), MIN(height, _takePictureImageView.frame.size.height))];
    [finalImage addRepresentations:image.representations];
    

    NSLog(@"SampleCameraRemoteViewController drawTakenPicture");
    [_takePictureImageView setImage:finalImage];
    [_takePictureImageView setHidden:NO];
    dispatch_after(
                   dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       [_takePictureImageView setHidden:YES];
                   });
}

- (void)didFetchCgImage:(CGImageRef)cgImage
{
    [_liveImageView setImage:cgImage];
}

/**
 * SampleStreamingDataDelegate implementation
 */
- (void)didFetchImage:(NSImage *)image
{
    [_liveViewImageView setImage:image];
}

- (void)didStreamingStopped
{
    [self.cameraManager start];
}

#pragma mark - HostManagerDelegate methods

- (void)hostManagerDidDisconnect:(HostManager *)hostManager
{
    self.bluetoothImageView.image = self.btOff;
}

- (void)hostManagerDidReceiveInvitation:(HostManager *)hostManager
{
    self.connectTimer = [NSTimer scheduledTimerWithTimeInterval:0.3 target:self selector:@selector(connectingBlink:) userInfo:nil repeats:YES];
}

- (void)connectingBlink:(NSTimer *)timer
{
    [self.bluetoothImageView setHidden:![self.bluetoothImageView isHidden]];
}

- (void)hostManagerDidConnect:(HostManager *)hostManager
{
    [self.connectTimer invalidate];
    self.connectTimer = nil;
    [self.bluetoothImageView setHidden:NO];
    self.bluetoothImageView.image = self.btOn;
}

- (void)hostManager:(HostManager *)hostManager didReceiveCommand:(NSString *)command
{
    NSLog(@"!!! Got command: %@", command);
    [self.cameraManager takePicture];
}

#pragma mark - NSWindowDelegate methods

- (IBAction)takePicture:(id)sender {
    [self.cameraManager takePicture];
}

- (void)mouseEntered:(NSEvent *)event
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideCursor) object:nil];
    [self performSelector:@selector(hideCursor) withObject:nil afterDelay:5];
}

- (void)mouseExited:(NSEvent *)event
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideCursor) object:nil];
}

- (void)mouseMoved:(NSEvent *)event
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideCursor) object:nil];
    [self performSelector:@selector(hideCursor) withObject:nil afterDelay:5];
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
    [self performSelector:@selector(hideCursor) withObject:nil afterDelay:5];
    self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.view.frame options:NSTrackingMouseMoved|NSTrackingActiveWhenFirstResponder owner:self userInfo:nil];
    [self.view addTrackingArea:self.trackingArea];
}

- (void)windowWillExitFullScreen:(NSNotification *)notification
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideCursor) object:nil];
    [NSCursor setHiddenUntilMouseMoves:NO];
    [self.view removeTrackingArea:self.trackingArea];
}

- (void)hideCursor
{
    [NSCursor setHiddenUntilMouseMoves:YES];
}

@end

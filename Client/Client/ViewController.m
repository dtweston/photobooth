//
//  ViewController.m
//  Client
//
//  Created by Dave Weston on 4/21/15.
//  Copyright (c) 2015 Binocracy. All rights reserved.
//

#import "ViewController.h"
#import "ClientManager.h"


@interface ViewController ()<ClientManagerDelegate>

@property (weak, nonatomic) IBOutlet UIButton *bluetoothButton;
@property (nonatomic, strong) UIImage *btOff;
@property (nonatomic, strong) UIImage *btOn;
@property (nonatomic, strong) NSTimer *connectTimer;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.clientManager.delegate = self;

    [self.bluetoothButton setBackgroundImage:self.btOff forState:UIControlStateNormal];
}

- (IBAction)takePicture:(id)sender
{
    [self.clientManager sendCommand:@"snap"];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (UIImage *)tintImage:(UIImage *)image withColor:(UIColor *)color
{
    // It's important to pass in 0.0f to this function to draw the image to the scale of the screen
    UIGraphicsBeginImageContextWithOptions(image.size, NO, 0.0f);
    [color setFill];
    CGRect bounds = CGRectMake(0, 0, image.size.width, image.size.height);
    UIRectFill(bounds);
    [image drawInRect:bounds blendMode:kCGBlendModeDestinationIn alpha:1.0];
    
    UIImage *tintedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return tintedImage;
}

- (UIImage *)btOff
{
    if (_btOff) {
        return _btOff;
    }
    
    _btOff = [self tintImage:[UIImage imageNamed:@"bluetooth"] withColor:[UIColor redColor]];
    return _btOff;
}

- (UIImage *)btOn
{
    if (_btOn) {
        return _btOn;
    }
    
    _btOn = [self tintImage:[UIImage imageNamed:@"bluetooth"] withColor:[UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:1.0]];
    return _btOn;
}

#pragma mark - ClientManagerDelegate methods

- (void)clientManagerStartConnecting:(ClientManager *)clientManager
{
    self.connectTimer = [NSTimer scheduledTimerWithTimeInterval:0.3 target:self selector:@selector(connectingBlink:) userInfo:nil repeats:YES];
}

- (void)connectingBlink:(NSTimer *)timer
{
    [self.bluetoothButton setHidden:![self.bluetoothButton isHidden]];
}

- (void)clientManagerDidConnect:(ClientManager *)clientManager
{
    [self.connectTimer invalidate];
    self.connectTimer = nil;
    [self.bluetoothButton setHidden:NO];
    [self.bluetoothButton setBackgroundImage:self.btOn forState:UIControlStateNormal];
}

- (void)clientManagerDidDisconnect:(ClientManager *)clientManager
{
    [self.bluetoothButton setBackgroundImage:self.btOff forState:UIControlStateNormal];
}

@end

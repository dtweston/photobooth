//
//  CameraManager.m
//  Host
//
//  Created by Dave Weston on 4/22/15.
//  Copyright (c) 2015 Binocracy. All rights reserved.
//

#import "CameraManager.h"

#import <AppKit/AppKit.h>
#import "DeviceList.h"
#import "SampleCameraApi.h"
#import "SampleAvContentApi.h"
#import "SampleStreamingDataManager.h"
#import "SampleCameraEventObserver.h"

static NSString const *NextIndexKey = @"NextIndex";

@interface CameraManager ()<HttpAsynchronousRequestParserDelegate,SampleEventObserverDelegate>

@property (nonatomic, strong) NSArray *availableCameraApiList;
@property (nonatomic, assign) BOOL isSupportedVersion;
@property (nonatomic, assign) BOOL isPreparingOpenConnection;
@property (nonatomic, assign) BOOL currentLiveviewStatus;
@property (nonatomic, assign) BOOL isMediaAvailable;
@property (nonatomic, assign) BOOL isMovieAvailable;
@property (nonatomic, assign) BOOL isContentAvailable;
@property (nonatomic, assign) BOOL isNextZoomAvailable;
@property (nonatomic, strong) NSMutableArray *modeArray;
@property (nonatomic, strong) NSString *currentShootMode;
@property (nonatomic, strong) SampleStreamingDataManager *streamingDataManager;
@property (nonatomic, weak) id<SampleStreamingDataDelegate> delegate;
@property (nonatomic, strong) SampleCameraEventObserver *eventObserver;
@property (nonatomic, strong) NSString *baseDirectory;
@property (nonatomic, assign) NSInteger nextIndex;

@end

@implementation CameraManager

- (instancetype)initWithBaseDirectory:(NSString *)baseDirectory streamingDelegate:(id<SampleStreamingDataDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _eventObserver = [SampleCameraEventObserver getInstance];
        _baseDirectory = baseDirectory;
        _streamingDataManager = [[SampleStreamingDataManager alloc] init];
    }
    
    return self;
}

- (NSString *)infoFilePath
{
    return [self.baseDirectory stringByAppendingPathComponent:@"info.plist"];
}

- (void)setNextIndex:(NSInteger)nextIndex
{
    if (_nextIndex != nextIndex) {
        _nextIndex = nextIndex;
        [@{NextIndexKey: @(nextIndex)} writeToFile:[self infoFilePath] atomically:YES];
    }
}

- (void)start
{
    NSError *error = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    BOOL isDir;
    BOOL exists = [fm fileExistsAtPath:self.baseDirectory isDirectory:&isDir];
    if (exists && !isDir) {
        BOOL didRemove = [fm removeItemAtPath:self.baseDirectory error:&error];
        if (!didRemove) {
            NSLog(@"Unable to create destination path: %@", error);
            return;
        }
        exists = NO;
    }
    
    if (!exists) {
        BOOL didCreate = [fm createDirectoryAtPath:self.baseDirectory withIntermediateDirectories:YES attributes:nil error:&error];
        if (!didCreate) {
            NSLog(@"Unable to create destination path: %@", error);
            return;
        }
    }
    
    NSString *infoFilePath = [self infoFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:infoFilePath]) {
        NSDictionary *infoDictionary = [NSDictionary dictionaryWithContentsOfFile:[self infoFilePath]];
        _nextIndex = [infoDictionary[NextIndexKey] integerValue];
    }
    else {
        self.nextIndex = 1;
    }
    
    [SampleCameraApi startLiveview:self];
}

- (void)takePicture
{
    [SampleCameraApi actTakePicture:self];
}

/**
 * Preparing to open connection.
 */
- (void)prepareOpenConnection
{
    // First, call get method types.
    [SampleCameraApi getMethodTypes:self];
}

/*
 * Initialize client to setup liveview, camera controls and start listening to
 * camera events.
 */
- (void)openConnection
{
    NSLog(@"SampleCameraRemoteViewController initialize");
    _isSupportedVersion = NO;
    
    // check available API list
    NSData *availableApiList =
    [SampleCameraApi getAvailableApiList:self isSync:YES];
    if (availableApiList != nil) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self parseMessage:availableApiList
                       apiName:API_CAMERA_getAvailableApiList];
        });
    } else {
        NSLog(@"SampleCameraRemoteViewController initialize : "
              @"getAvailableApiList error");
        dispatch_async(dispatch_get_main_queue(),
                       ^{ [self openNetworkErrorDialog]; });
        return;
    }
    
    // check if the version of the server is supported or not
    if ([self isCameraApiAvailable:API_CAMERA_getApplicationInfo]) {
        NSData *response = [SampleCameraApi getApplicationInfo:self isSync:YES];
        if (response != nil) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self parseMessage:response
                           apiName:API_CAMERA_getApplicationInfo];
            });
            if (!_isSupportedVersion) {
                // popup not supported version
                NSLog(@"SampleCameraRemoteViewController initialize is not "
                      @"supported version");
                dispatch_async(dispatch_get_main_queue(),
                               ^{ [self openUnsupportedErrorDialog]; });
                return;
            } else {
                NSLog(@"SampleCameraRemoteViewController initialize is "
                      @"supported version");
            }
        } else {
            NSLog(@"SampleCameraRemoteViewController initialize error");
            dispatch_async(dispatch_get_main_queue(),
                           ^{ [self openNetworkErrorDialog]; });
            return;
        }
    }
    
    // startRecMode if necessary
    if ([self isCameraApiAvailable:API_CAMERA_startRecMode]) {
        NSData *response = [SampleCameraApi startRecMode:self isSync:YES];
        if (response != nil) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self parseMessage:response apiName:API_CAMERA_startRecMode];
            });
        } else {
            NSLog(@"SampleCameraRemoteViewController initialize error");
            dispatch_async(dispatch_get_main_queue(),
                           ^{ [self openNetworkErrorDialog]; });
            return;
        }
    }
    
    // update available API list
    availableApiList = [SampleCameraApi getAvailableApiList:self isSync:YES];
    if (availableApiList != nil) {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self parseMessage:availableApiList
                       apiName:API_CAMERA_getAvailableApiList];
        });
    } else {
        NSLog(@"SampleCameraRemoteViewController initialize error");
        dispatch_async(dispatch_get_main_queue(),
                       ^{ [self openNetworkErrorDialog]; });
        return;
    }
    
    // check available shoot mode to update mode button
    if ([self isCameraApiAvailable:API_CAMERA_getAvailableShootMode]) {
        dispatch_sync(dispatch_get_main_queue(),
                      ^{ [SampleCameraApi getAvailableShootMode:self]; });
    }
    
    // check method types of avContent service to update availability of movie
    if ([[DeviceList getSelectedDevice] findActionListUrl:@"avContent"] !=
        NULL) {
        dispatch_sync(dispatch_get_main_queue(),
                      ^{ [SampleAvContentApi getMethodTypes:self]; });
    }
}

/*
 * Closing the webAPI connection from the client.
 */
- (void)closeConnection
{
    NSLog(@"SampleCameraRemoteViewController closeConnection");
    
    [_eventObserver stop];
    [_streamingDataManager stop];
    if ([self isCameraApiAvailable:API_CAMERA_stopRecMode]) {
        [SampleCameraApi stopRecMode:self];
    }
}

/*
 * Function to check if apiName is available at any moment.
 */
- (BOOL)isCameraApiAvailable:(NSString *)apiName
{
    return [_availableCameraApiList containsObject:apiName];
}

/**
 * SampleEventObserverDelegate function implementation
 */

- (void)didAvailableApiListChanged:(NSMutableArray *)API_CAMERA_list
{
    NSLog(@"SampleCameraRemoteViewController didApiListChanged:%@",
          [API_CAMERA_list componentsJoinedByString:@","]);
    _availableCameraApiList = API_CAMERA_list;
    
    // start liveview if available
    if ([self isCameraApiAvailable:API_CAMERA_startLiveview]) {
        if (![_streamingDataManager isStarted] && _isSupportedVersion) {
            [self start];
        }
    }
    
    // getEvent start if available
    if ([self isCameraApiAvailable:API_CAMERA_getEvent] &&
        _isSupportedVersion) {
        [_eventObserver startWithDelegate:self];
    }
    
    if ([self isCameraApiAvailable:API_CAMERA_actZoom] && _isSupportedVersion) {
//        [zoomInButton setHidden:NO];
//        [zoomOutButton setHidden:NO];
    } else {
//        [zoomInButton setHidden:YES];
//        [zoomOutButton setHidden:YES];
    }
}

- (void)didCameraStatusChanged:(NSString *)status
{
    NSLog(@"SampleCameraRemoteViewController didCameraStatusChanged:%@",
          status);
    
    if (_isPreparingOpenConnection) {
        if ([PARAM_CAMERA_cameraStatus_idle isEqualToString:status] ||
            [PARAM_CAMERA_cameraStatus_stillCapturing isEqualToString:status] ||
            [PARAM_CAMERA_cameraStatus_stillSaving isEqualToString:status] ||
            [PARAM_CAMERA_cameraStatus_movieWaitRecStart
             isEqualToString:status] ||
            [PARAM_CAMERA_cameraStatus_movieRecording isEqualToString:status] ||
            [PARAM_CAMERA_cameraStatus_movieWaitRecStop
             isEqualToString:status] ||
            [PARAM_CAMERA_cameraStatus_movieSaving isEqualToString:status] ||
            [PARAM_CAMERA_cameraStatus_intervalWaitRecStart
             isEqualToString:status] ||
            [PARAM_CAMERA_cameraStatus_intervalRecording
             isEqualToString:status] ||
            [PARAM_CAMERA_cameraStatus_intervalWaitRecStop
             isEqualToString:status] ||
            [PARAM_CAMERA_cameraStatus_audioWaitRecStart
             isEqualToString:status] ||
            [PARAM_CAMERA_cameraStatus_audioRecording isEqualToString:status] ||
            [PARAM_CAMERA_cameraStatus_audioWaitRecStop
             isEqualToString:status] ||
            [PARAM_CAMERA_cameraStatus_audioSaving isEqualToString:status]) {
            _isPreparingOpenConnection = NO;
            [self performSelectorInBackground:@selector(openConnection)
                                   withObject:NULL];
        } else {
            [SampleCameraApi
             setCameraFunction:self
             function:PARAM_CAMERA_cameraFunction_remoteShooting];
        }
    }
    
    // CameraStatus TextView
//    self.cameraStatusView.text = status;
    
    // if status is streaming
    if ([PARAM_CAMERA_cameraStatus_streaming isEqualToString:status]) {
        [SampleAvContentApi stopStreaming:self];
    }
    
    // Recording Start/Stop Button
    if ([PARAM_CAMERA_cameraStatus_movieRecording isEqualToString:status]) {
//        [actionButtonText setHidden:NO];
//        [actionButtonText setEnabled:YES];
//        [actionButtonText setBackgroundColor:[UIColor whiteColor]];
//        [actionButtonText
//         setTitle:NSLocalizedString(@"STR_RECORD_STOP", @"STR_RECORD_STOP")
//         forState:UIControlStateNormal];
//        actionButtonText.tag = 2;
    }
    
    if ([PARAM_CAMERA_cameraStatus_idle isEqualToString:status] &&
        [@"movie" isEqualToString:_currentShootMode]) {
//        [actionButtonText setHidden:NO];
//        [actionButtonText setEnabled:YES];
//        [actionButtonText setBackgroundColor:[UIColor whiteColor]];
//        [actionButtonText
//         setTitle:NSLocalizedString(@"STR_RECORD_START", @"STR_RECORD_START")
//         forState:UIControlStateNormal];
//        actionButtonText.tag = 1;
    }
    
    if ([PARAM_CAMERA_cameraStatus_idle isEqualToString:status] &&
        [@"still" isEqualToString:_currentShootMode]) {
//        [actionButtonText setHidden:NO];
//        [actionButtonText setEnabled:YES];
//        [actionButtonText setBackgroundColor:[UIColor whiteColor]];
//        [actionButtonText
//         setTitle:NSLocalizedString(@"STR_TAKE_PICTURE", @"STR_TAKE_PICTURE")
//         forState:UIControlStateNormal];
//        actionButtonText.tag = 3;
    }
    
    if ([PARAM_CAMERA_cameraStatus_stillCapturing isEqualToString:status] &&
        [@"still" isEqualToString:_currentShootMode]) {
//        [actionButtonText setEnabled:NO];
//        [actionButtonText setBackgroundColor:[UIColor grayColor]];
    }
    
    if ([PARAM_CAMERA_cameraStatus_notReady isEqualToString:status]) {
//        [actionButtonText setEnabled:NO];
//        [actionButtonText setBackgroundColor:[UIColor grayColor]];
    }
}

- (void)didLiveviewStatusChanged:(BOOL)status
{
    NSLog(@"SampleCameraRemoteViewController didLiveviewStatusChanged:%d",
          status);
    _currentLiveviewStatus = status;
}

- (void)didShootModeChanged:(NSString *)shootMode
{
    NSLog(@"SampleCameraRemoteViewController didShootModeChanged:%@",
          shootMode);
    if ([shootMode isEqualToString:@"movie"] ||
        [shootMode isEqualToString:@"still"]) {
        _currentShootMode = shootMode;
    } else {
        _currentShootMode = @"";
    }
    if (_modeArray.count > 0) {
        [self setInitialShootModeUI];
    }
}

- (void)didZoomPositionChanged:(int)zoomPosition
{
    NSLog(@"SampleCameraRemoteViewController didZoomPositionChanged:%d",
          zoomPosition);
    _isNextZoomAvailable = YES;
    
    if (zoomPosition == 0) {
//        [zoomInButton setEnabled:YES];
//        [zoomOutButton setEnabled:NO];
        
    } else if (zoomPosition == 100) {
//        [zoomInButton setEnabled:NO];
//        [zoomOutButton setEnabled:YES];
        
    } else {
//        [zoomInButton setEnabled:YES];
//        [zoomOutButton setEnabled:YES];
    }
}

- (void)didStorageInformationChanged:(NSString *)storageId
{
    NSLog(@"SampleCameraRemoteViewController didStorageInformationChanged %@",
          storageId);
    if ([storageId isEqualToString:PARAM_CAMERA_storageId_noMedia]) {
        _isMediaAvailable = NO;
//        [self.navigationItem.rightBarButtonItem setEnabled:NO];
    } else {
        _isMediaAvailable = YES;
        if (_isContentAvailable) {
//            [self.navigationItem.rightBarButtonItem setEnabled:YES];
        }
    }
}

- (void)didFailParseMessageWithError:(NSError *)error
{
    NSLog(@"SampleCameraRemoteViewController didFailParseMessageWithError "
          @"error parsing JSON string");
    [self openNetworkErrorDialog];
}

/**
 * Parses response of WebAPI requests.
 */

/*
 * Parser of actTakePicture response
 */
- (void)parseActTakePicture:(NSArray *)resultArray
                  errorCode:(NSInteger)errorCode
               errorMessage:(NSString *)errorMessage
{
    if (resultArray.count > 0 && errorCode < 0) {
        NSArray *pictureList = resultArray[0];
        [self didTakePicture:pictureList[0]];
    } else {
        [self openCannotControlErrorDialog];
    }
}

/*
 * Get the taken picture and show
 */
- (void)didTakePicture:(NSString *)url
{
    NSLog(@"SampleCameraRemoteViewController didTakePicture:%@", url);
    NSURL *downloadUrl = [NSURL URLWithString:url];
    NSURLSessionConfiguration *config =
    [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    NSURLSessionDataTask *task =
    [session dataTaskWithURL:downloadUrl
           completionHandler:^(NSData *data, NSURLResponse *response,
                               NSError *error) {
//               [self progressIndicator:NO];
               if (data != nil) {
                   
                   NSString *filePath = [self.baseDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"Photo %03ld.jpg", self.nextIndex]];

                   dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                       self.nextIndex += 1;
                       [data writeToFile:filePath atomically:YES];
                   });
                   
                   NSImage *downloadedImage = [[NSImage alloc] initWithData:data];
                   
                   dispatch_sync(dispatch_get_main_queue(), ^{
                       [self.delegate drawTakenPicture:downloadedImage];
                   });
               } else {
                   NSLog(@"SampleContentViewController data object could "
                         @"not be created " @"from download URL = %@",
                         url);
                   [self openNetworkErrorDialog];
               }
               [session invalidateAndCancel];
           }];
    [task resume];
}

/*
 * Parser of getAvailableApiList response
 */
- (void)parseGetAvailableApiList:(NSArray *)resultArray
                       errorCode:(NSInteger)errorCode
                    errorMessage:(NSString *)errorMessage
{
    if (resultArray.count > 0 && errorCode < 0) {
        NSArray *availableApiList = resultArray[0];
        if (availableApiList != nil) {
            [self didAvailableApiListChanged:availableApiList];
        }
    }
    // For developer : if errorCode>=0, handle the error according to
    // requirement.
}

/*
 * Parser of getApplicationInfo response
 */
- (void)parseGetApplicationInfo:(NSArray *)resultArray
                      errorCode:(NSInteger)errorCode
                   errorMessage:(NSString *)errorMessage
{
    if (resultArray.count > 0 && errorCode < 0) {
        NSString *serverName = resultArray[0];
        NSString *serverVersion = resultArray[1];
        NSLog(@"SampleCameraRemoteViewController parseGetApplicationInfo "
              @"serverName = %@",
              serverName);
        NSLog(@"SampleCameraRemoteViewController parseGetApplicationInfo "
              @"serverVersion = %@",
              serverVersion);
        if (serverVersion != nil) {
            _isSupportedVersion = [self isSupportedServerVersion:serverVersion];
        }
    }
    // For developer : if errorCode>=0, handle the error according to
    // requirement.
}

- (BOOL)isSupportedServerVersion:(NSString *)version
{
    NSArray *versionModeList = [version componentsSeparatedByString:@"."];
    if (versionModeList.count > 0) {
        long major = [versionModeList[0] integerValue];
        if (2 <= major) {
            NSLog(@"SampleCameraRemoteViewController isSupportedServerVersion "
                  @"YES");
            return YES;
        } else {
            NSLog(@"SampleCameraRemoteViewController isSupportedServerVersion "
                  @"NO");
        }
    }
    return NO;
}

/*
 * Parser of getAvailableShootMode response
 */
- (void)parseGetAvailableShootMode:(NSArray *)resultArray
                         errorCode:(NSInteger)errorCode
                      errorMessage:(NSString *)errorMessage
{
    if (resultArray.count > 0 && errorCode < 0) {
        if ([resultArray[0] isEqualToString:@"movie"] ||
            [resultArray[0] isEqualToString:@"still"]) {
            _currentShootMode = resultArray[0];
        } else {
            _currentShootMode = @"";
        }
        
        _modeArray = [[NSMutableArray alloc] init];
        NSArray *shootModeList = resultArray[1];
        
        for (int i = 0; i < shootModeList.count; i++) {
            NSLog(@"SampleCameraRemoteViewController "
                  @"parseGetAvailableShootMode shootMode = %@",
                  shootModeList[i]);
            
            NSString *shootMode = shootModeList[i];
            if ([shootMode isEqualToString:@"movie"] ||
                [shootMode isEqualToString:@"still"]) {
                [_modeArray addObject:shootMode];
            } else {
                [_modeArray addObject:@""];
            }
        }
        // set initial shoot mode
        [self setInitialShootModeUI];
    }
    // For developer : if errorCode>=0, handle the error according to
    // requirement.
//    [self progressIndicator:NO];
}

// set initial shoot mode
- (void)setInitialShootModeUI
{
//    [actionButtonText setHidden:NO];
//    [actionButtonText setEnabled:YES];
//    [actionButtonText setBackgroundColor:[UIColor whiteColor]];
//    
//    [modeButtonText setHidden:NO];
//    [modeButtonText setEnabled:YES];
//    [modeButtonText setBackgroundColor:[UIColor whiteColor]];
//    [modeButtonText
//     setTitle:[NSString stringWithFormat:@"Mode:%@", _currentShootMode]
//     forState:UIControlStateNormal];
    
    if ([@"movie" isEqualToString:_currentShootMode]) {
//        if (![NSLocalizedString(@"STR_RECORD_STOP", @"STR_RECORD_STOP")
//              isEqualToString:[actionButtonText currentTitle]]) {
//            [actionButtonText setTitle:NSLocalizedString(@"STR_RECORD_START",
//                                                         @"STR_RECORD_START")
//                              forState:UIControlStateNormal];
//            actionButtonText.tag = 1;
//        }
    } else if ([@"still" isEqualToString:_currentShootMode]) {
//        [actionButtonText
//         setTitle:NSLocalizedString(@"STR_TAKE_PICTURE", @"STR_TAKE_PICTURE")
//         forState:UIControlStateNormal];
//        actionButtonText.tag = 3;
    } else {
//        [actionButtonText setTitle:@"" forState:UIControlStateNormal];
//        [actionButtonText setEnabled:NO];
//        [actionButtonText setBackgroundColor:[UIColor grayColor]];
//        actionButtonText.tag = -1;
    }
//    [modeButtonText
//     setTitle:[NSString stringWithFormat:@"Mode:%@", _currentShootMode]
//     forState:UIControlStateNormal];
}

/*
 * Parser of startLiveview response
 */
- (void)parseStartLiveView:(NSArray *)resultArray
                 errorCode:(NSInteger)errorCode
              errorMessage:(NSString *)errorMessage
{
    if (resultArray.count > 0 && errorCode < 0) {
        NSString *liveviewUrl = resultArray[0];
        NSLog(@"SampleCameraRemoteViewController parseStartLiveView liveview = "
              @"%@",
              liveviewUrl);
        [_streamingDataManager start:liveviewUrl viewDelegate:self.delegate];
    }
}

/*
 * Parser of Camera getmethodTypes response
 */
- (void)parseCameraGetMethodTypes:(NSArray *)resultArray
                        errorCode:(NSInteger)errorCode
                     errorMessage:(NSString *)errorMessage
{
    NSLog(@"SampleCameraRemoteViewController parseCameraGetMethodTypes");
    if (resultArray.count > 0 && errorCode < 0) {
        BOOL isSetCameraFunctionSupported = NO;
        BOOL isGetEventSupported = NO;
        
        // check setCameraFunction and getEvent
        for (int i = 0; i < resultArray.count; i++) {
            NSArray *result = resultArray[i];
            if ([(NSString *)result[0]
                 isEqualToString:API_CAMERA_setCameraFunction] &&
                [(NSString *)result[3] isEqualToString:@"1.0"]) {
                isSetCameraFunctionSupported = YES;
            }
            if ([(NSString *)result[0] isEqualToString:API_CAMERA_getEvent] &&
                [(NSString *)result[3] isEqualToString:@"1.0"]) {
                isGetEventSupported = YES;
            }
        }
        
        if (isSetCameraFunctionSupported) {
            if (!isGetEventSupported) {
                NSLog(@"SampleCameraRemoteViewController "
                      @"parseCameraGetMethodTypes getEvent is not available.");
                return;
            }
            [_eventObserver startWithDelegate:self];
        } else {
            _isPreparingOpenConnection = NO;
            [self performSelectorInBackground:@selector(openConnection)
                                   withObject:NULL];
        }
    }
}

/*
 * Parser of AvContent getmethodTypes response
 */
- (void)parseAvContentGetMethodTypes:(NSArray *)resultArray
                           errorCode:(NSInteger)errorCode
                        errorMessage:(NSString *)errorMessage
{
    NSLog(@"SampleCameraRemoteViewController parseAvContentGetMethodTypes");
    BOOL isContentValid = NO;
    if (resultArray.count > 0 && errorCode < 0) {
        // check getSchemeList
        for (int i = 0; i < resultArray.count; i++) {
            NSArray *result = resultArray[i];
            if ([(NSString *)result[0]
                 isEqualToString:API_AVCONTENT_getSchemeList] &&
                [(NSString *)result[3] isEqualToString:@"1.0"]) {
                isContentValid = YES;
            }
        }
        // check getSourceList
        if (isContentValid) {
            isContentValid = NO;
            for (int i = 0; i < resultArray.count; i++) {
                NSArray *result = resultArray[i];
                if ([(NSString *)result[0]
                     isEqualToString:API_AVCONTENT_getSourceList] &&
                    [(NSString *)result[3] isEqualToString:@"1.0"]) {
                    isContentValid = YES;
                }
            }
        }
        // check getContentList
        if (isContentValid) {
            isContentValid = NO;
            for (int i = 0; i < resultArray.count; i++) {
                NSArray *result = resultArray[i];
                if ([(NSString *)result[0]
                     isEqualToString:API_AVCONTENT_getContentList] &&
                    [(NSString *)result[3] isEqualToString:@"1.3"]) {
                    isContentValid = YES;
                }
            }
        }
        if (isContentValid) {
            // Content is available
            _isContentAvailable = YES;
            if (_isMediaAvailable) {
//                [self.navigationItem.rightBarButtonItem setEnabled:YES];
            }
            isContentValid = NO;
            
            // check for video : setStreamingContent
            
            for (int i = 0; i < resultArray.count; i++) {
                NSArray *result = resultArray[i];
                if ([(NSString *)result[0]
                     isEqualToString:API_AVCONTENT_setStreamingContent] &&
                    [(NSString *)result[3] isEqualToString:@"1.0"]) {
                    isContentValid = YES;
                }
            }
            // check startStreaming
            if (isContentValid) {
                isContentValid = NO;
                for (int i = 0; i < resultArray.count; i++) {
                    NSArray *result = resultArray[i];
                    if ([(NSString *)result[0]
                         isEqualToString:API_AVCONTENT_startStreaming] &&
                        [(NSString *)result[3] isEqualToString:@"1.0"]) {
                        isContentValid = YES;
                    }
                }
            }
            // check stopStreaming
            if (isContentValid) {
                isContentValid = NO;
                for (int i = 0; i < resultArray.count; i++) {
                    NSArray *result = resultArray[i];
                    if ([(NSString *)result[0]
                         isEqualToString:API_AVCONTENT_stopStreaming] &&
                        [(NSString *)result[3] isEqualToString:@"1.0"]) {
                        isContentValid = YES;
                    }
                }
            }
            if (isContentValid) {
                // video is available
                _isMovieAvailable = YES;
            }
        }
    }
}

/*
 * Delegate parser implementation for WebAPI requests
 */
- (void)parseMessage:(NSData *)response apiName:(NSString *)apiName
{
    NSString *responseText =
    [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding];
    NSLog(@"SampleCameraRemoteViewController parseMessage = %@ apiName = %@",
          responseText, apiName);
    
    NSError *e;
    NSDictionary *dict =
    [NSJSONSerialization JSONObjectWithData:response
                                    options:NSJSONReadingMutableContainers
                                      error:&e];
    if (e) {
        NSLog(@"SampleCameraRemoteViewController parseMessage error parsing "
              @"JSON string");
        [self openNetworkErrorDialog];
        return;
    }
    
    NSArray *resultArray = [[NSArray alloc] init];
    if ([dict[@"result"] isKindOfClass:[NSArray class]]) {
        resultArray = dict[@"result"];
    }
    
    NSArray *resultsArray = [[NSArray alloc] init];
    if ([dict[@"results"] isKindOfClass:[NSArray class]]) {
        resultsArray = dict[@"results"];
    }
    
    NSArray *errorArray = nil;
    NSString *errorMessage = @"";
    NSInteger errorCode = -1;
    if ([dict[@"error"] isKindOfClass:[NSArray class]]) {
        errorArray = dict[@"error"];
    }
    if (errorArray != nil && errorArray.count >= 2) {
        errorCode = [(NSNumber *)errorArray[0] intValue];
        errorMessage = errorArray[1];
        NSLog(@"SampleCameraRemoteViewController parseMessage API=%@, "
              @"errorCode=%ld, errorMessage=%@",
              apiName, (long)errorCode, errorMessage);
        
        // This error is created in HttpAsynchronousRequest
        if (errorCode == 16) {
            [self openNetworkErrorDialog];
            return;
        }
    }
    
    if ([apiName isEqualToString:API_CAMERA_getAvailableApiList]) {
        [self parseGetAvailableApiList:resultArray
                             errorCode:errorCode
                          errorMessage:errorMessage];
    } else if ([apiName isEqualToString:API_CAMERA_getApplicationInfo]) {
        [self parseGetApplicationInfo:resultArray
                            errorCode:errorCode
                         errorMessage:errorMessage];
    } else if ([apiName isEqualToString:API_CAMERA_getShootMode]) {
        
    } else if ([apiName isEqualToString:API_CAMERA_setShootMode]) {
        
    } else if ([apiName isEqualToString:API_CAMERA_getAvailableShootMode]) {
        [self parseGetAvailableShootMode:resultArray
                               errorCode:errorCode
                            errorMessage:errorMessage];
    } else if ([apiName isEqualToString:API_CAMERA_getSupportedShootMode]) {
        
    } else if ([apiName isEqualToString:API_CAMERA_startLiveview]) {
        [self parseStartLiveView:resultArray
                       errorCode:errorCode
                    errorMessage:errorMessage];
    } else if ([apiName isEqualToString:API_CAMERA_stopLiveview]) {
        
    } else if ([apiName isEqualToString:API_CAMERA_startRecMode]) {
        
    } else if ([apiName isEqualToString:API_CAMERA_stopRecMode]) {
        
    } else if ([apiName isEqualToString:API_CAMERA_actTakePicture]) {
        [self parseActTakePicture:resultArray
                        errorCode:errorCode
                     errorMessage:errorMessage];
    } else if ([apiName isEqualToString:API_CAMERA_startMovieRec]) {
        
    } else if ([apiName isEqualToString:API_CAMERA_stopMovieRec]) {
        
    } else if ([apiName isEqualToString:API_CAMERA_getMethodTypes]) {
        [self parseCameraGetMethodTypes:resultsArray
                              errorCode:errorCode
                           errorMessage:errorMessage];
    } else if ([apiName isEqualToString:API_CAMERA_actZoom]) {
        
    } else if ([apiName isEqualToString:API_AVCONTENT_getMethodTypes]) {
        [self parseAvContentGetMethodTypes:resultsArray
                                 errorCode:errorCode
                              errorMessage:errorMessage];
    }
}

- (void)openNetworkErrorDialog
{
    NSLog(@"Error: %@", NSLocalizedString(@"NETWORK_ERROR_MESSAGE",
                                          @"NETWORK_ERROR_MESSAGE"));
//    UIAlertView *alert = [[UIAlertView alloc]
//                          initWithTitle:NSLocalizedString(@"NETWORK_ERROR_HEADING",
//                                                          @"NETWORK_ERROR_HEADING")
//                          message:NSLocalizedString(@"NETWORK_ERROR_MESSAGE",
//                                                    @"NETWORK_ERROR_MESSAGE")
//                          delegate:nil
//                          cancelButtonTitle:@"OK"
//                          otherButtonTitles:nil];
//    [alert show];
//    [self progressIndicator:NO];
}

- (void)openUnsupportedErrorDialog
{
    NSLog(@"Error: %@", NSLocalizedString(@"UNSUPPORTED_MESSAGE",
                                          @"UNSUPPORTED_MESSAGE"));
//    UIAlertView *alert = [[UIAlertView alloc]
//                          initWithTitle:NSLocalizedString(@"UNSUPPORTED_HEADING",
//                                                          @"UNSUPPORTED_HEADING")
//                          message:NSLocalizedString(@"UNSUPPORTED_MESSAGE",
//                                                    @"UNSUPPORTED_MESSAGE")
//                          delegate:nil
//                          cancelButtonTitle:@"OK"
//                          otherButtonTitles:nil];
//    [alert show];
//    [self progressIndicator:NO];
}

- (void)openUnsupportedShootModeErrorDialog
{
    NSLog(@"Error: %@", NSLocalizedString(@"UNSUPPORTED_SHOOT_MODE_MESSAGE",
                                          @"UNSUPPORTED_SHOOT_MODE_MESSAGE"));
//    UIAlertView *alert = [[UIAlertView alloc]
//                          initWithTitle:NSLocalizedString(@"UNSUPPORTED_HEADING",
//                                                          @"UNSUPPORTED_HEADING")
//                          message:NSLocalizedString(@"UNSUPPORTED_SHOOT_MODE_MESSAGE",
//                                                    @"UNSUPPORTED_SHOOT_MODE_MESSAGE")
//                          delegate:nil
//                          cancelButtonTitle:@"OK"
//                          otherButtonTitles:nil];
//    [alert show];
}

- (void)openCannotControlErrorDialog
{
    NSLog(@"Error: %@", NSLocalizedString(@"CANNOT_CONTROL_MESSAGE",
                                          @"CANNOT_CONTROL_MESSAGE"));
//    UIAlertView *alert = [[UIAlertView alloc]
//                          initWithTitle:NSLocalizedString(@"UNSUPPORTED_HEADING",
//                                                          @"UNSUPPORTED_HEADING")
//                          message:NSLocalizedString(@"CANNOT_CONTROL_MESSAGE",
//                                                    @"CANNOT_CONTROL_MESSAGE")
//                          delegate:nil
//                          cancelButtonTitle:@"OK"
//                          otherButtonTitles:nil];
//    [alert show];
//    [self progressIndicator:NO];
}

@end

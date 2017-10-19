/**
 * @file  SampleStreamingDataManager.m
 * @brief CameraRemoteSampleApp
 *
 * Copyright 2014 Sony Corporation
 */
#import "SampleStreamingDataManager.h"

#import <AppKit/AppKit.h>

@implementation SampleStreamingDataManager {
    BOOL _isStarted;
    NSMutableData *_receiveData;
    NSURLConnection *_connection;
    id<SampleStreamingDataDelegate> _viewDelegate;
    dispatch_semaphore_t _dataSemaphore;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _dataSemaphore = dispatch_semaphore_create(1);
    }
    
    return self;
}

- (void)dealloc
{
    _dataSemaphore = nil;
}

- (void)start:(NSString *)url
    viewDelegate:(id<SampleStreamingDataDelegate>)viewDelegate
{
    if (!_isStarted) {
        @synchronized(self)
        {
            _isStarted = YES;
            _receiveData = [[NSMutableData alloc] init];
        }
        _viewDelegate = viewDelegate;
        [self readStream:[NSURL URLWithString:url]];
    }
}

- (void)readStream:(NSURL *)url
{
    NSLog(@"SampleStreamingDataManager : readStream : url = %@", url);
    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:url
                                cachePolicy:NSURLRequestReloadIgnoringCacheData
                            timeoutInterval:60.0];
    [request setHTTPMethod:@"GET"];

    _connection = [[NSURLConnection alloc] initWithRequest:request
                                                  delegate:self
                                          startImmediately:NO];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        [_connection start];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate distantFuture]];
    });
}

- (void)connection:(NSURLConnection *)connection
    didReceiveResponse:(NSURLResponse *)response
{
    @synchronized(self)
    {
        [_receiveData setLength:0];
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
                   ^{ [self getPackets]; });
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    @synchronized(self)
    {
        [_receiveData appendData:data];
        dispatch_semaphore_signal(_dataSemaphore);
    }
}

- (void)connection:(NSURLConnection *)connection
    didFailWithError:(NSError *)error
{
    NSLog(@"SampleStreamingDataManager didFailWithError %@", error);
    [self stop];
    [_viewDelegate didStreamingStopped];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
}

/*
 * Start getting JPEG packets
 */
- (void)getPackets
{
    while (_isStarted) {
        @autoreleasepool
        {
            [self getJPEGPacket];
        }
    }
}

typedef struct {
    uint8_t startByte;
    uint8_t payloadType;
    uint16_t sequenceNumber;
    uint32_t timeStamp;
} __attribute((packed)) LivewViewPacketHeader;

typedef struct {
    uint8_t startCode[4];
    uint32_t dataSize : 24;
    uint8_t paddingSize;
} __attribute((packed)) LiveViewPayloadHeader;

typedef struct {
    uint8_t reserved[4];
    uint8_t flag;
    uint8_t reserved2[115];
} __attribute((packed)) LivewViewJpegPayloadHeader;

typedef struct {
    uint8_t dataVersion[2];
    uint16_t frameCount;
    uint16_t frameDataSize;
    uint8_t reserved[114];
} __attribute((packed)) LiveViewFramePayloadHeader;

/*
 * Get a single JPEG packet
 */
- (void)getJPEGPacket
{
    LivewViewPacketHeader packetHeader;
    [self readBytes:sizeof(LivewViewPacketHeader) buffer:&packetHeader];

    // read for JPEG image
    [self getPayload:((packetHeader.payloadType & 0x01) == 0x01)];
}

/*
 * Get payload data of JPEG image
 */
- (void)getPayload:(BOOL)isImage
{
    NSInteger jpegDataSize = 0;
    NSInteger jpegPaddingSize = 0;

    // check for first 4 bytes
    [self detectPayloadHeader];

    // get JPEG data size
    uint8_t jData[3];
    [self readBytes:3 buffer:jData];
    jpegDataSize = [self bytesToInt:jData count:3];

    // get JPEG padding size
    uint8_t jPad[1];
    [self readBytes:1 buffer:jPad];
    jpegPaddingSize = [self bytesToInt:jPad count:1];

    // remove 120 bytes from stream
    uint8_t b1[120];
    [self readBytes:120 buffer:b1];

    // read JPEG image
    uint8_t jpegData[jpegDataSize];
    [self readBytes:jpegDataSize buffer:jpegData];

    if (isImage) {
        NSData *imageData =
            [[NSData alloc] initWithBytes:jpegData length:jpegDataSize];

        CGDataProviderRef dataProvider = CGDataProviderCreateWithCFData((CFDataRef)imageData);
        CGImageRef image = CGImageCreateWithJPEGDataProvider(dataProvider, NULL, true, kCGRenderingIntentDefault);
        CGDataProviderRelease(dataProvider);
        
        if (image) {
            dispatch_async(dispatch_get_main_queue(),
                           ^{
                               [_viewDelegate didFetchCgImage:image];
                               CFRelease(image);
                           });
        }
        else {
            NSLog(@"Unable to parse image");
        }
    }

    // remove JPEG padding data
    uint8_t padData[jpegPaddingSize];
    [self readBytes:jpegPaddingSize buffer:padData];
}

/*
 * Detect payload header
 */
- (void)detectPayloadHeader
{
    while (true && _isStarted) {
        BOOL isValid = YES;
        @synchronized(self)
        {
            if (_receiveData != NULL && _receiveData.length < 4) {
                isValid = NO;
            }
        }
        if (isValid) {
            break;
        } else {
            // Wait to receive more data into _receiveData
            sleep(0.01);
        }
    }
    uint8_t checkByte[4];
    checkByte[0] = 0x24;
    checkByte[1] = 0x35;
    checkByte[2] = 0x68;
    checkByte[3] = 0x79;

    NSData *checkData = [NSData dataWithBytes:checkByte length:4];
    BOOL isFound = NO;

    NSRange found = NSMakeRange(0, 4);

    @synchronized(self)
    {
        if (_isStarted) {
            found = [_receiveData rangeOfData:checkData
                                      options:NSDataSearchAnchored
                                        range:found];
        }
    }

    if (found.location != NSNotFound && _isStarted) {
        @synchronized(self)
        {
            // remove extra bytes from the beginning
            [_receiveData replaceBytesInRange:NSMakeRange(0, 4)
                                    withBytes:NULL
                                       length:0];
        }
        return;
    }

    // In case the data is corrupted and first 4 bytes are not checkBytes, this
    // loop will find the checkBytes.
    // NOTE : not used in general cases
    while (!isFound && _isStarted) {
        long maxRangeLength = 0;
        @synchronized(self)
        {
            maxRangeLength = _receiveData.length;
        }
        NSRange currentRange = NSMakeRange(0, maxRangeLength);

        @synchronized(self)
        {
            found = [_receiveData rangeOfData:checkData
                                      options:NSDataSearchBackwards
                                        range:currentRange];
        }
        if (found.location != NSNotFound) {
            NSRange lastFound = found;

            isFound = YES; // found latest checkBytes
            @synchronized(self)
            {
                // remove extra bytes from the beginning
                [_receiveData
                    replaceBytesInRange:NSMakeRange(0, lastFound.location + 4)
                              withBytes:NULL
                                 length:0];
            }
        } else {
            // Wait to receive more data into _receiveData
            sleep(0.1);
        }
    }
    return;
}

/*
 * Read bytes from _receiveData
 */
- (void)readBytes:(NSInteger)length buffer:(void *)buffer
{
    // remove specified length from _receiveData
    while (true && _isStarted) {
        BOOL isValid = NO;
        @synchronized(self)
        {
            if (_receiveData != NULL && _receiveData.length > length) {
                isValid = YES;
            }
        }
        if (isValid) {
            break;
        } else {
            // Wait to receive more data into _receiveData
            dispatch_semaphore_wait(_dataSemaphore, dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC));
        }
    }

    // ASSERT : length is sufficient
    @synchronized(self)
    {
        if (_receiveData != NULL && _isStarted) {
            [_receiveData getBytes:buffer length:length];
            [_receiveData replaceBytesInRange:NSMakeRange(0, length)
                                    withBytes:NULL
                                       length:0];
        }
    }
}

- (NSInteger)bytesToInt:(uint8_t *)bytes count:(NSInteger)count
{
    NSInteger val = 0;
    for (int i = 0; i < count; i++) {
        val = (val << 8) | (bytes[i] & 0xff);
    }
    return val;
}

- (void)stop
{
    NSLog(@"SampleStreamingDataManager stop");
    @synchronized(self)
    {
        _isStarted = NO;
        _receiveData = nil;
    }
    _viewDelegate = nil;

    [_connection cancel];
}

- (BOOL)isStarted
{
    return _isStarted;
}

@end

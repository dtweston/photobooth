/**
 * @file  UdpRequest.m
 * @brief CameraRemoteSampleApp
 *
 * Copyright 2014 Sony Corporation
 */

#import "UdpRequest.h"

static id<SampleDiscoveryDelegate> _discoveryDelegate;
static NSMutableArray *_deviceUuidList;

@implementation UdpRequest {
    CFSocketRef _cfSocketSend;
    CFSocketRef _cfSocketListen;
    NSThread *_timeoutThread;
    bool _didReceiveSsdp;
}

int _SSDP_RECEIVE_TIMEOUT = 10; // seconds
int _SSDP_PORT = 1900;
int _SSDP_MX = 1;
NSString *_SSDP_ADDR = @"239.255.255.250";
NSString *_SSDP_ST = @"urn:schemas-sony-com:service:ScalarWebAPI:1";

- (void)search:(id<SampleDiscoveryDelegate>)delegate
{
    _deviceUuidList = [[NSMutableArray alloc] init];
    _discoveryDelegate = delegate;
    _didReceiveSsdp = false;
    _timeoutThread = [[NSThread alloc] initWithTarget:self
                                             selector:@selector(timeoutThread)
                                               object:nil];
    [_timeoutThread start];

    [self listen];
}

- (void)timeoutThread
{
    int i = 0;
    while (i < _SSDP_RECEIVE_TIMEOUT && ![_timeoutThread isCancelled]) {
        sleep(1);
        i++;
    }
    if (CFSocketIsValid(_cfSocketSend)) {
        _cfSocketSend = NULL;
    }
    if (CFSocketIsValid(_cfSocketListen)) {
        _cfSocketListen = NULL;
    }
    if (!_didReceiveSsdp) {
        [_discoveryDelegate didReceiveDdUrl:NULL];
    }
}

- (void)listen
{
    _cfSocketSend = [self initSocket:_cfSocketSend];
    if (!_cfSocketSend) {
        return;
    }

    // Send from socket
    NSString *_message =
        [NSString stringWithFormat:@"M-SEARCH * "
                                   @"HTTP/"
                                   @"1.1\r\nHOST:%@:%d\r\nMAN:\"ssdp:"
                                   @"discover\"\r\nMX:%d\r\nST:%@\r\n\r\n",
                                   _SSDP_ADDR, _SSDP_PORT, _SSDP_MX, _SSDP_ST];
    CFDataRef data = CFDataCreate(
        NULL, (const UInt8 *)[_message UTF8String],
        [_message lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);

    /* Set the port and address we want to send to */
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = inet_addr([_SSDP_ADDR UTF8String]);
    addr.sin_port = htons(_SSDP_PORT);

    NSData *address = [NSData dataWithBytes:&addr length:sizeof(addr)];

    if (CFSocketSendData(_cfSocketSend, (__bridge CFDataRef)address, data,
                         0.0) == kCFSocketSuccess) {
        NSLog(@"UdpRequest callCFSocket Sending data");
    }
    NSLog(@"UdpRequest Initialising socket for listening");
    _cfSocketListen = [self initSocket:_cfSocketListen];
    if (!_cfSocketListen) {
        CFRelease(data);
        return;
    }

    /* Set the port and address we want to listen on */
    if (CFSocketSetAddress(_cfSocketListen, (__bridge CFDataRef)(address)) !=
        kCFSocketSuccess) {
        NSLog(@"UdpRequest callCFSocket CFSocketSetAddress() failed\n = %d",
              errno);
    }

    // Listen from socket
    CFRunLoopSourceRef cfSourceSend =
        CFSocketCreateRunLoopSource(kCFAllocatorDefault, _cfSocketSend, 0);
    CFRunLoopSourceRef cfSourceListen =
        CFSocketCreateRunLoopSource(kCFAllocatorDefault, _cfSocketListen, 0);

    if (cfSourceSend == NULL && cfSourceListen == NULL) {
        NSLog(@"UdpRequest callCFSocket CFRunLoopSourceRef is null");
        CFRelease(_cfSocketSend);
        CFRelease(_cfSocketListen);
        CFRelease(data);
        return;
    }

    if (cfSourceSend != NULL) {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), cfSourceSend,
                           kCFRunLoopDefaultMode);
        CFRelease(cfSourceSend);
    }
    if (cfSourceListen != NULL) {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), cfSourceListen,
                           kCFRunLoopDefaultMode);
        NSLog(@"UdpRequest callCFSocket Socket listening");
        CFRelease(cfSourceListen);
    }

    CFRelease(_cfSocketSend);
    CFRelease(_cfSocketListen);
    CFRelease(data);
    CFRunLoopRun();
    NSLog(@"UdpRequest callCFSocket CFRunLoopRun finish");
}

/*
 * Function for initializing socket for SSDP
 */
- (CFSocketRef)initSocket:(CFSocketRef)socket
{
    CFSocketContext socketContext = {0, (__bridge void *)(self), NULL, NULL,
                                     NULL};
    socket = CFSocketCreate(NULL, PF_INET, SOCK_DGRAM, IPPROTO_UDP,
                            kCFSocketAcceptCallBack | kCFSocketDataCallBack,
                            (CFSocketCallBack)receiveData, &socketContext);
    if (socket == NULL) {
        NSLog(@"UdpRequest UDP socket could not be created\n");
        return socket;
    }

    CFSocketSetSocketFlags(socket, kCFSocketCloseOnInvalidate);

    struct ip_mreq mreq;
    mreq.imr_multiaddr.s_addr = inet_addr([_SSDP_ADDR UTF8String]);
    mreq.imr_interface.s_addr = inet_addr([[self getIPAddress] UTF8String]);

    if (setsockopt(CFSocketGetNative(socket), IPPROTO_IP, IP_ADD_MEMBERSHIP,
                   (const void *)&mreq, sizeof(struct ip_mreq))) {
        NSLog(@"UdpRequest callCFSocket IP_ADD_MEMBERSHIP error");
        return nil;
    }
    return socket;
}

void receiveData(CFSocketRef s, CFSocketCallBackType type, CFDataRef address,
                 const void *data, void *info)
{
    if (data) {
        NSString *response =
            [[NSString alloc] initWithData:(__bridge NSData *)((CFDataRef)data)
                                  encoding:NSUTF8StringEncoding];
        NSLog(@"UdpRequest CFSocket receiveData response = %@", response);

        UdpRequest *udpRequest = (__bridge UdpRequest *)info;

        NSString *ddUrl = nil;
        NSString *uuid = nil;
        NSDictionary *headers = [udpRequest parseHeaders:response];
        for (NSString *key in headers.allKeys) {
            if ([key compare:@"LOCATION" options:NSCaseInsensitiveSearch] == 0) {
                ddUrl = [headers[key] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            } else if ([key compare:@"USN" options:NSCaseInsensitiveSearch] == 0) {
                uuid = [headers[key] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
        }
        NSLog(@"UdpRequest CFSocket receiveData didReceiveDdUrl = %@", ddUrl);

        if (![_deviceUuidList containsObject:uuid]) {
            if (uuid != NULL) {
                [_deviceUuidList addObject:uuid];
                NSLog(@"UdpRequest CFSocket receiveData uuid = %@", uuid);
            }
            [_discoveryDelegate didReceiveDdUrl:ddUrl];
        }
        CFSocketInvalidate(s);
    }
}

- (NSDictionary *)parseHeaders:(NSString *)response
{
    NSMutableDictionary *ret = [[NSMutableDictionary alloc] init];
    NSArray *lines = [response componentsSeparatedByString:@"\r\n"];
    for (int i = 1; i < lines.count; i++) {
        NSString *line = lines[i];
        NSRange colonRange = [line rangeOfString:@":"];
        if (colonRange.location != NSNotFound) {
            NSString *key = [line substringToIndex:colonRange.location];
            NSString *value = [[line substringFromIndex:colonRange.location+1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            ret[key] = value;
        }
    }

    return ret;
}

- (NSString *)parseDdUrl:(NSString *)response
{
    NSString *ret = NULL;
    if (response == NULL) {
        return ret;
    }
    NSArray *first = [response componentsSeparatedByString:@"LOCATION:"];
    if (first != nil && first.count == 2) {
        NSArray *second = [first[1] componentsSeparatedByString:@"\r\n"];
        if (second != nil && second.count >= 2) {
            if (![second[0] isEqualToString:@""]) {
                ret = second[0];
                _didReceiveSsdp = true;
            }
        }
    }
    return ret;
}

- (NSString *)parseUuid:(NSString *)response
{
    NSString *ret = NULL;
    if (response == NULL) {
        return ret;
    }
    NSArray *first = [response componentsSeparatedByString:@"USN:"];
    if (first != nil && first.count == 2) {
        NSArray *second = [first[1] componentsSeparatedByString:@":"];
        if (second != nil && second.count >= 2) {
            if (![second[1] isEqualToString:@""]) {
                ret = second[1];
            }
        }
    }
    return ret;
}

- (NSString *)getIPAddress
{
    NSString *address = @"0.0.0.0";
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    int success = 0;
    // retrieve the current interfaces - returns 0 on success
    success = getifaddrs(&interfaces);
    if (success == 0) {
        // Loop through linked list of interfaces
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr->sa_family == AF_INET) {
                NSLog(@"UdpRequest getIPAddress NIF = %@",
                      @(temp_addr->ifa_name));
                // Check if interface is en0 which is the wifi connection on the
                // iPhone
                if ([@(temp_addr->ifa_name) isEqualToString:@"en0"]) {
                    address = @(inet_ntoa(
                        ((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr));
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    NSLog(@"UdpRequest getIPAddress = %@", address);
    return address;
}

@end

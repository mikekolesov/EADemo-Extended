/*
    Copyright (C) 2016 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information
    
    Abstract:
    Provides an interface for communication with an EASession. Also the delegate for the EASession input and output stream objects.
 */

#import "EADSessionController.h"
#import "NSThread+RunBlock.h"
#import "EADSessionController+SpeedMeasure.h"

#include <pthread.h>

@interface EADSessionController ()

@property (nonatomic, strong) EASession *session;

@property (nonatomic, strong) NSMutableData *writeDataCache;
@property (nonatomic, strong) NSMutableData *readDataCache;

@property (nonatomic, strong) NSThread *inputStreamThread;
@property (nonatomic, strong) NSThread *outputStreamThread;

@property (nonatomic, assign) BOOL isInputThreadReady;
@property (nonatomic, assign) BOOL isOutputThreadReady;

@property (nonatomic, strong) NSLock *readCacheLock;
@property (nonatomic, strong) NSLock *writeCacheLock;

@property (nonatomic, assign) BOOL isSessionOpened;

@property (nonatomic, assign) BOOL keepRunningOutput;
@property (nonatomic, assign) BOOL keepRunningInput;

@end

NSString *EADSessionDataReceivedNotification = @"EADSessionDataReceivedNotification";

@implementation EADSessionController

#pragma mark Public Methods

+ (EADSessionController *)sharedController
{
    static EADSessionController *sessionController = nil;
    if (sessionController == nil) {
        sessionController = [[EADSessionController alloc] init];
        sessionController.isSessionOpened = NO;
    }

    return sessionController;
}

- (void)dealloc
{
    [self closeSession];
    [self setupControllerForAccessory:nil withProtocolString:nil];
}

// initialize the accessory with the protocolString
- (void)setupControllerForAccessory:(EAAccessory *)accessory withProtocolString:(NSString *)protocolString
{
    NSLog(@"setupControllerForAccessory entered protocolString is %@", protocolString);
    _accessory = accessory;
    _protocolString = [protocolString copy];
}

// open a session with the accessory and set up the input and output stream on the default run loop
- (BOOL)openSession
{
    self.keepRunningInput = YES;
    self.keepRunningOutput = YES;
    
    self.isInputThreadReady = NO;
    self.isOutputThreadReady = NO;
    
    self.readDataCache = [NSMutableData new];
    self.writeDataCache = [NSMutableData new];
    
    self.readCacheLock = [NSLock new];
    self.writeCacheLock = [NSLock new];
    
    [_accessory setDelegate:self];
    _session = [[EASession alloc] initWithAccessory:_accessory forProtocol:_protocolString];
    
    if (_session)
    {
        self.inputStreamThread = [[NSThread alloc] initWithTarget:self selector:@selector(inputThreadRoutine:) object:_session];
        if (self.inputStreamThread != nil ) {
            [self.inputStreamThread setName:@"InputStreamThread"];
            [self.inputStreamThread start];
        }
        
        self.outputStreamThread = [[NSThread alloc] initWithTarget:self selector:@selector(outputThreadRoutine:) object:_session];
        if (self.outputStreamThread != nil ) {
            [self.outputStreamThread setName:@"OutputStreamThread"];
            [self.outputStreamThread start];
        }
        
        //waiting for threads setup to be ready
        NSInteger waitingStreams = 0;
        while (!self.isInputThreadReady && !self.isOutputThreadReady) {
            usleep(10000);
            waitingStreams += 1;
            NSLog(@"Number of waiting streams: %ld", (long)waitingStreams);
        }
        
        self.isSessionOpened = YES;
    }
    else
    {
        NSLog(@"Creating EASession is failed");
    }
    
    return (_session != nil);
}

// close the session with the accessory.
- (void)closeSession
{
    NSLog(@"Closing EA session");
    // prevent using session outside
    self.isSessionOpened = NO;
    
    [[_session outputStream] setDelegate:nil];
    [[_session inputStream] setDelegate:nil];
    
    [self.outputStreamThread performBlock:^{
        [[_session outputStream] removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [[_session outputStream] close];
    }];
    
    [self.inputStreamThread performBlock:^{
        [[_session inputStream] removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [[_session inputStream] close];
        
    }];
    
    // stop threads
    self.keepRunningOutput = NO;
    self.keepRunningInput = NO;
    
    _session = nil;
}

- (void) inputThreadRoutine:(EASession *)session {
    
    pthread_setname_np([[[NSThread currentThread] name] UTF8String]);
    
    [[session inputStream] setDelegate:self];
    [[session inputStream] scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [[session inputStream] open];
    
    self.isInputThreadReady = YES;
    
    NSRunLoop *theRL = [NSRunLoop currentRunLoop];
    while (self.keepRunningInput && [theRL runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
}

- (void) outputThreadRoutine:(EASession *)session {
    
    pthread_setname_np([[[NSThread currentThread] name] UTF8String]);
    
    [[session outputStream] setDelegate:self];
    [[session outputStream] scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [[session outputStream] open];
    
    self.isOutputThreadReady = YES;
    
    NSRunLoop *theRL = [NSRunLoop currentRunLoop];
    while (self.keepRunningOutput && [theRL runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
}

#pragma mark - NSStreamDelegateEventExtensions

// asynchronous NSStream handleEvent method
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    switch (eventCode) {
        case NSStreamEventNone:
            NSLog(@"Stream event: NSStreamEventNone");
            break;
        case NSStreamEventOpenCompleted:
            NSLog(@"Stream event: NSStreamEventOpenCompleted");
            break;
        case NSStreamEventHasBytesAvailable:
            NSLog(@"Stream event: NSStreamEventHasBytesAvailable");
            [self internalReadData];
            break;
        case NSStreamEventHasSpaceAvailable:
            NSLog(@"Stream event: NSStreamEventHasSpaceAvailable");
            [self internalWriteData];
            break;
        case NSStreamEventErrorOccurred:
            NSLog(@"Stream event: NSStreamEventErrorOccurred");
            NSLog(@"%@", aStream.streamError);
            break;
        case NSStreamEventEndEncountered:
            NSLog(@"Stream event: NSStreamEventEndEncountered");
            break;
        default:
            break;
    }
}

//********** READ **********//

// get number of bytes read into local buffer
- (NSUInteger)readBytesAvailable
{
    return [self.readDataCache length];
}


// external API read of cached EA data

- (NSInteger)readCacheWith:(uint8_t *)buffer andLength:(NSUInteger)length {
    
    if (self.isSessionOpened == NO) {
        NSLog(@"readCacheWith. Using closed Session prohibited");
        return 0;
    }
    
    int readRes = 0;
    
    [self.readCacheLock lock];
    NSInteger minAvailableLength = MIN([self.readDataCache length], length);
    NSRange range = NSMakeRange(0, minAvailableLength);
    [self.readDataCache getBytes:buffer range:range];
    [self.readDataCache replaceBytesInRange:range withBytes:NULL length:0];
    readRes = (int)minAvailableLength;
    [self.readCacheLock unlock];
    
    return readRes;
}


// internal read getting EA data to cache

#define EA_READ_BUFFER_SIZE 1024

- (void)internalReadData {
    
    NSLog(@"internalReadData called");
    uint8_t buf[EA_READ_BUFFER_SIZE];
    NSTimeInterval t1 = [[NSDate date] timeIntervalSince1970];
    NSInteger amountOfData = 0;
    NSInteger readCounts = 0;
    while ([[_session inputStream] hasBytesAvailable])
    {
        NSInteger bytesRead = [[_session inputStream] read:buf maxLength:EA_READ_BUFFER_SIZE];
        NSLog(@"_readData bytesRead = %ld", bytesRead);
        [self.readCacheLock lock];
        [self.readDataCache appendBytes:(void *)buf length:bytesRead];
        [self.readCacheLock unlock];
        amountOfData += bytesRead;
        readCounts++;
    }
    NSTimeInterval t2 = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval t3 = t2 - t1;
    NSLog(@"Read time=%f, read amount=%ld, readCounts=%ld", t3, amountOfData, readCounts);
    
    [self measureSpeedPerSecond:amountOfData completion:^(NSString *speedPerSecond) {
        NSLog(@"Downloading Speed: %@", speedPerSecond);
    }];
    
    // notify that data is ready
    [[NSNotificationCenter defaultCenter] postNotificationName:EADSessionDataReceivedNotification object:self userInfo:nil];
}


//********** WRITE **********//

// external API write to cache

- (NSInteger)writeCacheWith:(const uint8_t *)buffer andLength:(NSUInteger)length {
    
    if (self.isSessionOpened == NO) {
        NSLog(@"writeCacheWith. Using closed Session prohibited");
        return 0;
    }
    
    int __block writeRes = (int)length;
    
    [self.writeCacheLock lock];
    [self.writeDataCache appendBytes:buffer length:length];
    [self.writeCacheLock unlock];
    
    [self.outputStreamThread performBlock:^{
        writeRes = [self internalWriteData];
        
    }];
    
    // wait for write finish
    NSInteger waitWriteCounter = 0;
    while (self.writeDataCache.length > 0) {
        if (waitWriteCounter > 10) {
            NSLog(@"Waiting for write finish. Stuck with write to accessory!");
            break;
        }
        usleep(30000);
        waitWriteCounter++;
    }
    NSLog(@"Number of write waites = %zd", waitWriteCounter);
    return length;
}


// internal API write consuming cached data to EA

- (int)internalWriteData {
    [self.writeCacheLock lock];
    NSTimeInterval t1 = [[NSDate date] timeIntervalSince1970];
    NSInteger amountOfData = 0;
    NSInteger bytesWritten = 0;
    NSInteger writeCounter = 0;
    while ([[_session outputStream] hasSpaceAvailable] && ([self.writeDataCache length] > 0))
    {
        bytesWritten = [[_session outputStream] write:[self.writeDataCache bytes] maxLength:[self.writeDataCache length]];
        if (bytesWritten > 0)
        {
            [self.writeDataCache replaceBytesInRange:NSMakeRange(0, bytesWritten) withBytes:NULL length:0];
            NSLog(@"internalWriteData bytesWritten %ld", (long)bytesWritten);
            
        } else if (bytesWritten == 0 ) {
            // double check this case
            NSLog(@"internalWriteData bytesWritten == ZERO!");
        } else {
            NSLog(@"internalWriteData: write error");
            break;
        }
        
        amountOfData += bytesWritten;
        writeCounter++;
    }
    NSTimeInterval t2 = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval t3 = t2 - t1;
    NSLog(@"Write time=%f, write amount=%ld, write counter = %zd", t3, amountOfData, writeCounter);
    [self.writeCacheLock unlock];
    return (int)amountOfData;
}



@end

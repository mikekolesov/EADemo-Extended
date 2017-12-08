/*
 Copyright (C) 2016 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information
 
 Abstract:
 Provides an interface for communication with an EASession. Also the delegate for the EASession input and output stream objects.
 */

@import Foundation;
@import ExternalAccessory;

extern NSString *EADSessionDataReceivedNotification;

@interface EADSessionController : NSObject <EAAccessoryDelegate, NSStreamDelegate>

+ (EADSessionController *)sharedController;

- (void)setupControllerForAccessory:(EAAccessory *)accessory withProtocolString:(NSString *)protocolString;

- (BOOL)openSession;
- (void)closeSession;

- (NSInteger)readCacheWith:(uint8_t *)buffer andLength:(NSUInteger)length;
- (NSInteger)writeCacheWith:(const uint8_t *)buffer andLength:(NSUInteger)length;

- (NSUInteger)readBytesAvailable;

@property (nonatomic, readonly) EAAccessory *accessory;
@property (nonatomic, readonly) NSString *protocolString;

@end

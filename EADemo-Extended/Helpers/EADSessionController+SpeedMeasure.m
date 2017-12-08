//
//  EADSessionController+SpeedMeasure.m
//  EADemo-Extended
//
//  Created by MKolesov on 08/12/2017.
//  Copyright © 2017 MKolesov. All rights reserved.
//

#import "EADSessionController+SpeedMeasure.h"

@implementation EADSessionController (SpeedMeasure)

- (void) measureSpeedPerSecond:(int64_t)bytesTransfered completion:(void (^)(NSString *speedPerSecond))completionHandler {
    static NSTimeInterval lastSecondTimeStamp = -1;
    static int64_t bytesWrittenInSecond = 0;
    
    NSTimeInterval currentTimeStamp = [[NSDate date] timeIntervalSince1970];
    bytesWrittenInSecond += bytesTransfered;
    
    if (lastSecondTimeStamp == -1) {
        lastSecondTimeStamp = currentTimeStamp;
    } else if (lastSecondTimeStamp + 1 < currentTimeStamp ) {
        lastSecondTimeStamp = currentTimeStamp;
        
        NSString *bytesPerSeconds = nil;
        if (bytesWrittenInSecond > 1000000) {
            bytesPerSeconds = [NSString stringWithFormat:@"Speed %.1f MB/s", bytesWrittenInSecond/1000000.0];
        } else if (bytesWrittenInSecond > 1000) {
            bytesPerSeconds = [NSString stringWithFormat:@"Speed %.1f KB/s", bytesWrittenInSecond/1000.0];
        } else {
            bytesPerSeconds = [NSString stringWithFormat:@"Speed %.1f B/s", (double)bytesWrittenInSecond];
        }
        bytesWrittenInSecond = 0;
        
        completionHandler(bytesPerSeconds);
    }
}

@end

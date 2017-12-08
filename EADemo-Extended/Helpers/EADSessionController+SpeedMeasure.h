//
//  EADSessionController+SpeedMeasure.h
//  EADemo-Extended
//
//  Created by MKolesov on 08/12/2017.
//  Copyright © 2017 MKolesov. All rights reserved.
//

#import "EADSessionController.h"

@interface EADSessionController (SpeedMeasure)
- (void) measureSpeedPerSecond:(int64_t)bytesTransfered completion:(void (^)(NSString *speedPerSecond))completionHandler;
@end

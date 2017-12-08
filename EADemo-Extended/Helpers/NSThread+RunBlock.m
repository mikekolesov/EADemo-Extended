//
//  NSThread+RunBlock.m
//  EADemo-Extended
//
//  Created by MKolesov on 08/12/2017.
//  Copyright © 2017 MKolesov. All rights reserved.
//

#import "NSThread+RunBlock.h"

@implementation NSThread (RunBlock)
- (void) performBlock: (void (^)(void))block;
{
    [self performSelector: @selector(runBlock:)
                 onThread: self withObject: block waitUntilDone: YES];
}

- (void) runBlock: (void (^)(void))block;
{
    block();
}
@end

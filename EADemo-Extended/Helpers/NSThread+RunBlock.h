//
//  NSThread+RunBlock.h
//  EADemo-Extended
//
//  Created by MKolesov on 08/12/2017.
//  Copyright © 2017 MKolesov. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSThread (RunBlock)
- (void) performBlock: (void (^)(void))block;
@end

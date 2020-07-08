//
//  PINManager.h
//  YubiKey-observer
//
//  Created by bluebox on 2020/07/08.
//  Copyright © 2020 cx.lab. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PINManager : NSObject
- (NSString*)getPinForKey:(NSString*)key;
@end

NS_ASSUME_NONNULL_END

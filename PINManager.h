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
- (NSString* _Nullable)getPinForKey:(NSString*)key;
- (OSStatus)storePin:(NSString*)pin forKey:(NSString*)key withLabel:(NSString*)label;
- (void)dump;
@end

NS_ASSUME_NONNULL_END

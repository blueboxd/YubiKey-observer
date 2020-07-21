//
//  YubiKeyManager.h
//  YubiKey-observer
//
//  Created by bluebox on 2020/07/08.
//  Copyright © 2020 cx.lab. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "YubiKey.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName YubiKeyDeviceManagerKeyInsertedNotificationKey;
extern NSNotificationName YubiKeyDeviceManagerKeyRemovedNotificationKey;

@interface YubiKeyDeviceManager : NSObject
- (kern_return_t) registerMatchingCallbacks;
- (NSDictionary*) getAnyYubiKey;
- (int8_t) verifyPIN:(NSString*)pin forDeviceSerial:(NSNumber*)serial;
@property (nonatomic,readonly) NSMutableDictionary<NSString*,YubiKey*> *devices;
@end

NS_ASSUME_NONNULL_END

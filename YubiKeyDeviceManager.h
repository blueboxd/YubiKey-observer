//
//  YubiKeyManager.h
//  YubiKey-observer
//
//  Created by bluebox on 2020/07/08.
//  Copyright © 2020 cx.lab. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol YubiKeyDeviceManagerDelegate <NSObject>

- (void) deviceAdded:(NSDictionary*)dev;
- (void) deviceRemoved:(NSDictionary*)dev;

@end

@interface YubiKeyDeviceManager : NSObject
- (kern_return_t) registerMatchingCallbacks;
- (NSString*) getUniqueIDFromDev:(NSDictionary*)dev;

@property (nonatomic) BOOL isYubiKeyInserted;
@property (nonatomic,readonly) NSMutableDictionary<NSString*,NSDictionary*> *devices;
@property (strong) IBOutlet NSUserDefaultsController *prefsController;

@property (weak, nonatomic) IBOutlet id <YubiKeyDeviceManagerDelegate> delegate;

@end

NS_ASSUME_NONNULL_END

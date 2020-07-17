//
//  YubiKeyManager.h
//  YubiKey-observer
//
//  Created by bluebox on 2020/07/08.
//  Copyright © 2020 cx.lab. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName YubiKeyDeviceManagerKeyInsertedNotificationKey;
extern NSNotificationName YubiKeyDeviceManagerKeyRemovedNotificationKey;

extern NSString* const YubiKeyDeviceDictionaryUSBNameKey;
extern NSString* const YubiKeyDeviceDictionaryUSBSerialNumberKey;
extern NSString* const YubiKeyDeviceDictionaryUSBLocationKey;
extern NSString* const YubiKeyDeviceDictionaryUniqueStringKey;

extern NSString *const YubiKeyDeviceDictionaryPropertyKey;
extern NSString *const YubiKeyDevicePropertySerialKey; 
extern NSString *const YubiKeyDevicePropertyVersionKey;
extern NSString *const YubiKeyDevicePropertyFormfactorKey;
extern NSString *const YubiKeyDevicePropertyNFCSupportedKey;
extern NSString *const YubiKeyDevicePropertyNFCEnabledKey;
extern NSString *const YubiKeyDevicePropertyUSBSupportedKey;
extern NSString *const YubiKeyDevicePropertyUSBEnabledKey;
extern NSString *const YubiKeyDevicePropertyModelKey;

@interface YubiKeyDeviceManager : NSObject
- (kern_return_t) registerMatchingCallbacks;
- (NSDictionary*) getAnySingleDevice;
@property (nonatomic,readonly) NSMutableDictionary<NSString*,NSDictionary*> *devices;
@end

NS_ASSUME_NONNULL_END

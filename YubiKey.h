//
//  YubiKey.h
//  YubiKey-observer
//
//  Created by bluebox on 2020/07/21.
//  Copyright © 2020 cx.lab. All rights reserved.
//

#import <Foundation/Foundation.h>

#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/hid/IOHIDLib.h>
#include <IOKit/hid/IOHIDKeys.h>

#include <PCSC/winscard.h>
#include <PCSC/wintypes.h>


NS_ASSUME_NONNULL_BEGIN

#define kYubiKeyDeviceManagerVerifyPINSuccess 0
#define kYubiKeyDeviceManagerVerifyPINBlockedErr -1
#define kYubiKeyDeviceManagerVerifyPINUnknownErr -127

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

typedef enum ConfigTags {
    USB_SUPPORTED = 0x01,
    SERIAL = 0x02,
    USB_ENABLED = 0x03,
    FORMFACTOR = 0x04,
    VERSION = 0x05,
    AUTO_EJECT_TIMEOUT = 0x06,
    CHALRESP_TIMEOUT = 0x07,
    DEVICE_FLAGS = 0x08,
    APP_VERSIONS = 0x09,
    CONFIG_LOCK = 0x0a,
    USE_LOCK_KEY = 0x0b,
    REBOOT = 0x0c,
    NFC_SUPPORTED = 0x0d,
    NFC_ENABLED = 0x0e,
}ConfigTags ;

enum ConfigFormfactor {
    UNKNOWN = 0x00,
    USB_A_KEYCHAIN = 0x01,
    USB_A_NANO = 0x02,
    USB_C_KEYCHAIN = 0x03,
    USB_C_NANO = 0x04,
    USB_C_LIGHTNING = 0x05
};

enum ConfigApplications {
    OTP = 0x01,
    U2F = 0x02,
    OPGP = 0x08,
    PIV = 0x10,
    OATH = 0x20,
    FIDO2 = 0x200,
};

@interface YubiKey : NSObject

+ (NSString*) getUniqueStringFromIOService:(io_service_t) service;
- (instancetype) initWithIOService:(io_service_t) service;
- (NSString*) getUniqueString;
- (int8_t) verifyPIN:(NSString*)pin;

@property (readonly,nonatomic) NSString *usbName;
@property (readonly,nonatomic) NSString *model;
@property (readonly,nonatomic) NSString *serial;
@property (readonly,nonatomic) NSString *location;

@end

NS_ASSUME_NONNULL_END

//
//  YubiKeyManager.m
//  YubiKey-observer
//
//  Created by bluebox on 2020/07/08.
//  Copyright © 2020 cx.lab. All rights reserved.
//

#import "YubiKeyDeviceManager.h"
#import "PrefKeys.h"

#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/hid/IOHIDKeys.h>

@interface YubiKeyDeviceManager()

@end

static YubiKeyDeviceManager *gSelf;
@implementation YubiKeyDeviceManager {
	NSArray<NSDictionary*> *yubikeyArray;
}

- (instancetype) init {
	self = [super init];
	gSelf = self;
	return self;
}

- (NSString*) getUniqueIDFromDev:(NSDictionary*) dev {
	return [NSString stringWithFormat:@"%@/%@-%@",dev[@kUSBDevicePropertyLocationID],dev[@kUSBProductString],dev[@kUSBSerialNumberString]];
}

void IOServiceMatchedCallback(void* refcon, io_iterator_t iterator);
- (kern_return_t) registerMatchingCallbacks{
	kern_return_t kr;

	IONotificationPortRef notifyPort = IONotificationPortCreate(kIOMasterPortDefault);
	CFRunLoopSourceRef loopSource = IONotificationPortGetRunLoopSource(notifyPort);
	CFRunLoopRef runLoop = CFRunLoopGetCurrent();
	CFRunLoopAddSource(runLoop, loopSource, kCFRunLoopDefaultMode);

	CFMutableDictionaryRef matchDict = (__bridge_retained CFMutableDictionaryRef)@{
		@kIOProviderClassKey : @kIOUSBDeviceClassName,
		@kUSBProductID : @"*",
		@kUSBVendorID : @0x1050
	};

	CFRetain(matchDict);

	io_iterator_t iterator;
	io_service_t usbDevice;

	kr = IOServiceAddMatchingNotification(notifyPort, kIOFirstMatchNotification, matchDict, IOServiceMatchedCallback, (void*)YES, &iterator);
	if(kr!=KERN_SUCCESS) return kr;
	while ((usbDevice=IOIteratorNext(iterator))) {
		CFDictionaryRef dict = GetKeyInfo(usbDevice);
		if(dict) {
			NSLog(@"initial device found:%@",dict);
			[self.delegate deviceAdded:(__bridge_transfer NSDictionary*)dict];
		}
	}

	kr = IOServiceAddMatchingNotification(notifyPort, kIOTerminatedNotification, matchDict, IOServiceMatchedCallback, (void*)NO, &iterator);
	if(kr!=KERN_SUCCESS) return kr;
	while ((usbDevice=IOIteratorNext(iterator))) {
		CFDictionaryRef dict = GetKeyInfo(usbDevice);
		if(dict)
			NSLog(@"device found for termination:%@",dict);
	}
	return KERN_SUCCESS;
}

void IOServiceMatchedCallback(void* added, io_iterator_t iterator) {
	NSLog(@"IOServiceMatchedCallback");
	io_service_t usbDevice;

	while ((usbDevice=IOIteratorNext(iterator))) {
		CFDictionaryRef dict = GetKeyInfo(usbDevice);
		if(dict) {
			if(added) {
				NSLog(@"YubiKey inserted:%@",dict);
				[gSelf.delegate deviceAdded:(__bridge_transfer NSDictionary*)dict];
			} else {
				NSLog(@"YubiKey removed:%@",dict);
				[gSelf.delegate deviceRemoved:(__bridge_transfer NSDictionary*)dict];
			}
		}
	}
}

CFDictionaryRef GetKeyInfo(io_service_t usbDevice) {
	kern_return_t kr;
	CFMutableDictionaryRef devDict = nil;

	kr = IORegistryEntryCreateCFProperties(usbDevice, &devDict, kCFAllocatorDefault, kNilOptions);
	if(kr!=KERN_SUCCESS) return nil;
	NSLog(@"Yubico device (idVendor:0x1050) found:%@",devDict);

	io_name_t devName;
	IORegistryEntryGetName(usbDevice, devName);
	if(!strstr(devName,"CCID"))
		return nil;
	
	if(!CFDictionaryContainsKey(devDict, CFSTR(kUSBSerialNumberString)))
		CFDictionarySetValue(devDict, CFSTR(kUSBSerialNumberString), CFSTR("unknown"));
	
	return devDict;
}

@end

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

NSNotificationName YubiKeyDeviceManagerKeyInsertedNotificationKey = @"YubiKeyDeviceManagerKeyInsertedNotificationKey";
NSNotificationName YubiKeyDeviceManagerKeyRemovedNotificationKey = @"YubiKeyDeviceManagerKeyRemovedNotificationKey";

const NSString* YubiKeyDeviceDictionaryUSBNameKey = @kUSBProductString;
const NSString* YubiKeyDeviceDictionaryUSBSerialNumberKey = @kUSBSerialNumberString;
const NSString* YubiKeyDeviceDictionaryUSBLocationKey = @kUSBDevicePropertyLocationID;
const NSString* YubiKeyDeviceDictionaryUniqueStringKey = @"UniqueString";

static YubiKeyDeviceManager *gSelf;
@implementation YubiKeyDeviceManager {
}

- (instancetype) init {
	self = [super init];
	gSelf = self;
	_devices = [NSMutableDictionary new];
	return self;
}

- (NSString*) getUniqueIDFromDev:(NSDictionary*) dev {
	return [NSString stringWithFormat:@"%@[%@]@%@",dev[YubiKeyDeviceDictionaryUSBNameKey],dev[YubiKeyDeviceDictionaryUSBSerialNumberKey],dev[YubiKeyDeviceDictionaryUSBLocationKey]];
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
			CFRetain(dict);
			NSLog(@"initial device found:%@",[self getUniqueIDFromDev:(__bridge NSDictionary*)dict]);
			[self addDevice:(__bridge_transfer NSDictionary*)(dict)];
		}
	}

	kr = IOServiceAddMatchingNotification(notifyPort, kIOTerminatedNotification, matchDict, IOServiceMatchedCallback, (void*)NO, &iterator);
	if(kr!=KERN_SUCCESS) return kr;
	while ((usbDevice=IOIteratorNext(iterator))) {
		CFDictionaryRef dict = GetKeyInfo(usbDevice);
		if(dict)
			NSLog(@"device found for termination:%@",[self getUniqueIDFromDev:(__bridge NSDictionary*)dict]);
	}
	[[NSRunLoop currentRunLoop] run];
	return KERN_SUCCESS;
}

- (void) addDevice:(NSDictionary*)dev {
	_devices[[self getUniqueIDFromDev:dev]] = dev;
	[[NSNotificationCenter defaultCenter] postNotificationName:YubiKeyDeviceManagerKeyInsertedNotificationKey object:self userInfo:dev];
}

- (void) removeDevice:(NSDictionary*)dev {
	[_devices removeObjectForKey:[self getUniqueIDFromDev:dev]];
	[[NSNotificationCenter defaultCenter] postNotificationName:YubiKeyDeviceManagerKeyRemovedNotificationKey object:self userInfo:dev];
}

void IOServiceMatchedCallback(void* added, io_iterator_t iterator) {
	io_service_t usbDevice;

	while ((usbDevice=IOIteratorNext(iterator))) {
		CFDictionaryRef dict = GetKeyInfo(usbDevice);
		if(dict) {
			CFRetain(dict);
			if(added) {
				NSLog(@"IOServiceMatchedCallback:YubiKey inserted");
				[gSelf addDevice:(__bridge_transfer NSDictionary*)(dict)];
			} else {
				NSLog(@"IOServiceMatchedCallback:YubiKey removed");
				[gSelf removeDevice:(__bridge_transfer NSDictionary*)(dict)];
			}
		}
	}
}

CFDictionaryRef GetKeyInfo(io_service_t usbDevice) {
	kern_return_t kr;
	CFMutableDictionaryRef devDict = nil;

	kr = IORegistryEntryCreateCFProperties(usbDevice, &devDict, kCFAllocatorDefault, kNilOptions);
	if(kr!=KERN_SUCCESS) return nil;
//	NSLog(@"Yubico device (idVendor:0x1050) found:%@",devDict);

	io_name_t devName;
	IORegistryEntryGetName(usbDevice, devName);
	if(!strstr(devName,"CCID"))
		return nil;
	
	if(!CFDictionaryContainsKey(devDict, CFSTR(kUSBSerialNumberString)))
		CFDictionarySetValue(devDict, CFSTR(kUSBSerialNumberString), CFSTR("unknown"));
	CFDictionarySetValue(devDict, (__bridge_retained CFStringRef)YubiKeyDeviceDictionaryUniqueStringKey,(__bridge CFStringRef)[gSelf getUniqueIDFromDev:(__bridge NSDictionary*)devDict]);
	
	return devDict;
}

@end

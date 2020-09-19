//
//  YubiKeyManager.m
//  YubiKey-observer
//
//  Created by bluebox on 2020/07/08.
//  Copyright © 2020 cx.lab. All rights reserved.
//

#import "YubiKeyDeviceManager.h"

#include "ykcore/ykcore_lcl.h"
#include "ykcore/ykcore_backend.h"
#include "ykcore/yktsd.h"
#include "ykcore/ykbzero.h"
#include "ykcore/yubikey.h"
#include "ykcore/ykdef.h"
#include "ykcore/ykcore.h"

#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/hid/IOHIDLib.h>
#include <IOKit/hid/IOHIDKeys.h>

#include <PCSC/winscard.h>
#include <PCSC/wintypes.h>

NSNotificationName YubiKeyDeviceManagerKeyInsertedNotificationKey = @"YubiKeyDeviceManagerKeyInsertedNotificationKey";
NSNotificationName YubiKeyDeviceManagerKeyRemovedNotificationKey = @"YubiKeyDeviceManagerKeyRemovedNotificationKey";

static YubiKeyDeviceManager *gSelf;
@implementation YubiKeyDeviceManager {
}

- (instancetype) init {
	self = [super init];
	gSelf = self;
	_devices = [NSMutableDictionary new];
	return self;
}


#define CHECK(f, rv) \
 if (SCARD_S_SUCCESS != rv) \
 { \
  printf(f ": 0x%08x(%s)\n", rv, pcsc_stringify_error(rv)); \
  return nil; \
 }

- (NSArray*) getAllCardReaders {
	ULONG rv;
	SCARDCONTEXT hContext;
	//LPTSTR mszReaders;
	BYTE buf[4096];
	DWORD dwReaders=4096;

	rv = SCardEstablishContext(SCARD_SCOPE_SYSTEM, NULL, NULL, &hContext);
	CHECK("SCardEstablishContext", rv)
	if(rv)return nil;

//	rv = SCardListReaders(hContext, NULL, NULL, &dwReaders);
//	CHECK("SCardListReaders", rv)
//	if(rv)return nil;	
//	mszReaders = calloc(dwReaders, sizeof(char));
	
	rv = SCardListReaders(hContext, NULL, buf, &dwReaders);
	CHECK("SCardListReaders2", rv)
	if(rv)return nil;

	NSMutableArray *readers = [NSMutableArray new];
	char *pos = buf;
	while(*pos) {
		[readers addObject:[NSString stringWithUTF8String:pos]];
		pos += strlen(pos)+1;
	}
//	free(mszReaders);
//	NSLog(@"readers found:%@",readers);
	rv = SCardReleaseContext(hContext);
	return readers;
}

- (YubiKey*)getAnyYubiKey {
	return self.devices[[[self.devices allKeys] objectAtIndex:0]];
}

void IOServiceMatchedCallback(void* refcon, io_iterator_t iterator);
- (kern_return_t) registerMatchingCallbacks{
	kern_return_t kr;

	IONotificationPortRef notifyPort = IONotificationPortCreate(kIOMasterPortDefault);
	CFRunLoopSourceRef loopSource = IONotificationPortGetRunLoopSource(notifyPort);
	CFRunLoopRef runLoop = CFRunLoopGetCurrent();
	CFRunLoopAddSource(runLoop, loopSource, kCFRunLoopDefaultMode);

	CFMutableDictionaryRef matchDict = (__bridge_retained CFMutableDictionaryRef)@{
		@kIOProviderClassKey : @kIOHIDDeviceKey,//@kIOUSBDeviceClassName,
//		@kIOHIDProductIDKey : @"*",
		@kIOHIDVendorIDKey : @0x1050,
		@kIOHIDPrimaryUsagePageKey : @0x1
	};

	CFRetain(matchDict);

	io_iterator_t iterator;
	io_service_t usbDevice;

	kr = IOServiceAddMatchingNotification(notifyPort, kIOFirstMatchNotification, matchDict, IOServiceMatchedCallback, (void*)YES, &iterator);
	if(kr!=KERN_SUCCESS) return kr;
	while ((usbDevice=IOIteratorNext(iterator))) {
		YubiKey *yubikey = [gSelf getYubiKeyInfo:usbDevice];
		if(yubikey) {
//			NSLog(@"initial device found:%@",[yubikey getUniqueString]);
			[self addDevice:yubikey];
		}
	}

	kr = IOServiceAddMatchingNotification(notifyPort, kIOTerminatedNotification, matchDict, IOServiceMatchedCallback, (void*)NO, &iterator);
	if(kr!=KERN_SUCCESS) return kr;
	while ((usbDevice=IOIteratorNext(iterator))) {
		YubiKey *yubikey = [gSelf getYubiKeyInfo:usbDevice];
//		if(yubikey)
//			NSLog(@"device found for termination:%@",[yubikey getUniqueString]);
	}
	[[NSRunLoop currentRunLoop] run];
	return KERN_SUCCESS;
}

- (void) addDevice:(YubiKey*)yubikey {
	_devices[[yubikey getUniqueString]] = yubikey;
	[[NSNotificationCenter defaultCenter] postNotificationName:YubiKeyDeviceManagerKeyInsertedNotificationKey object:self userInfo:yubikey];
}

- (void) removeDevice:(YubiKey*)yubikey {
	[_devices removeObjectForKey:[yubikey getUniqueString]];
	[[NSNotificationCenter defaultCenter] postNotificationName:YubiKeyDeviceManagerKeyRemovedNotificationKey object:self userInfo:yubikey];
}

void IOServiceMatchedCallback(void* added, io_iterator_t iterator) {
	io_service_t usbDevice;

	while ((usbDevice=IOIteratorNext(iterator))) {
		if(added) {
			YubiKey *yubikey = [gSelf getYubiKeyInfo:usbDevice];
			if(yubikey) {
//				NSLog(@"IOServiceMatchedCallback:YubiKey inserted");
				[gSelf addDevice:yubikey];
			}
		} else {
			NSString *idStr = [YubiKey getUniqueStringFromIOService:usbDevice];
			YubiKey *yubikey = gSelf.devices[idStr];
//			NSLog(@"IOServiceMatchedCallback::remove: %@",yubikey);
			if(yubikey) {
//				NSLog(@"IOServiceMatchedCallback:YubiKey removed");
				[gSelf removeDevice:yubikey];
			}
		}
	}
}

-(void) WaitTillRecognized {
//	uint64_t start,end,diff;
//	start=clock_gettime_nsec_np(_CLOCK_REALTIME);
	NSArray *readers = [self getAllCardReaders];
	NSUInteger curCount = [self.devices count];
	int i=0;
	for(;[readers count]==curCount;i++) {
		usleep(5000);
		readers = [self getAllCardReaders];
		if(i>100)
			break;
	}
//	end=clock_gettime_nsec_np(_CLOCK_REALTIME);
//	diff=end-start;
//	NSLog(@"WaitTillRecognized:%u, %llu ns",i,diff);
}

- (YubiKey*)getYubiKeyInfo:(io_service_t)usbDevice {
	kern_return_t kr;
	CFMutableDictionaryRef devDict = nil;
	kr = IORegistryEntryCreateCFProperties(usbDevice, &devDict, kCFAllocatorDefault, kNilOptions);
	if(kr!=KERN_SUCCESS) return nil;
//	NSLog(@"GetDeviceInfo:%@",devDict);
	CFStringRef devName = CFDictionaryGetValue(devDict, CFSTR(kIOHIDProductKey));
	CFRange range = CFStringFind(devName, CFSTR("CCID"), kCFCompareCaseInsensitive);
	if(range.location==kCFNotFound)
		return nil;

	[gSelf WaitTillRecognized];
	YubiKey *yubikey = [[YubiKey alloc] initWithIOService:usbDevice];
	if(!yubikey)
		return nil;
	return yubikey;
}

@end

//
//  YubiKeyManager.m
//  YubiKey-observer
//
//  Created by bluebox on 2020/07/08.
//  Copyright © 2020 cx.lab. All rights reserved.
//

#import "YubiKeyDeviceManager.h"

#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/hid/IOHIDLib.h>
#include <IOKit/hid/IOHIDKeys.h>

#include <PCSC/winscard.h>
#include <PCSC/wintypes.h>

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

#define CHECK(f, rv) \
 if (SCARD_S_SUCCESS != rv) \
 { \
  printf(f ": %s\n", pcsc_stringify_error(rv)); \
  return; \
 }

void sendAPDU(SCARDHANDLE hCard, SCARD_IO_REQUEST pioSendPci, BYTE apdu[], DWORD size) {
	LONG rv;
	DWORD dwRecvLength;
	BYTE pbRecvBuffer[258];
	
	printf("request: ");
	for(unsigned int i=0; i<size; i++)
		printf("%02X ", apdu[i]);
	printf("\n");

	dwRecvLength = sizeof(pbRecvBuffer);
	rv = SCardTransmit(hCard, &pioSendPci, apdu, size,
					   NULL, pbRecvBuffer, &dwRecvLength);
	CHECK("SCardTransmit", rv)
	
	printf("response: ");
	for(unsigned int i=0; i<dwRecvLength; i++)
		printf("%02X ", pbRecvBuffer[i]);
	printf("\n");

}

- (void) awakeFromNib {
	LONG rv;
	
	SCARDCONTEXT hContext;
	LPTSTR mszReaders;
	SCARDHANDLE hCard;
	DWORD dwReaders, dwActiveProtocol;
	
	SCARD_IO_REQUEST pioSendPci;
	
	//							  cls   ins   p1    p2    lc    body -  
	BYTE cmdSelectOTP[] =		{ 0x00, 0xA4, 0x04, 0x00, 0x08, 0xA0, 0x00, 0x00, 0x05, 0x27, 0x20, 0x01, 0x01 };
	BYTE cmdSelectPIV[] =		{ 0x00, 0xA4, 0x04, 0x00, 0x05, 0xA0, 0x00, 0x00, 0x03, 0x08 };
	BYTE cmdSelectMGR[] =		{ 0x00, 0xA4, 0x04, 0x00, 0x08, 0xA0, 0x00, 0x00, 0x05, 0x27, 0x47, 0x11, 0x17 };
	BYTE cmdPIVGetSerial[] =	{ 0x00, 0xf8, 0x00, 0x00 };
	BYTE cmdPIVGetVersion[] = 	{ 0x00, 0xfd, 0x00, 0x00 };
	BYTE cmdGetConfig[] = 		{ 0x00, 0x1d, 0x00, 0x00 };
	BYTE cmdOTPGetSerial[] = 	{ 0x00, 0x01, 0x10, 0x00, 0x00 };
	BYTE cmdGetUID[] = 			{ 0xFF, 0xCA, 0x00, 0x00, 0x00 };
	
	
	
	rv = SCardEstablishContext(SCARD_SCOPE_SYSTEM, NULL, NULL, &hContext);
	CHECK("SCardEstablishContext", rv)
	
#ifdef SCARD_AUTOALLOCATE
	dwReaders = SCARD_AUTOALLOCATE;
	
	rv = SCardListReaders(hContext, NULL, (LPTSTR)&mszReaders, &dwReaders);
	CHECK("SCardListReaders", rv)
#else
	rv = SCardListReaders(hContext, NULL, NULL, &dwReaders);
	CHECK("SCardListReaders", rv)
	
	mszReaders = calloc(dwReaders, sizeof(char));
	rv = SCardListReaders(hContext, NULL, mszReaders, &dwReaders);
	CHECK("SCardListReaders", rv)
#endif
	printf("reader name: %s\n", mszReaders);
	
	rv = SCardConnect(hContext, mszReaders, SCARD_SHARE_SHARED,
					  SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1, &hCard, &dwActiveProtocol);
	CHECK("SCardConnect", rv)

//#define 	SCARD_CLASS_VENDOR_INFO   1
//#define 	SCARD_ATTR_VALUE(Class, Tag)   ((((ULONG)(Class)) << 16) | ((ULONG)(Tag)))
//#define 	SCARD_ATTR_VENDOR_IFD_SERIAL_NO   SCARD_ATTR_VALUE(SCARD_CLASS_VENDOR_INFO, 0x0103)
//#define 	SCARD_ATTR_VENDOR_IFD_TYPE   SCARD_ATTR_VALUE(SCARD_CLASS_VENDOR_INFO, 0x0101)
//#define 	SCARD_ATTR_VENDOR_IFD_VERSION   SCARD_ATTR_VALUE(SCARD_CLASS_VENDOR_INFO, 0x0102)
//	DWORD len;
//	rv = SCardGetAttrib(hCard, SCARD_ATTR_VENDOR_IFD_SERIAL_NO, nil, &len);
//	BYTE *buf = calloc(1,len);
//	rv = SCardGetAttrib(hCard, SCARD_ATTR_VENDOR_IFD_SERIAL_NO, buf, &len);
	
	switch(dwActiveProtocol)
	{
		case SCARD_PROTOCOL_T0:
			pioSendPci = *SCARD_PCI_T0;
			break;
			
		case SCARD_PROTOCOL_T1:
			pioSendPci = *SCARD_PCI_T1;
			break;
	}
	
	sendAPDU(hCard, pioSendPci, cmdSelectMGR, sizeof(cmdSelectMGR));
	sendAPDU(hCard, pioSendPci, cmdGetConfig, sizeof(cmdGetConfig));	

//	sendAPDU(hCard, pioSendPci, cmdPIVGetSerial, sizeof(cmdPIVGetSerial));

#ifdef SCARD_AUTOALLOCATE
	rv = SCardFreeMemory(hContext, mszReaders);
	CHECK("SCardFreeMemory", rv)
	
#else
	free(mszReaders);
#endif
	
	rv = SCardReleaseContext(hContext);
}

- (NSDictionary*)getAnySingleDevice {
	return self.devices[[[self.devices allKeys] objectAtIndex:0]];
}

- (NSString*) getUniqueStringForDev:(NSDictionary*)dev {
	return [NSString stringWithFormat:@"%@[%@]@0x%08x",
		dev[YubiKeyDeviceDictionaryUSBNameKey],
		dev[YubiKeyDeviceDictionaryUSBSerialNumberKey],
		[dev[YubiKeyDeviceDictionaryUSBLocationKey] intValue]
	];
}

void IOServiceMatchedCallback(void* refcon, io_iterator_t iterator);
- (kern_return_t) registerMatchingCallbacks{
	kern_return_t kr;

	IONotificationPortRef notifyPort = IONotificationPortCreate(kIOMasterPortDefault);
	CFRunLoopSourceRef loopSource = IONotificationPortGetRunLoopSource(notifyPort);
	CFRunLoopRef runLoop = CFRunLoopGetCurrent();
	CFRunLoopAddSource(runLoop, loopSource, kCFRunLoopDefaultMode);

	CFMutableDictionaryRef matchDict = (__bridge_retained CFMutableDictionaryRef)@{
		@kIOProviderClassKey : @"IOUSBHostDevice",//@kIOUSBDeviceClassName,
		@kUSBProductID : @"*",
		@kUSBVendorID : @0x1050
	};

	CFRetain(matchDict);

	io_iterator_t iterator;
	io_service_t usbDevice;

	kr = IOServiceAddMatchingNotification(notifyPort, kIOFirstMatchNotification, matchDict, IOServiceMatchedCallback, (void*)YES, &iterator);
	if(kr!=KERN_SUCCESS) return kr;
	while ((usbDevice=IOIteratorNext(iterator))) {
		CFDictionaryRef dict = GetDeviceInfo(usbDevice);
		if(dict) {
			CFRetain(dict);
			NSLog(@"initial device found:%@",[self getUniqueStringForDev:(__bridge NSDictionary*)dict]);
			[self addDevice:(__bridge_transfer NSDictionary*)(dict)];
		}
	}

	kr = IOServiceAddMatchingNotification(notifyPort, kIOTerminatedNotification, matchDict, IOServiceMatchedCallback, (void*)NO, &iterator);
	if(kr!=KERN_SUCCESS) return kr;
	while ((usbDevice=IOIteratorNext(iterator))) {
		CFDictionaryRef dict = GetDeviceInfo(usbDevice);
		if(dict)
			NSLog(@"device found for termination:%@",[self getUniqueStringForDev:(__bridge NSDictionary*)dict]);
	}
	[[NSRunLoop currentRunLoop] run];
	return KERN_SUCCESS;
}

- (void) addDevice:(NSDictionary*)dev {
	_devices[[self getUniqueStringForDev:dev]] = dev;
	[[NSNotificationCenter defaultCenter] postNotificationName:YubiKeyDeviceManagerKeyInsertedNotificationKey object:self userInfo:dev];
}

- (void) removeDevice:(NSDictionary*)dev {
	[_devices removeObjectForKey:[self getUniqueStringForDev:dev]];
	[[NSNotificationCenter defaultCenter] postNotificationName:YubiKeyDeviceManagerKeyRemovedNotificationKey object:self userInfo:dev];
}

void IOServiceMatchedCallback(void* added, io_iterator_t iterator) {
	io_service_t usbDevice;

	while ((usbDevice=IOIteratorNext(iterator))) {
		CFDictionaryRef dict = GetDeviceInfo(usbDevice);
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

CFDictionaryRef GetDeviceInfo(io_service_t usbDevice) {
	kern_return_t kr;
	CFMutableDictionaryRef devDict = nil;

	io_registry_entry_t child;
	CFMutableDictionaryRef dict = nil;
	kr = IORegistryEntryGetChildEntry(usbDevice, kIOServicePlane, &child);
	kr = IORegistryEntryCreateCFProperties(child, &dict, kCFAllocatorDefault, kNilOptions);

	kr = IORegistryEntryCreateCFProperties(usbDevice, &devDict, kCFAllocatorDefault, kNilOptions);
	if(kr!=KERN_SUCCESS) return nil;

	io_name_t devName;
	IORegistryEntryGetName(usbDevice, devName);
	if(!strstr(devName,"CCID"))
		return nil;
	
	if(!CFDictionaryContainsKey(devDict, CFSTR(kUSBSerialNumberString)))
		CFDictionarySetValue(devDict, CFSTR(kUSBSerialNumberString), CFSTR("unknown"));
	CFDictionarySetValue(devDict, (__bridge_retained CFStringRef)YubiKeyDeviceDictionaryUniqueStringKey,(__bridge CFStringRef)[gSelf getUniqueStringForDev:(__bridge NSDictionary*)devDict]);
	
	IOHIDDeviceRef hid = IOHIDDeviceCreate(kCFAllocatorDefault,usbDevice);
	if(hid) {
		IOReturn r = IOHIDDeviceOpen(hid, kIOHIDOptionsTypeNone);
		r = IOHIDDeviceClose(hid, kIOHIDOptionsTypeNone);
	}
	return devDict;
}

@end

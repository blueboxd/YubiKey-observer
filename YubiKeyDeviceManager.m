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

const NSString* YubiKeyDeviceDictionaryUSBNameKey = @kIOHIDProductKey;
const NSString* YubiKeyDeviceDictionaryUSBSerialNumberKey = @kIOHIDSerialNumberKey;
const NSString* YubiKeyDeviceDictionaryUSBLocationKey = @kIOHIDLocationIDKey;
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

LONG sendAPDU(SCARDHANDLE hCard, SCARD_IO_REQUEST pioSendPci, BYTE apdu[], DWORD size, BYTE **result, DWORD *resultLen) {
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
	if(rv)
		return rv;
	
	printf("response: ");
	for(unsigned int i=0; i<dwRecvLength; i++)
		printf("%02X ", pbRecvBuffer[i]);
	printf("\n");
	if(result) {
		BYTE *res = calloc(dwRecvLength,sizeof(char));
		memcpy(res, pbRecvBuffer, dwRecvLength);
		*result = res;
		*resultLen = dwRecvLength;
	}
	return rv;
}

enum ConfigTags {
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
};

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

- (NSDictionary*) parseTLV:(NSData*)data {
	size_t length = [data length];
	char *buf = calloc(length,sizeof(char));

	[data getBytes:buf];
	if(buf[0]!=(length-3))
		return nil;

	unsigned char sw1 = buf[length-2];
	unsigned char sw2 = buf[length-1];
	if(sw1!=0x90 || sw2!=0x00)
		return nil;

	NSMutableDictionary *dict = [NSMutableDictionary new];
	for(unsigned int i=1; i<length-2;) {
		unsigned char tag = buf[i];
		unsigned char size = buf[i+1];
		char body[256];
		memcpy(body,buf+(i+2),size);
		dict[[NSNumber numberWithInteger:tag]] = [NSData dataWithBytes:body length:size];
		i+=2+size;
	}
	return dict;
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

#define 	SCARD_CLASS_VENDOR_INFO   1
#define 	SCARD_ATTR_VALUE(Class, Tag)   ((((ULONG)(Class)) << 16) | ((ULONG)(Tag)))
#define 	SCARD_ATTR_VENDOR_IFD_SERIAL_NO   SCARD_ATTR_VALUE(SCARD_CLASS_VENDOR_INFO, 0x0103)
#define 	SCARD_ATTR_VENDOR_IFD_TYPE   SCARD_ATTR_VALUE(SCARD_CLASS_VENDOR_INFO, 0x0101)
#define 	SCARD_ATTR_VENDOR_IFD_VERSION   SCARD_ATTR_VALUE(SCARD_CLASS_VENDOR_INFO, 0x0102)
	DWORD len;
	rv = SCardGetAttrib(hCard, SCARD_ATTR_VENDOR_IFD_SERIAL_NO, nil, &len);
	BYTE *buf = calloc(1,len);
	rv = SCardGetAttrib(hCard, SCARD_ATTR_VENDOR_IFD_SERIAL_NO, buf, &len);
	printf("SN#:%s\n",buf);
	
	switch(dwActiveProtocol)
	{
		case SCARD_PROTOCOL_T0:
			pioSendPci = *SCARD_PCI_T0;
			break;
			
		case SCARD_PROTOCOL_T1:
			pioSendPci = *SCARD_PCI_T1;
			break;
	}
	
	char *res;
//	size_t len;
	sendAPDU(hCard, pioSendPci, cmdSelectMGR, sizeof(cmdSelectMGR),nil,nil);
	sendAPDU(hCard, pioSendPci, cmdGetConfig, sizeof(cmdGetConfig),&res,&len);
	NSDictionary *config = [self parseTLV:[NSData dataWithBytes:res length:len]];	

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
		@kIOProviderClassKey : @kIOHIDDeviceKey,//@kIOUSBDeviceClassName,
//		@kIOHIDProductIDKey : @"*",
		@kIOHIDVendorIDKey : @0x1050
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

	kr = IORegistryEntryCreateCFProperties(usbDevice, &devDict, kCFAllocatorDefault, kNilOptions);
	if(kr!=KERN_SUCCESS) return nil;
	NSLog(@"GetDeviceInfo:%@",devDict);
	CFStringRef devName = CFDictionaryGetValue(devDict, CFSTR(kIOHIDProductKey));
	CFRange range = CFStringFind(devName, CFSTR("CCID"), kCFCompareCaseInsensitive);
	if(range.location==kCFNotFound)
		return nil;

	IOHIDDeviceRef hid = IOHIDDeviceCreate(kCFAllocatorDefault,usbDevice);
	if(hid) {
		IOReturn r = IOHIDDeviceOpen(hid, kIOHIDOptionsTypeNone);
		r = IOHIDDeviceClose(hid, kIOHIDOptionsTypeNone);
	}

	
//	io_name_t devName;
//	IORegistryEntryGetName(usbDevice, devName);
//	if(!strstr(devName,"CCID"))
//		return nil;

	if(!CFDictionaryContainsKey(devDict, CFSTR(kIOHIDSerialNumberKey))) {
		CFDictionarySetValue(devDict, CFSTR(kIOHIDSerialNumberKey), CFSTR("unknown"));
	}
	CFDictionarySetValue(devDict, (__bridge_retained CFStringRef)YubiKeyDeviceDictionaryUniqueStringKey,(__bridge CFStringRef)[gSelf getUniqueStringForDev:(__bridge NSDictionary*)devDict]);
	
	return devDict;
}

@end

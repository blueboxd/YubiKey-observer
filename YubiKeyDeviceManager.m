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

- (NSDictionary<NSNumber*,NSData*>*) parseTLV:(NSData*)data {
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

NSString *const YubiKeyDevicePropertySerialKey = @"Serial";
NSString *const YubiKeyDevicePropertyVersionKey = @"Version";
NSString *const YubiKeyDevicePropertyFormfactorKey = @"Formfactor";
NSString *const YubiKeyDevicePropertyModelKey = @"Model";

- (NSDictionary<NSString*,id>*) parseConfig:(NSDictionary<NSNumber*,NSData*>*)dict {
	NSMutableDictionary<NSString*,id> *result = [NSMutableDictionary new];
	for(NSNumber *key in dict) {
		switch((ConfigTags)[key intValue]) {
			case SERIAL:
				NSLog(@"SN#:%@",dict[key]);
				int rawSerial;
				[dict[key] getBytes:&rawSerial];
				result[YubiKeyDevicePropertySerialKey] = [NSNumber numberWithInt:ntohl(rawSerial)];
			break;
			
			case VERSION:
				NSLog(@"Ver#:%@",dict[key]);
				char rawVer;
				[dict[key] getBytes:&rawVer];
				result[YubiKeyDevicePropertyVersionKey] = [NSString stringWithFormat:@"%d.%d.%d",((char*)&rawVer)[0],((char*)&rawVer)[1],((char*)&rawVer)[2]];
			break;
			
			case FORMFACTOR:
				NSLog(@"fctr:%@",dict[key]);
				int rawFactor;
				[dict[key] getBytes:&rawFactor];
				result[YubiKeyDevicePropertyFormfactorKey] = [NSNumber numberWithInt:ntohl(rawFactor)]; 
			break;
		} 
	}
	
	
	
	return result;
}

#define CHECK(f, rv) \
 if (SCARD_S_SUCCESS != rv) \
 { \
  printf(f ": %s\n", pcsc_stringify_error(rv)); \
  return nil; \
 }
- (NSDictionary*)getYubKeyDeviceProperty:(NSNumber*)serial {
	LONG rv;
	
	SCARDCONTEXT hContext;
	LPTSTR mszReaders;
	SCARDHANDLE hCard;
	DWORD dwReaders, dwActiveProtocol;
	SCARD_IO_REQUEST pioSendPci;
	
	BYTE cmdSelectMGR[] =		{ 0x00, 0xA4, 0x04, 0x00, 0x08, 0xA0, 0x00, 0x00, 0x05, 0x27, 0x47, 0x11, 0x17 };
	BYTE cmdGetConfig[] = 		{ 0x00, 0x1d, 0x00, 0x00 };
	
	BYTE cmdSelectPIV[] =		{ 0x00, 0xA4, 0x04, 0x00, 0x05, 0xA0, 0x00, 0x00, 0x03, 0x08 };
	BYTE cmdPIVGetVersion[] = 	{ 0x00, 0xfd, 0x00, 0x00 };
	
	rv = SCardEstablishContext(SCARD_SCOPE_SYSTEM, NULL, NULL, &hContext);
	CHECK("SCardEstablishContext", rv)
	if(rv)return nil;
	rv = SCardListReaders(hContext, NULL, NULL, &dwReaders);
	if(rv)return nil;
	
	mszReaders = calloc(dwReaders, sizeof(char));
	rv = SCardListReaders(hContext, NULL, mszReaders, &dwReaders);
	if(rv)return nil;

	NSMutableArray *readers = [NSMutableArray new];
	char *pos = mszReaders;
	while(*pos) {
		[readers addObject:[NSString stringWithUTF8String:pos]];
		pos += strlen(pos)+1;
	}
	free(mszReaders);

	NSDictionary *result=nil;
	for(NSString*reader in readers)
	{
		NSLog(@"reader: %@", reader);
		
		rv = SCardConnect(hContext, [reader cStringUsingEncoding:NSUTF8StringEncoding], SCARD_SHARE_SHARED, SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1, &hCard, &dwActiveProtocol);
		CHECK("SCardConnect", rv)
		if(rv)return nil;
		
		switch(dwActiveProtocol)
		{
			case SCARD_PROTOCOL_T0:
				pioSendPci = *SCARD_PCI_T0;
				break;
				
			case SCARD_PROTOCOL_T1:
				pioSendPci = *SCARD_PCI_T1;
				break;
		}

		BYTE *res;
		DWORD len;

		sendAPDU(hCard, pioSendPci, cmdSelectMGR, sizeof(cmdSelectMGR),nil,nil);
		sendAPDU(hCard, pioSendPci, cmdGetConfig, sizeof(cmdGetConfig),&res,&len);
		NSDictionary<NSNumber*,NSData*> *config = [self parseTLV:[NSData dataWithBytes:res length:len]];
		NSLog(@"%@",config);
		NSMutableDictionary<NSString*,id> *devInfo = [[self parseConfig:config] mutableCopy];

		if(!devInfo[YubiKeyDevicePropertyVersionKey]) {
			sendAPDU(hCard, pioSendPci, cmdSelectPIV, sizeof(cmdSelectPIV),&res,&len);
			if(res[len-2]==0x90) {
				sendAPDU(hCard, pioSendPci, cmdPIVGetVersion, sizeof(cmdPIVGetVersion),&res,&len);
				if(res[len-2]==0x90)
					devInfo[YubiKeyDevicePropertyVersionKey] = [NSString stringWithFormat:@"%d.%d.%d",res[0],res[1],res[2]];
			}
		}


		if([devInfo[YubiKeyDevicePropertySerialKey] intValue] == [serial intValue]) {
			result = devInfo;
			break;
		}
	}
	
	rv = SCardReleaseContext(hContext);
	return result;
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

NSString *const YubiKeyDeviceDictionaryPropertyKey = @"YubiKeyDeviceDictionaryPropertyKey";
CFDictionaryRef GetDeviceInfo(io_service_t usbDevice) {
	kern_return_t kr;
	CFMutableDictionaryRef devDict = nil;

	kr = IORegistryEntryCreateCFProperties(usbDevice, &devDict, kCFAllocatorDefault, kNilOptions);
	if(kr!=KERN_SUCCESS) return nil;
//	NSLog(@"GetDeviceInfo:%@",devDict);
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
	
	if(CFDictionaryContainsKey(devDict, CFSTR(kIOHIDSerialNumberKey))) {
		CFStringRef version = CFDictionaryGetValue(devDict, CFSTR(kIOHIDSerialNumberKey));
		SInt32 versionNumber = CFStringGetIntValue(version);
		CFDictionaryRemoveValue(devDict, CFSTR(kIOHIDSerialNumberKey));
		CFNumberRef versionNumberRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &versionNumber);
		CFDictionaryAddValue(devDict, CFSTR(kIOHIDSerialNumberKey), versionNumberRef);
		CFDictionaryRef yubikeyProperty = (__bridge_retained CFDictionaryRef)[gSelf getYubKeyDeviceProperty:(__bridge NSNumber*)versionNumberRef];
		CFDictionaryAddValue(devDict, (__bridge CFStringRef)YubiKeyDeviceDictionaryPropertyKey, yubikeyProperty);
	} else {
//		CFDictionarySetValue(devDict, CFSTR(kIOHIDSerialNumberKey), );
	}
	CFDictionarySetValue(devDict, (__bridge_retained CFStringRef)YubiKeyDeviceDictionaryUniqueStringKey,(__bridge CFStringRef)[gSelf getUniqueStringForDev:(__bridge NSDictionary*)devDict]);
	
	
	return devDict;
}

@end

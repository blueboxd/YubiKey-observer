//
//  YubiKey.m
//  YubiKey-observer
//
//  Created by bluebox on 2020/07/21.
//  Copyright © 2020 cx.lab. All rights reserved.
//

#import "YubiKey.h"

NSString *const YubiKeyDeviceDictionaryUSBNameKey = @kIOHIDProductKey;
NSString *const YubiKeyDeviceDictionaryUSBSerialNumberKey = @kIOHIDSerialNumberKey;
NSString *const YubiKeyDeviceDictionaryUSBSerialNumberIntegerKey = @"IntegerSerialNumber";
NSString *const YubiKeyDeviceDictionaryUSBLocationKey = @kIOHIDLocationIDKey;
NSString *const YubiKeyDeviceDictionaryUniqueStringKey = @"UniqueString";

NSString *const YubiKeyDeviceDictionaryPropertyKey = @"YubiKeyDeviceDictionaryPropertyKey";
NSString *const YubiKeyDevicePropertySerialKey = @"Serial";
NSString *const YubiKeyDevicePropertyVersionKey = @"Version";
NSString *const YubiKeyDevicePropertyFormfactorKey = @"Formfactor";
NSString *const YubiKeyDevicePropertyNFCSupportedKey = @"NFCSupported";
NSString *const YubiKeyDevicePropertyNFCEnabledKey = @"NFCEnabled";
NSString *const YubiKeyDevicePropertyUSBSupportedKey = @"USBSupported";
NSString *const YubiKeyDevicePropertyUSBEnabledKey = @"USBEnabled";
NSString *const YubiKeyDevicePropertyModelKey = @"Model";

BYTE cmdSelectMGR[] =		{ 0x00, 0xA4, 0x04, 0x00, 0x08, 0xA0, 0x00, 0x00, 0x05, 0x27, 0x47, 0x11, 0x17 };
BYTE cmdGetConfig[] = 		{ 0x00, 0x1d, 0x00, 0x00 };

BYTE cmdSelectPIV[] =		{ 0x00, 0xA4, 0x04, 0x00, 0x05, 0xA0, 0x00, 0x00, 0x03, 0x08 };
BYTE cmdPIVGetVersion[] = 	{ 0x00, 0xfd, 0x00, 0x00 };

BYTE cmdSelectOTP[] =		{ 0x00, 0xA4, 0x04, 0x00, 0x08, 0xA0, 0x00, 0x00, 0x05, 0x27, 0x20, 0x01, 0x01 };
BYTE cmdOTPGetSerial[] = 	{ 0x00, 0x01, 0x10, 0x00, 0x00 };

@implementation YubiKey {
	NSString *readerName;
//	NSDictionary *dev;
	NSArray * yubiKeyFormfactors;
	
	SCARD_IO_REQUEST *pioSendPci;
	SCARDCONTEXT hContext;
	SCARDHANDLE hCard;
}

#define kUniqueStringFormat @"%@[%@]"

+ (NSString*) getUniqueStringFromIOService:(io_service_t) service {
	kern_return_t kr;
	NSMutableDictionary *dev = nil;
	CFMutableDictionaryRef devDict;
	kr = IORegistryEntryCreateCFProperties(service, &devDict, kCFAllocatorDefault, kNilOptions);
	if(kr!=KERN_SUCCESS) return nil;
	
	dev = (__bridge_transfer NSMutableDictionary*)devDict;
	if(!dev[YubiKeyDeviceDictionaryUSBSerialNumberKey])
		return nil;

	return [NSString stringWithFormat:kUniqueStringFormat,
		dev[YubiKeyDeviceDictionaryUSBNameKey],
		dev[YubiKeyDeviceDictionaryUSBSerialNumberKey]
	];
}

static YubiKey *gSelf;
- (instancetype) initWithIOService:(io_service_t) service {
	self = [super init];
	gSelf = self;
	yubiKeyFormfactors = @[
		@"",
		@"",
		@" Nano",
		@"C",
		@"C Nano",
		@"Ci"
	];
	pioSendPci = nil;
	hContext = nil;
	hCard = nil;

	kern_return_t kr;
	NSMutableDictionary *dev = nil;
	CFMutableDictionaryRef devDict;
	kr = IORegistryEntryCreateCFProperties(service, &devDict, kCFAllocatorDefault, kNilOptions);
	if(kr!=KERN_SUCCESS) return nil;
	
	dev = (__bridge_transfer NSMutableDictionary*)devDict;
	if([dev[@kIOHIDProductKey] rangeOfString:@"CCID"].location==NSNotFound)
		return nil;
	
	if(!dev[YubiKeyDeviceDictionaryUSBSerialNumberKey])
		return nil;
	
	_usbName =  dev[YubiKeyDeviceDictionaryUSBNameKey]; 
	_serial = dev[YubiKeyDeviceDictionaryUSBSerialNumberKey];
	_location = dev[YubiKeyDeviceDictionaryUSBLocationKey];
	[self initCardReaderForSelf];

	NSDictionary *property = [self getYubKeyDevicePropertyForSelf];
	if(!property)
		return nil;

	return self;
}

- (NSString*) getUniqueString {
	return [NSString stringWithFormat:kUniqueStringFormat,
		self.usbName,
		self.serial
//		[self.location intValue]
	];
}

-(LONG) openConnection {
	LONG rv;
	if(!readerName)
		return SCARD_E_UNKNOWN_CARD;
	
	if(!hContext) {
		rv = SCardEstablishContext(SCARD_SCOPE_SYSTEM, NULL, NULL, &hContext);
		if(rv)return rv;
	}
	
	if(!hCard) {
		DWORD dwActiveProtocol;
		rv = SCardConnect(hContext, [readerName cStringUsingEncoding:NSUTF8StringEncoding], SCARD_SHARE_SHARED, SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1, &hCard, &dwActiveProtocol);
		if(rv)return rv;
	}
}

-(LONG) closeConnection {
	LONG rv;
	if(hCard) {
		rv = SCardDisconnect(hCard, SCARD_LEAVE_CARD);
		hCard = nil;
	}
	
	if(hContext) {
		rv = SCardReleaseContext(hContext);
		hContext = nil;
	}
}

-(LONG) sendAPDU:(BYTE*)apdu size:(DWORD)size result:(BYTE **)result resultLength:(DWORD *)resultLen {
	LONG rv;
	DWORD dwRecvLength;
	BYTE pbRecvBuffer[258];
	
//	printf("req: ");
//	for(unsigned int i=0; i<size; i++)
//		printf("%02X ", apdu[i]);
//	printf("\n");

	dwRecvLength = sizeof(pbRecvBuffer);
	rv = SCardTransmit(hCard, pioSendPci, apdu, size,
					   NULL, pbRecvBuffer, &dwRecvLength);
	if(rv) {
		NSLog(@"SCardTransmit:0x%08x",rv);
		return rv;
	}
	
//	printf("res: ");
//	for(unsigned int i=0; i<dwRecvLength; i++)
//		printf("%02X ", pbRecvBuffer[i]);
//	printf("\n");

	if(result) {
		BYTE *res = calloc(dwRecvLength,sizeof(char));
		memcpy(res, pbRecvBuffer, dwRecvLength);
		*result = res;
		*resultLen = dwRecvLength;
	}
	return rv;
}

- (NSDictionary<NSNumber*,NSData*>*) parseTLV:(NSData*)data {
	size_t length = [data length];
	if(!length)
		return nil;
	char *buf;

	buf = [data bytes];
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

- (NSDictionary<NSString*,id>*) parseConfig:(NSDictionary<NSNumber*,NSData*>*)dict {
	NSMutableDictionary<NSString*,id> *result = [NSMutableDictionary new];
	for(NSNumber *key in dict) {
		NSData *curValue = dict[key];
		NSUInteger curLen = [curValue length];
		switch((ConfigTags)[key intValue]) {
			case SERIAL: {
				int rawValue;
				[curValue getBytes:&rawValue];
				result[YubiKeyDevicePropertySerialKey] = [NSNumber numberWithInt:ntohl(rawValue)];
			break;
			}

			case VERSION:{
				uint32_t rawValue;
				[curValue getBytes:&rawValue];
				result[YubiKeyDevicePropertyVersionKey] = [NSString stringWithFormat:@"%d.%d.%d",((char*)&rawValue)[0],((char*)&rawValue)[1],((char*)&rawValue)[2]];
			break;
			}

			case FORMFACTOR:{
				int rawValue;
				[curValue getBytes:&rawValue];
				result[YubiKeyDevicePropertyFormfactorKey] = [NSNumber numberWithInt:(rawValue&0xff)]; 
			break;
			}

			case NFC_SUPPORTED:{
				short rawValue=0;
				[curValue getBytes:&rawValue];
				result[YubiKeyDevicePropertyNFCSupportedKey] = [NSNumber numberWithInt:curLen==1?rawValue:ntohs(rawValue)]; 
			break;
			}

			case NFC_ENABLED:{
				short rawValue=0;
				[curValue getBytes:&rawValue];
				result[YubiKeyDevicePropertyNFCEnabledKey] = [NSNumber numberWithInt:curLen==1?rawValue:ntohs(rawValue)]; 
			break;
			}

			case USB_SUPPORTED:{
				short rawValue=0;
				[curValue getBytes:&rawValue];
				result[YubiKeyDevicePropertyUSBSupportedKey] = [NSNumber numberWithInt:curLen==1?rawValue:ntohs(rawValue)]; 
			break;
			}

			case USB_ENABLED:{
				short rawValue=0;
				[curValue getBytes:&rawValue];
				result[YubiKeyDevicePropertyUSBEnabledKey] = [NSNumber numberWithInt:curLen==1?rawValue:ntohs(rawValue)]; 
			break;
			}
		} 
	}
	return result;
}

- (BOOL)initCardReaderForSelf {
	ULONG rv;
	SCARDCONTEXT lhContext;
	LPTSTR mszReaders;
	SCARDHANDLE lhCard;
	DWORD dwReaders, dwActiveProtocol;
	
	if(readerName)
		return YES;
	
	if(!self.serial)
		return NO;

	rv = SCardEstablishContext(SCARD_SCOPE_SYSTEM, NULL, NULL, &lhContext);
	if(rv)return NO;

	rv = SCardListReaders(lhContext, NULL, NULL, &dwReaders);
	if(rv)return NO;
	
	mszReaders = calloc(dwReaders, sizeof(char));
	rv = SCardListReaders(lhContext, NULL, mszReaders, &dwReaders);
	if(rv)return NO;

	NSMutableArray *readers = [NSMutableArray new];
	char *pos = mszReaders;
	while(*pos) {
		[readers addObject:[NSString stringWithUTF8String:pos]];
		pos += strlen(pos)+1;
	}
	free(mszReaders);
//	NSLog(@"readers found:%@",readers);
	NSString *result=nil;
	for(NSString *reader in readers)
	{
		rv = SCardConnect(lhContext, [reader cStringUsingEncoding:NSUTF8StringEncoding], SCARD_SHARE_SHARED, SCARD_PROTOCOL_T0 | SCARD_PROTOCOL_T1, &lhCard, &dwActiveProtocol);
		if(rv) {
			NSLog(@"SCardConnect:0x%08x",rv);
			break;
		}
		
		switch(dwActiveProtocol)
		{
			case SCARD_PROTOCOL_T0:
				pioSendPci = SCARD_PCI_T0;
				break;
				
			case SCARD_PROTOCOL_T1:
				pioSendPci = SCARD_PCI_T1;
				break;
		}

		BYTE *res;
		DWORD len;
		readerName = reader;
		hCard = lhCard;
		[self sendAPDU:cmdSelectMGR size:sizeof(cmdSelectMGR) result:nil resultLength:nil];
		[self sendAPDU:cmdGetConfig size:sizeof(cmdGetConfig) result:&res resultLength:&len];
		hCard = nil;
		rv = SCardDisconnect(lhCard, SCARD_LEAVE_CARD);
		if(res[len-2]==0x90) {
			uint32_t rawValue;
			NSDictionary *dic = [self parseTLV:[NSData dataWithBytes:res length:len]];
			[dic[[NSNumber numberWithInteger:SERIAL]] getBytes:&rawValue];
			if([self.serial intValue]==ntohl(rawValue))
				result = reader;
		}
	}
	rv = SCardReleaseContext(lhContext);
	readerName = result;
	return YES;
}

- (NSDictionary*)getYubKeyDevicePropertyForSelf {

	NSDictionary *result=nil;
	BYTE *res;
	DWORD len;

	[self openConnection];
	[self sendAPDU:cmdSelectMGR size:sizeof(cmdSelectMGR) result:nil resultLength:nil];
	[self sendAPDU:cmdGetConfig size:sizeof(cmdGetConfig) result:&res resultLength:&len];
	
	NSDictionary<NSNumber*,NSData*> *config = [self parseTLV:[NSData dataWithBytes:res length:len]];
	NSMutableDictionary<NSString*,id> *devInfo = [[self parseConfig:config] mutableCopy];

	if(!devInfo[YubiKeyDevicePropertyVersionKey]) {
		[self sendAPDU:cmdSelectPIV size:sizeof(cmdSelectPIV) result:&res resultLength:&len];
		if(res[len-2]==0x90) {
			[self sendAPDU:cmdPIVGetVersion size:sizeof(cmdPIVGetVersion) result:&res resultLength:&len];
			if(res[len-2]==0x90)
				devInfo[YubiKeyDevicePropertyVersionKey] = [NSString stringWithFormat:@"%d.%d.%d",res[0],res[1],res[2]];
		}
	}
	[self closeConnection];

	NSString *verString = (devInfo[YubiKeyDevicePropertyVersionKey])?[devInfo[YubiKeyDevicePropertyVersionKey] substringToIndex:1]:@"";
	NSMutableString *formString = [yubiKeyFormfactors[[devInfo[YubiKeyDevicePropertyFormfactorKey] intValue]] mutableCopy];

	if([devInfo[YubiKeyDevicePropertyNFCSupportedKey] intValue]!=0)
		[formString appendString:@" NFC"];	

	NSString *modelName = [NSString stringWithFormat:@"YubiKey %@%@", verString, formString];
	devInfo[YubiKeyDevicePropertyModelKey] = modelName;
	_model = modelName;
	result = devInfo;

	return result;
}

- (int8_t) verifyPIN:(NSString*)pin {
	if([pin length]>8)
		return -EINVAL;

	BYTE verifyPINCmd[] = {0x00, 0x20, 0x00, 0x80, 0x08, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff};
	BYTE *res, rawPIN[8];
	DWORD len;
	
	[pin getCString:rawPIN maxLength:8+1 encoding:NSUTF8StringEncoding];
	memcpy(verifyPINCmd+5, rawPIN, [pin length]);

	[self openConnection];
	[self sendAPDU:cmdSelectPIV size:sizeof(cmdSelectPIV) result:nil resultLength:nil];
	[self sendAPDU:verifyPINCmd size:sizeof(verifyPINCmd) result:&res resultLength:&len];
	[self closeConnection];

	if (res[0]==0x90) {
		return kYubiKeyDeviceManagerVerifyPINSuccess;
	} else {
		printf("verifyPINCmd Failed:\n");
		for(unsigned int i=0; i<len; i++)
			printf("%02X ", res[i]);
		printf("\n");

		if (res[0]==0x63 && (res[1]&0xf0)==0xc0)
			return (res[1]&0x0f);
		else if (res[0]==0x69 && (res[1]==0x83))
			return kYubiKeyDeviceManagerVerifyPINBlockedErr;
	}	
	return kYubiKeyDeviceManagerVerifyPINUnknownErr;
}

@end

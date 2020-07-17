//
//  PINManager.m
//  YubiKey-observer
//
//  Created by bluebox on 2020/07/08.
//  Copyright © 2020 cx.lab. All rights reserved.
//

#import "PINManager.h"

static NSString *keychainServiceName;

@implementation PINManager

-(void) awakeFromNib {
	keychainServiceName = [[NSBundle mainBundle] bundleIdentifier];
}

- (NSString*)getPinForKey:(NSString*)key {
	if(![key length]) return nil;
	NSDictionary *query = @{
		(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService:keychainServiceName,
		(__bridge id)kSecAttrAccount:key,
		(__bridge id)kSecReturnData:@YES,
	};
	
	CFDataRef result=nil;
	OSStatus err = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef)&result);
	if(err) {
		CFStringRef description = SecCopyErrorMessageString(err, nil);
		NSLog(@"err:%d (%@)",err,description);
		CFRelease(description);
		return nil;
	}
	NSString *passwd = [[NSString alloc] initWithData:(__bridge NSData*)result encoding:NSUTF8StringEncoding];
	return passwd;
}

- (OSStatus)removePinForKey:(NSString*)key {
	if(![key length]) return paramErr;
	NSDictionary *query = @{
		(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService:keychainServiceName,
		(__bridge id)kSecAttrAccount:key,
	};

	OSStatus err = SecItemDelete((__bridge CFDictionaryRef)query);
	if(err) {
		CFStringRef description = SecCopyErrorMessageString(err, nil);
		NSLog(@"err:%d (%@)",err,description);
		CFRelease(description);
		return err;
	}
	return err;
}

- (OSStatus)storePin:(NSString*)pin forKey:(NSString*)key withLabel:(NSString*)label{
	if(![key length]) return paramErr;
	OSStatus err = noErr;
	NSMutableDictionary *query = [@{
		(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService:keychainServiceName,
		(__bridge id)kSecAttrAccount:key,
		(__bridge id)kSecValueData:[pin dataUsingEncoding:NSUTF8StringEncoding],
		(__bridge id)kSecAttrLabel:label,
	} mutableCopy];

	err = SecItemAdd((__bridge CFDictionaryRef)query, nil);
	if(err == errSecDuplicateItem) {
		NSDictionary *changes = @{
			(__bridge id)kSecValueData:[pin dataUsingEncoding:NSUTF8StringEncoding],
		};
		[query removeObjectForKey:(__bridge id)kSecValueData];
		[query removeObjectForKey:(__bridge id)kSecAttrLabel];
		err = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)changes);
	}
	return err;
}

- (void)dump {
	NSDictionary *query = @{
		(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService:keychainServiceName,
		(__bridge id)kSecReturnAttributes:@YES,		
		(__bridge id)kSecMatchLimit:(__bridge id)kSecMatchLimitAll,
	};
	
	CFTypeRef result=nil;
	OSStatus err = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef)&result);
	NSLog(@"%@",(CFArrayRef)result);
}

@end

//
//  SSHKeyManager.m
//  YubiKey-observer
//
//  Created by bluebox on 2020/07/08.
//  Copyright © 2020 cx.lab. All rights reserved.
//

#import "SSHKeyManager.h"

#include <sys/un.h>
#include <sys/socket.h>
#include <fcntl.h>

#include "openssh/authfd.h"
#include "openssh/sshkey.h"
#include "openssh/digest.h"
#include "openssh/ssherr.h"

NSString* const SSHKeyManagerSSHKeyDictionaryHashKey = @"hash";
NSString* const SSHKeyManagerSSHKeyDictionaryNameKey = @"name";
NSString* const SSHKeyManagerSSHKeyDictionaryAlgoKey = @"algo";
NSString* const SSHKeyManagerSSHKeyDictionaryBitsKey = @"bits";
NSString* const SSHKeyManagerSSHKeyDictionaryOursKey = @"ours";

NSNotificationName SSHKeyManagerKeyStoreDidChangeNotificationKey = @"SSHKeyManagerKeyStoreDidChangeNotificationKey";
NSNotificationName SSHKeyManagerCommandFailedNotificationKey = @"SSHKeyManagerCommandFailedNotificationKey";
NSString* const SSHKeyManagerCommandFailedActionKey = @"action";
NSString* const SSHKeyManagerCommandFailedActionAddKey = @"add";
NSString* const SSHKeyManagerCommandFailedActionRemoveKey = @"remove";
NSString* const SSHKeyManagerCommandFailedErrorKey = @"err";
NSString* const SSHKeyManagerCommandFailedStdErrStrKey = @"stderrstr";

@interface SSHKeyManager()

@end

@implementation SSHKeyManager {
	NSTimer *refreshTimer;
	NSDictionary *curKeys;
}

- (instancetype)init {
	self = [super init];
	curKeys = @{};
	return self;
}

- (instancetype)initWithProvider:(NSString*)provider {
	NSLog(@"%@::%@%@",NSStringFromClass([self class]),NSStringFromSelector(_cmd),provider);
	self = [super init];
	curKeys = @{};
	self.provider = provider;
	return self;

}

- (void)dealloc {
	NSLog(@"%@::%@",NSStringFromClass([self class]),NSStringFromSelector(_cmd));
	[refreshTimer invalidate];
}

- (void) setProvider:(NSString *)provider {
	_provider = provider;
	[self rebuildKeyStore];
}

-(void) setFpDigest:(NSUInteger)fpDigest {
	_fpDigest = fpDigest;
	[self rebuildKeyStore];
}

-(void) setFpRepresentation:(NSUInteger)fpRepresentation {
	_fpRepresentation = fpRepresentation;
	[self rebuildKeyStore];
}

- (void)startObserver {
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		self->refreshTimer = [NSTimer timerWithTimeInterval:5 target:self selector:@selector(refreshKeyStore) userInfo:nil repeats:YES];
		[[NSRunLoop currentRunLoop] addTimer:self->refreshTimer forMode:NSDefaultRunLoopMode];
		[[NSRunLoop currentRunLoop] run];
	});
}

- (BOOL) isDifferent:(NSDictionary*)newKeys from:(NSDictionary*)curKeys {
	if([newKeys count]!=[curKeys count])
		return YES;

	for (NSString *key in newKeys) {
		if(!curKeys[key])
			return YES;
	}
	return NO;
}

- (void) rebuildKeyStore {
	curKeys = @{};
	[self refreshKeyStore];
}

- (void) refreshKeyStore {
	NSDictionary *newKeys = [self listIdentities];
	if([self isDifferent:newKeys from:curKeys]) {
		[[NSNotificationCenter defaultCenter] postNotificationName:SSHKeyManagerKeyStoreDidChangeNotificationKey object:self userInfo:@{@"keys":newKeys}];
	}
	curKeys = newKeys;
}

- (BOOL) hasOurKey {
	NSDictionary *sshKeys = [self listIdentities];
	for (NSString *key in sshKeys) {
		if([sshKeys[key][SSHKeyManagerSSHKeyDictionaryOursKey] intValue])
			return YES;
	}
	return NO;
}

- (NSDictionary*) listIdentities {
	if(!self.provider)
		return nil;

	int sock;
	ssh_get_authentication_socket(&sock);
	
	struct ssh_identitylist *idlist;
	char *fp;
	int r = ssh_fetch_identitylist(sock, &idlist);
	if(r)
		return @{};

	NSMutableDictionary *dict = [NSMutableDictionary new];
	for (size_t i = 0; i < idlist->nkeys; i++) {
		struct sshkey *k = idlist->keys[i];

		fp = sshkey_fingerprint(k, self.fpDigest, self.fpRepresentation);		
		NSString *fingerprint = [NSString stringWithCString:fp encoding:NSUTF8StringEncoding];
		NSString *comment = [NSString stringWithCString:idlist->comments[i] encoding:NSUTF8StringEncoding];
		NSString *keyType = [NSString stringWithCString:sshkey_type(k) encoding:NSUTF8StringEncoding];
		NSNumber *keySize = [NSNumber numberWithInt:sshkey_size(k)];

		NSString *pkcsPath = self.provider;
		NSString *pkcsRealPath = [pkcsPath stringByResolvingSymlinksInPath];
		NSNumber *ours = @NO;
		
		if([comment isEqualToString:pkcsPath] || [comment isEqualToString:pkcsRealPath])
			ours = @YES;

		dict[fingerprint] = @{
			SSHKeyManagerSSHKeyDictionaryNameKey:comment,
			SSHKeyManagerSSHKeyDictionaryBitsKey:keySize,
			SSHKeyManagerSSHKeyDictionaryHashKey:fingerprint,
			SSHKeyManagerSSHKeyDictionaryAlgoKey:keyType,
			SSHKeyManagerSSHKeyDictionaryOursKey:ours,
		};
		
		free(fp);
	}
	close(sock);
	ssh_free_identitylist(idlist);
	return dict;
}

- (NSError* _Nullable) updateCardAdd:(BOOL)add pin:(NSString* _Nullable)pin {
	int sock;
	ssh_get_authentication_socket(&sock);
		
	u_int lifetime = 0;
	bool confirm = 0;
	if(!pin)
		pin = @"";
	int r = ssh_update_card(sock, add, [self.provider cStringUsingEncoding:NSUTF8StringEncoding],
					 [pin cStringUsingEncoding:NSUTF8StringEncoding], lifetime, confirm);
	close(sock);
	unsigned char *buf = (unsigned char *)CFStringGetCStringPtr((CFStringRef)pin, CFStringGetSystemEncoding());
	if(buf)
		memset(buf, 0, [pin length]);
	pin = nil;
	if(r) {
		NSString *action = add?@"Add ssh-key failed":@"Remove ssh-key failed";
		NSError *err = [NSError errorWithDomain:NSPOSIXErrorDomain code:r userInfo:@{NSLocalizedDescriptionKey:action,NSLocalizedFailureReasonErrorKey:[NSString stringWithCString:ssh_err(r) encoding:NSUTF8StringEncoding]}];
		[[NSNotificationCenter defaultCenter] postNotificationName:SSHKeyManagerCommandFailedNotificationKey object:self 
			userInfo:@{
				SSHKeyManagerCommandFailedActionKey:add?SSHKeyManagerCommandFailedActionAddKey:SSHKeyManagerCommandFailedActionRemoveKey,
				SSHKeyManagerCommandFailedErrorKey:err,
//				SSHKeyManagerCommandFailedStdErrStrKey:[exc stderrStr]
			}
		 ];
		NSLog(@"%@",err);
		return err;
	}
	[self refreshKeyStore];
	return nil;
}

@end

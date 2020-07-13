//
//  SSHKeyManager.m
//  YubiKey-observer
//
//  Created by bluebox on 2020/07/08.
//  Copyright © 2020 cx.lab. All rights reserved.
//

#import "SSHKeyManager.h"
#import "SystemCommandExecutor.h"
#import "PrefKeys.h"

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
	IBOutlet NSUserDefaultsController *prefsController;
	NSTimer *refreshTimer;
	NSDictionary *curKeys;
}

- (void)awakeFromNib {
	curKeys = @{};
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		[self startTimer];
	});
}

- (void)startTimer {
	refreshTimer = [NSTimer timerWithTimeInterval:5 target:self selector:@selector(refreshKeyStore) userInfo:nil repeats:YES];
	[[NSRunLoop currentRunLoop] addTimer:refreshTimer forMode:NSDefaultRunLoopMode];
	[[NSRunLoop currentRunLoop] run];
}

- (BOOL) isDifferent:(NSDictionary*)newKeys withCurrent:(NSDictionary*)curKeys {
	if([newKeys count]!=[curKeys count])
		return YES;

	for (NSString *key in newKeys) {
		if(!curKeys[key])
			return YES;
	}
	return NO;
}

- (void) refreshKeyStore {
	NSDictionary *newKeys = [self listIdentities];
	if([self isDifferent:newKeys withCurrent:curKeys]) {
		[[NSNotificationCenter defaultCenter] postNotificationName:SSHKeyManagerKeyStoreDidChangeNotificationKey object:self userInfo:@{@"keys":newKeys}];
	}
	curKeys = newKeys;
}

- (int32_t) addSSHKeyWithPin:(NSString*)pin {
	NSArray *args = @[
		@"-s",
		[[self->prefsController values] valueForKey:kPKCSPathKey],
	];

	NSArray *stdinArgs = @[
		pin,
		@"\n"
	];

	uint32_t result;
	SystemCommandExecutor *exc = [SystemCommandExecutor initWithCmd:[[self->prefsController values] valueForKey:kSSHAddPathKey] withArgs:args withStdIn:stdinArgs];
	result = [exc execute];
	if(result) {
		[[NSNotificationCenter defaultCenter] postNotificationName:SSHKeyManagerCommandFailedNotificationKey object:self 
			userInfo:@{
				SSHKeyManagerCommandFailedActionKey:SSHKeyManagerCommandFailedActionAddKey,
				SSHKeyManagerCommandFailedErrorKey:[NSError errorWithDomain:NSPOSIXErrorDomain code:result userInfo:nil],
				SSHKeyManagerCommandFailedStdErrStrKey:[exc stderrStr]
			}
		 ];
		 NSLog(@"%@",[exc stderrStr]);
	} else
		[self refreshKeyStore]; 
	return result;
}

- (int32_t) removeSSHKey {
	NSArray *args = @[
		@"-e",
		[[self->prefsController values] valueForKey:kPKCSPathKey],
	];

	uint32_t result;
	SystemCommandExecutor *exc = [SystemCommandExecutor initWithCmd:[[self->prefsController values] valueForKey:kSSHAddPathKey] withArgs:args withStdIn:nil];
	result = [exc execute];
	if(result)
		[[NSNotificationCenter defaultCenter] postNotificationName:SSHKeyManagerCommandFailedNotificationKey object:self 
			userInfo:@{
				SSHKeyManagerCommandFailedActionKey:SSHKeyManagerCommandFailedActionRemoveKey,
				SSHKeyManagerCommandFailedErrorKey:[NSError errorWithDomain:NSPOSIXErrorDomain code:result userInfo:nil],
				SSHKeyManagerCommandFailedStdErrStrKey:[exc stderrStr]
			}
		];
	else
		[self refreshKeyStore]; 
	return result;
}

- (NSDictionary*) enumerateSSHKeys {
	int32_t result;
	NSArray *args = @[
	  @"-l",
	  @"-E",
	  @"md5"
	];
	SystemCommandExecutor *exc = [SystemCommandExecutor initWithCmd:[[self->prefsController values] valueForKey:kSSHAddPathKey] withArgs:args withStdIn:nil];
	result = [exc execute];
	if(result)
		return @{};
	
	NSArray *lines = [exc.stdoutStr componentsSeparatedByString:@"\n"];
	NSMutableDictionary *keys = [NSMutableDictionary new];
	for (NSString *line in lines) {
		if(![line length])continue;
		NSArray *elements = [line componentsSeparatedByString:@" "];
		NSString *pkcsPath = [[self->prefsController values] valueForKey:kPKCSPathKey];
		NSString *pkcsRealPath = [pkcsPath stringByResolvingSymlinksInPath];
		NSNumber *ours = @NO;
		NSString *keyID = elements[2];
		NSString *hash = elements[1];
		
		if([keyID isEqualToString:pkcsPath] || [keyID isEqualToString:pkcsRealPath])
			ours = @YES;

		keys[hash] = @{
			SSHKeyManagerSSHKeyDictionaryNameKey:keyID,
			SSHKeyManagerSSHKeyDictionaryBitsKey:elements[0],
			SSHKeyManagerSSHKeyDictionaryHashKey:hash,
			SSHKeyManagerSSHKeyDictionaryAlgoKey:[elements[3] substringWithRange:NSMakeRange(1, ([elements[3] length]-2))],
			SSHKeyManagerSSHKeyDictionaryOursKey:ours,
		};
	}
	return keys;
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
//	char *authsocket = getenv("SSH_AUTH_SOCK");
//
//	int sock, oerrno;
//	struct sockaddr_un sunaddr;
//
//	memset(&sunaddr, 0, sizeof(sunaddr));
//	sunaddr.sun_family = AF_UNIX;
//	strlcpy(sunaddr.sun_path, authsocket, sizeof(sunaddr.sun_path));
//	if ((sock = socket(AF_UNIX, SOCK_STREAM, 0)) == -1)
//		return @{};
//
//	/* close on exec */
//	if (fcntl(sock, F_SETFD, FD_CLOEXEC) == -1 ||
//		connect(sock, (struct sockaddr *)&sunaddr, sizeof(sunaddr)) == -1) {
//		oerrno = errno;
//		close(sock);
//		errno = oerrno;
//		return @{};
//	}
	
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

		fp = sshkey_fingerprint(k, SSH_FP_HASH_DEFAULT, SSH_FP_HEX);
//		NSLog(@"%s",fp);

//		u_char *blob = NULL;
//		size_t blob_len = 0;
//		r = sshkey_to_blob(k, &blob, &blob_len);
//		NSData *rawKey = [NSData dataWithBytes:blob length:blob_len];
//		NSLog(@"%@",[rawKey description]);
		
//		char * name,*name_plain;
//		name = sshkey_ssh_name(k);
//		name_plain = sshkey_ssh_name_plain(k);
		
		NSString *fingerprint = [NSString stringWithCString:fp encoding:NSUTF8StringEncoding];
		NSString *comment = [NSString stringWithCString:idlist->comments[i] encoding:NSUTF8StringEncoding];
		NSString *keyType = [NSString stringWithCString:sshkey_type(k) encoding:NSUTF8StringEncoding];
		NSNumber *keySize = [NSNumber numberWithInt:sshkey_size(k)];

		NSString *pkcsPath = [[self->prefsController values] valueForKey:kPKCSPathKey];
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

- (NSError* _Nullable) updateCardWithProvider:(NSString*)provider add:(BOOL)add pin:(NSString* _Nullable)pin {
	int sock;
	ssh_get_authentication_socket(&sock);
		
	u_int lifetime = 0;
	bool confirm = 0;
	if(!pin)
		pin = @"";
	int r = ssh_update_card(sock, add, [provider cStringUsingEncoding:NSUTF8StringEncoding],
					 [pin cStringUsingEncoding:NSUTF8StringEncoding], lifetime, confirm);
	if(r) {
		NSError *err = [NSError errorWithDomain:NSPOSIXErrorDomain code:r userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithCString:ssh_err(r) encoding:NSUTF8StringEncoding]}];
		[[NSNotificationCenter defaultCenter] postNotificationName:SSHKeyManagerCommandFailedNotificationKey object:self 
			userInfo:@{
				SSHKeyManagerCommandFailedActionKey:add?SSHKeyManagerCommandFailedActionAddKey:SSHKeyManagerCommandFailedActionRemoveKey,
				SSHKeyManagerCommandFailedErrorKey:err,
//				SSHKeyManagerCommandFailedStdErrStrKey:[exc stderrStr]
			}
		 ];
	
		return err;
	}
	return nil;
}

@end

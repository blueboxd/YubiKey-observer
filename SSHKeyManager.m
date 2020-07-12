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
	BOOL diff = NO;
	if([newKeys count]!=[curKeys count])
		return YES;

	for (NSString *key in newKeys) {
		if(!curKeys[key])
			return YES;
	}
	return NO;
}

- (void) refreshKeyStore {
	NSMutableDictionary *newKeys = [[self enumerateSSHKeys] mutableCopy];
	if([self isDifferent:newKeys withCurrent:curKeys]) {
		[[NSNotificationCenter defaultCenter] postNotificationName:SSHKeyManagerKeyStoreDidChangeNotificationKey object:self userInfo:@{@"keys":[self enumerateSSHKeys]}];
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
	NSDictionary *sshKeys = [self enumerateSSHKeys];
	for (NSString *key in sshKeys) {
		if([sshKeys[key][SSHKeyManagerSSHKeyDictionaryOursKey] intValue])
			return YES;
	}
	return NO;
}

@end

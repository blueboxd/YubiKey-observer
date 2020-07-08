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

@implementation SSHKeyManager

- (int32_t) addSSHKeyWithPin:(NSString*)pin {
	NSLog(@"will ssh-add -s");
	
	NSArray *args = @[
		@"-s",
		[[self.prefsController values] valueForKey:kPKCSPathKey],
	];

	NSArray *stdinArgs = @[
		pin,
		@"\n"
	];

	usleep(500000);

	uint32_t result;
	SystemCommandExecutor *exc = [SystemCommandExecutor initWithCmd:[[self.prefsController values] valueForKey:kSSHAddPathKey] withArgs:args withStdIn:stdinArgs];
	result = [exc execute];
//	if (!result) {
//		statusItem.image = [NSImage imageNamed:@"yubikey-ok"];
//		[self.addKeyMenuItem setHidden:YES];
//		[self.removeKeyMenuItem setHidden:NO];
//	} else {
//		statusItem.image = [NSImage imageNamed:@"yubikey-ng"];
//	}
//	
//	NSArray *keys = [self enumerateSSHKeys];
//	[self updateSSHKeysMenu:keys];
	return result;
}

- (int32_t) removeSSHKey {
	NSLog(@"will ssh-add -e");
	NSArray *args = @[
		@"-e",
		[[self.prefsController values] valueForKey:kPKCSPathKey],
	];

	uint32_t result;
	SystemCommandExecutor *exc = [SystemCommandExecutor initWithCmd:[[self.prefsController values] valueForKey:kSSHAddPathKey] withArgs:args withStdIn:nil];
	result = [exc execute];
//	if(!result) {
//		statusItem.image = [NSImage imageNamed:@"yubikey-c"];
//		[self.addKeyMenuItem setHidden:NO];
//		[self.removeKeyMenuItem setHidden:YES];
//	}
//	NSArray *keys = [self enumerateSSHKeys];
//	[self updateSSHKeysMenu:keys];
	return result;
}

- (NSArray*) enumerateSSHKeys {
	int32_t result;
	NSArray *args = @[
	  @"-l",
	  @"-E",
	  @"md5"
	];
	SystemCommandExecutor *exc = [SystemCommandExecutor initWithCmd:[[self.prefsController values] valueForKey:kSSHAddPathKey] withArgs:args withStdIn:nil];
	result = [exc execute];
	if(result)
		return nil;
	
	NSArray *lines = [exc.stdoutStr componentsSeparatedByString:@"\n"];
	NSMutableArray *keys = [NSMutableArray new];
	for (NSString *line in lines) {
		if(![line length])continue;
		NSArray *elements = [line componentsSeparatedByString:@" "];
		NSString *pkcsPath = [[self.prefsController values] valueForKey:kPKCSPathKey];
		NSString *pkcsRealPath = [pkcsPath stringByResolvingSymlinksInPath];
		NSNumber *ours = @NO;
		NSString *keyID = elements[2];
		
		if([keyID isEqualToString:pkcsPath] || [keyID isEqualToString:pkcsRealPath])
			ours = @YES;

		[keys addObject:@{
			sshKeyID:keyID,
			sshKeyBits:elements[0],
			sshKeyHash:elements[1],
			sshKeyAlgo:[elements[3] substringWithRange:NSMakeRange(1, ([elements[3] length]-2))],
			sshKeyOurs:ours,
		}];
	}
	NSLog(@"%@",keys);
	return keys;
}

- (BOOL) isSSHKeyFomYubiKeyAdded {
	NSArray *keys = [self enumerateSSHKeys];
	for (NSDictionary *key in keys) {
		if([key[sshKeyOurs] intValue])
			return YES;
	}
	return NO;
}


@end

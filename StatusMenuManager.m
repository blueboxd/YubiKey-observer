//
//  StatusMenuIconManager.m
//  YubiKey-observer
//
//  Created by bluebox on 2020/07/09.
//  Copyright © 2020 cx.lab. All rights reserved.
//

#import "StatusMenuManager.h"
#import "YubiKeyDeviceManager.h"
#import "SSHKeyManager.h"


#define kStateNone			@"yubikey"
#define kStateInserted		@"yubikey-c"
#define kStateKeyImported	@"yubikey-ok"
#define kStateError			@"yubikey-ng"


@implementation StatusMenuManager {
	NSDictionary<NSString*,NSImage*> *statusIcons;
	IBOutlet YubiKeyDeviceManager *yubikeyDeviceManager;
	IBOutlet SSHKeyManager *sshKeyManager;
}

-(void) awakeFromNib {
	statusIcons = @{
		kStateNone			:	[NSImage imageNamed:kStateNone],
		kStateInserted		:	[NSImage imageNamed:kStateInserted],
		kStateKeyImported	:	[NSImage imageNamed:kStateKeyImported],
		kStateError			:	[NSImage imageNamed:kStateError],
	};
	self.menuIcon = statusIcons[kStateNone];
	[yubikeyDeviceManager addObserver:self forKeyPath:@"isYubiKeyInserted" options:NSKeyValueObservingOptionNew context:nil];
	[sshKeyManager addObserver:self forKeyPath:@"isSSHKeyFomYubiKeyAdded" options:NSKeyValueObservingOptionNew context:nil];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {

	if(yubikeyDeviceManager.isYubiKeyInserted) {
		if(sshKeyManager.isSSHKeyFomYubiKeyAdded)
			self.menuIcon = statusIcons[kStateKeyImported];
		else
			self.menuIcon = statusIcons[kStateInserted];
	} else {
		self.menuIcon = statusIcons[kStateNone];
	}
}

@end

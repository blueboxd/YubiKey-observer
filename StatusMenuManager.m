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
#import "YubiKey.h"

#define kStateNone			@"yubikey"
#define kStateInserted		@"yubikey-c"
#define kStateKeyImported	@"yubikey-ok"
#define kStateError			@"yubikey-ng"

@interface StatusMenuManager()
@property BOOL deviceInserted;
@property BOOL keyAdded;
@property BOOL addCmdFailed;
@end

@implementation StatusMenuManager {
IBOutlet	NSMenu *yubikeysSubMenu;
IBOutlet	NSMenu *sshkeysSubMenu;
IBOutlet	NSMenu *statusMenu;
			NSStatusItem *statusItem;
			NSDictionary<NSString*,NSImage*> *statusIcons;
			NSMutableDictionary<NSString*, NSMenuItem*> *yubikeyMenuItemArray;
}

-(void) awakeFromNib {
//	NSLog(@"%@:%@",NSStringFromClass([self class]),NSStringFromSelector(_cmd));
	self.deviceInserted = NO;
	self.keyAdded = NO;
	self.addCmdFailed = NO;
	
	statusIcons = @{
		kStateNone			:	[NSImage imageNamed:kStateNone],
		kStateInserted		:	[NSImage imageNamed:kStateInserted],
		kStateKeyImported	:	[NSImage imageNamed:kStateKeyImported],
		kStateError			:	[NSImage imageNamed:kStateError],
	};
	
	yubikeyMenuItemArray = [NSMutableDictionary<NSString*, NSMenuItem*> new];

	statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
	statusItem.menu = statusMenu;
	statusItem.highlightMode = YES;
	statusItem.image = [NSImage imageNamed:@"yubikey"];
	[statusItem bind:NSImageBinding toObject:self withKeyPath:@"self.menuIcon" options:nil];

	self.menuIcon = statusIcons[kStateNone];
	[self addObserver:self forKeyPath:@"deviceInserted" options:NSKeyValueObservingOptionNew context:nil];
	[self addObserver:self forKeyPath:@"keyAdded" options:NSKeyValueObservingOptionNew context:nil];
	[self addObserver:self forKeyPath:@"addCmdFailed" options:NSKeyValueObservingOptionNew context:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceAdded:) name:YubiKeyDeviceManagerKeyInsertedNotificationKey object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceRemoved:) name:YubiKeyDeviceManagerKeyRemovedNotificationKey object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyStoreModified:) name:SSHKeyManagerKeyStoreDidChangeNotificationKey object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sshAddFailed:) name:SSHKeyManagerCommandFailedNotificationKey object:nil];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	if(self.deviceInserted) {
		if(self.keyAdded) {
			self.menuIcon = statusIcons[kStateKeyImported];
		} else {
			if(self.addCmdFailed)
				self.menuIcon = statusIcons[kStateError];
			else
				self.menuIcon = statusIcons[kStateInserted];
		}
	} else {
		self.menuIcon = statusIcons[kStateNone];
	}
}

- (void) deviceAdded:(NSNotification*)notification {
	YubiKey *yubikey = notification.userInfo;
	self.deviceInserted = YES;
	NSString *newKeyString = [NSString stringWithFormat:@"%@\n\t[SN#%@] @ %08x",yubikey.model,yubikey.serial,[yubikey.location intValue]];
	NSMenuItem *newMenuItem = [[NSMenuItem alloc] initWithTitle:newKeyString action:nil keyEquivalent:@""];
	NSDictionary *attributes = @{
		NSFontAttributeName: [NSFont userFixedPitchFontOfSize:[NSFont smallSystemFontSize]],
	};
	NSAttributedString *attributedTitle = [[NSAttributedString alloc] initWithString:[newMenuItem title] attributes:attributes];
	newMenuItem.attributedTitle = attributedTitle;
	newMenuItem.enabled = YES;
	
	NSMenu *deviceSubmenu = [[NSMenu alloc] initWithTitle:@"Device Submenu"];
	deviceSubmenu.autoenablesItems = YES;
	[deviceSubmenu addItemWithTitle:@"Verify PIN" action:@selector(verifyPINAction:) keyEquivalent:@""].tag = (NSInteger)yubikey;
	[deviceSubmenu addItemWithTitle:@"Forget PIN" action:@selector(forgetPINAction:) keyEquivalent:@""].tag = (NSInteger)yubikey;
	newMenuItem.submenu = deviceSubmenu;
	
	self->yubikeyMenuItemArray[[yubikey getUniqueString]] = newMenuItem;
	[self->yubikeysSubMenu addItem:newMenuItem];
}

- (void) deviceRemoved:(NSNotification*)notification {
	NSDictionary *dev = notification.userInfo;
	NSString *devID = dev[YubiKeyDeviceDictionaryUniqueStringKey];
	NSMenuItem *targetMenuItem = yubikeyMenuItemArray[devID];
	if(targetMenuItem) {
		[yubikeyMenuItemArray removeObjectForKey:devID];
		[yubikeysSubMenu removeItem:targetMenuItem];
	}
	
	if(![yubikeyMenuItemArray count])
		self.deviceInserted = NO;

}

- (void) keyStoreModified:(NSNotification*)notification {
	NSDictionary *sshKeys = notification.userInfo[@"keys"];
	[sshkeysSubMenu removeAllItems];
	self.keyAdded = NO;
	for (NSString *key in sshKeys) {
		NSDictionary *curSSHKey = sshKeys[key];
		NSString *newKeyString = [NSString stringWithFormat:@"%@\n\t%@\n\t %@/%@bit",curSSHKey[SSHKeyManagerSSHKeyDictionaryHashKey],curSSHKey[SSHKeyManagerSSHKeyDictionaryNameKey],curSSHKey[SSHKeyManagerSSHKeyDictionaryAlgoKey],curSSHKey[SSHKeyManagerSSHKeyDictionaryBitsKey]];
		NSMenuItem *newMenuItem = [[NSMenuItem alloc] initWithTitle:newKeyString action:nil keyEquivalent:@""];
		NSDictionary *attributes = @{
			NSFontAttributeName: [NSFont userFixedPitchFontOfSize:[NSFont smallSystemFontSize]],
		};
		NSAttributedString *attributedTitle = [[NSAttributedString alloc] initWithString:[newMenuItem title] attributes:attributes];
		newMenuItem.attributedTitle = attributedTitle;
		newMenuItem.enabled = NO;
		
		if([curSSHKey[SSHKeyManagerSSHKeyDictionaryOursKey] intValue]) {
			newMenuItem.onStateImage = [NSImage imageNamed:@"yubikey-c"];
			newMenuItem.state = NSOnState;
			newMenuItem.enabled = YES;
			
			self.keyAdded = YES;
			self.addCmdFailed = NO;
		}
		[sshkeysSubMenu addItem:newMenuItem];
	}
}

- (void) sshAddFailed:(NSNotification*)notification {
	if(notification.userInfo[SSHKeyManagerCommandFailedActionKey]==SSHKeyManagerCommandFailedActionAddKey)
		self.addCmdFailed = YES;
}

@end

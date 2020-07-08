//
//  YubiKey_observerAppDelegate.m
//  YubiKey-observer
//
//  Created by bluebox on 18/10/27.
//  Copyright 2018 __MyCompanyName__. All rights reserved.
//

#import "YubiKey_observerAppDelegate.h"
#import "YubiKeyDeviceManager.h"
#import "SSHKeyManager.h"
#import "PINManager.h"
#import "PrefKeys.h"

#include <IOKit/IOKitLib.h>
#include <IOKit/IOMessage.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <IOKit/pwr_mgt/IOPMLib.h>

#define sshKeyID @"id"
#define sshKeyBits @"bits"
#define sshKeyHash @"hash"
#define sshKeyAlgo @"algo"
#define sshKeyOurs @"ours"

@interface YubiKey_observerAppDelegate() {
}

@property (strong) IBOutlet NSUserDefaultsController *prefsController;

@property (strong) IBOutlet NSWindow *pinDialog;
@property (nonatomic) IBOutlet NSButton *rememberPINCheckbox;
@property (nonatomic) IBOutlet NSTextField * pinTextField;
@property (nonatomic) IBOutlet NSString *pinText;
@property (nonatomic) IBOutlet NSTextField *keyIDLabel;

@property (strong) IBOutlet NSWindow *prefWindow;

@property (strong) IBOutlet NSMenu *statusMenu;
@property (strong) IBOutlet NSMenu *yubikeysSubMenu;
@property (strong) IBOutlet NSMenu *sshkeysSubMenu;

@property (strong) IBOutlet NSMenuItem *addKeyMenuItem;
@property (strong) IBOutlet NSMenuItem *removeKeyMenuItem;

@property IBOutlet YubiKeyDeviceManager *yubikeyDeviceManager;
@property IBOutlet SSHKeyManager *sshKeyManager;
@property IBOutlet PINManager *pinManager;

- (IBAction) confirmButtonAction:(id)sender;
- (IBAction) cancelButtonAction:(id)sender;

- (IBAction) forgetPINAction:(id)sender;

- (IBAction) preferenceAction:(id)sender;
- (IBAction) quitAction:(id)sender;

@end

@implementation YubiKey_observerAppDelegate {
	NSStatusItem *statusItem;
	NSMutableDictionary<NSString*, NSMenuItem*> *yubikeyMenuItemArray;
	NSString *pin;
}

- (void)awakeFromNib {
	NSLog(@"awakeFromNib");
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	unsetenv("DISPLAY");
	
	[[NSUserDefaults standardUserDefaults] registerDefaults:@{
		kPKCSPathKey:@"/usr/local/lib/libykcs11.dylib",
		kSSHAddPathKey:@"/usr/local/bin/ssh-add"
	}];

	kern_return_t kr = [self.yubikeyDeviceManager registerMatchingCallbacks];
	if(kr!=KERN_SUCCESS) {
		NSError *cause = [NSError errorWithDomain:NSMachErrorDomain code:kr userInfo:nil];
		NSAlert *alert = [NSAlert alertWithError:cause];
		alert.informativeText = @"[self initMatchingNotification] failed";
		[alert runModal];
		[NSApp terminate:self];
	}
//			statusItem.image = [NSImage imageNamed:@"yubikey-c"];
	NSArray *keys = [self.sshKeyManager enumerateSSHKeys];
	[self updateSSHKeysMenu:keys];
	BOOL isKeyAdded = [self.sshKeyManager isSSHKeyFomYubiKeyAdded];
	[self.addKeyMenuItem setHidden:isKeyAdded];
	[self.removeKeyMenuItem setHidden:!isKeyAdded];

	yubikeyMenuItemArray = [NSMutableDictionary<NSString*, NSMenuItem*> new];
	
	statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
	statusItem.menu = self.statusMenu;
	statusItem.highlightMode = YES;
	statusItem.image = [NSImage imageNamed:@"yubikey"];
	
	pin = nil;

}

- (void)receiveNotification:(NSNotification*)sender {
	NSLog(@"receiveNotification:%@",sender);
}

- (IBAction) confirmButtonAction:(id)sender {
	[[NSApplication sharedApplication] stopModalWithCode:1];
}

- (IBAction) cancelButtonAction:(id)sender {
	[[NSApplication sharedApplication] stopModalWithCode:0];
}

- (IBAction) preferenceAction:(id)sender {
	[[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
	[self.prefWindow makeKeyAndOrderFront:self];
}

- (IBAction) quitAction:(id)sender {
	[NSApp terminate:self];
}

- (NSString*) askPIN:(NSString*)informativeText {
	if(pin)
		return pin;

	[self.keyIDLabel setStringValue:informativeText];
	[self.rememberPINCheckbox setState:NSOnState];
	NSString *enteredPIN = nil;
	BOOL rememberPIN = NO;
	[[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
	if([[NSApplication sharedApplication] runModalForWindow:self.pinDialog]) {
		enteredPIN  = [self.pinTextField stringValue];
		rememberPIN = [self.rememberPINCheckbox state];
		if(rememberPIN) {
			pin = enteredPIN;
		}

		if ([[[self.prefsController values] valueForKey:kIsPINExpiresKey] intValue]) {
			uint32_t timeout = [[[self.prefsController values] valueForKey:kPINExpiresInKey] intValue];
			NSLog(@"PIN will expire in %d min",timeout);
			NSTimer *timer = [NSTimer timerWithTimeInterval:(timeout*60) target:self selector:@selector(forgetPINAction:) userInfo:nil repeats:NO];
			[[NSRunLoop mainRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
		}
	}

	[self.pinDialog orderOut:self];
	[self.pinTextField setStringValue:@""];
	[self.pinTextField becomeFirstResponder];
	[self.keyIDLabel setStringValue:@""];

	return enteredPIN;
}

- (IBAction) forgetPINAction:(id)sender {
	NSLog(@"forgetting PIN");
}

- (IBAction)addKeyAction:(id)sender {

}

- (IBAction)removeKeyAction:(id)sender {
}

- (IBAction)dummyAction:(id)sender {

}

- (void) updateSSHKeysMenu:(NSArray*)keys {
	[self.sshkeysSubMenu removeAllItems];
	for (NSDictionary *key in keys) {
		NSString *newKeyString = [NSString stringWithFormat:@"%@\n\t%@\n\t[%@/%@]",key[sshKeyHash],key[sshKeyID],key[sshKeyAlgo],key[sshKeyBits]];
		SEL action = [key[sshKeyOurs] intValue]?@selector(dummyAction:):nil;
		NSMenuItem *newMenuItem = [[NSMenuItem alloc] initWithTitle:newKeyString action:action keyEquivalent:@""];
		NSDictionary *attributes = @{
			NSFontAttributeName: [NSFont userFixedPitchFontOfSize:[NSFont smallSystemFontSize]],
	//		NSForegroundColorAttributeName: [NSColor textColor]
		};
		NSAttributedString *attributedTitle = [[NSAttributedString alloc] initWithString:[newMenuItem title] attributes:attributes];
		[newMenuItem setAttributedTitle:attributedTitle];
		if([key[sshKeyOurs] intValue]) {
			[newMenuItem setOnStateImage:[NSImage imageNamed:@"yubikey-c"]];
			[newMenuItem setState:NSOnState];
		}
		[self.sshkeysSubMenu addItem:newMenuItem];
	}
}

- (void) deviceAdded:(NSDictionary*)dev {
	NSLog(@"deviceAdded:%@(SN#%@)",dev[@kUSBProductString],dev[@kUSBSerialNumberString]);
	statusItem.image = [NSImage imageNamed:@"yubikey-c"];
	NSString *newKeyString = [NSString stringWithFormat:@"%@\n\t[SN#%@] at %@",dev[@kUSBProductString],dev[@kUSBSerialNumberString],dev[@kUSBDevicePropertyLocationID]];
	NSMenuItem *newMenuItem = [[NSMenuItem alloc] initWithTitle:newKeyString action:@selector(dummyAction:) keyEquivalent:@""];
	NSDictionary *attributes = @{
		NSFontAttributeName: [NSFont userFixedPitchFontOfSize:[NSFont smallSystemFontSize]],
//		NSForegroundColorAttributeName: [NSColor textColor]
	};
	NSAttributedString *attributedTitle = [[NSAttributedString alloc] initWithString:[newMenuItem title] attributes:attributes];
	[newMenuItem setAttributedTitle:attributedTitle];
	yubikeyMenuItemArray[[self.yubikeyDeviceManager getUniqueIDFromDev:dev]] = newMenuItem;
	[self.yubikeysSubMenu addItem:newMenuItem];

	if([[[self.prefsController values] valueForKey:kExecSSHAddOnInsertionKey] intValue]){
		if(![self.sshKeyManager isSSHKeyFomYubiKeyAdded])
			[self.sshKeyManager addSSHKeyWithPin:[self askPIN:@""]];
		else
			statusItem.image = [NSImage imageNamed:@"yubikey-ok"];
	}

	if([[[self.prefsController values] valueForKey:kWakeScreenOnInsertionKey] intValue]){
		NSLog(@"will wake screen");
		IOPMAssertionID assertionID;
		IOPMAssertionDeclareUserActivity(CFSTR(""), kIOPMUserActiveLocal, &assertionID);
	}
}

- (void) deviceRemoved:(NSDictionary*)dev {
	NSLog(@"deviceRemoved:%@(SN#%@)",dev[@kUSBProductString],dev[@kUSBSerialNumberString]);
	statusItem.image = [NSImage imageNamed:@"yubikey"];
	NSMenuItem *targetMenuItem = yubikeyMenuItemArray[[self.yubikeyDeviceManager getUniqueIDFromDev:dev]];
	if(targetMenuItem)
		[self.yubikeysSubMenu removeItem:targetMenuItem];
	
	if([[[self.prefsController values] valueForKey:kExecSSHAddOnRemovalKey] intValue]){
		[self.sshKeyManager removeSSHKey];
	}
	
	if([[[self.prefsController values] valueForKey:kSleepScreenOnRemovalKey] intValue]){
		NSLog(@"will sleep screen");
		io_registry_entry_t reg = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/IOResources/IODisplayWrangler");
		if (reg) {
			IORegistryEntrySetCFProperty(reg, CFSTR("IORequestIdle"), kCFBooleanTrue);
			IOObjectRelease(reg);
		}

		if([[[self.prefsController values] valueForKey:kLockScreenOnRemovalKey] intValue]){
			CFMessagePortRef port = CFMessagePortCreateRemote(kCFAllocatorDefault, CFSTR("com.apple.loginwindow.notify"));
			if(port) {
				CFMessagePortSendRequest(port, 600, NULL, 0, 0, NULL, NULL);
				CFRelease(port);
			} else {
				extern void SACLockScreenImmediate(void) __attribute__((weak_import, weak));;
				SACLockScreenImmediate();
			}
		}
	}
}


@end

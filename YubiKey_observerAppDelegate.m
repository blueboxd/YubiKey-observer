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
#import "StatusMenuManager.h"

#import "PrefKeys.h"

#include <IOKit/IOKitLib.h>
#include <IOKit/IOMessage.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <IOKit/pwr_mgt/IOPMLib.h>

@interface YubiKey_observerAppDelegate() {
}

- (IBAction) confirmButtonAction:(id)sender;
- (IBAction) cancelButtonAction:(id)sender;
- (IBAction) forgetPINAction:(id)sender;
- (IBAction) preferenceAction:(id)sender;

@end

@implementation YubiKey_observerAppDelegate {
	IBOutlet	NSUserDefaultsController *prefsController;
	IBOutlet	NSWindow *pinDialog;
	IBOutlet	NSButton *rememberPINCheckbox;
	IBOutlet	NSTextField *pinTextField;
	IBOutlet	NSTextField *keyIDLabel;
	IBOutlet	NSWindow *prefWindow;
	IBOutlet	NSMenu *statusMenu;
	IBOutlet	NSMenu *yubikeysSubMenu;
	IBOutlet	NSMenu *sshkeysSubMenu;
	IBOutlet	NSMenuItem *addKeyMenuItem;
	IBOutlet	NSMenuItem *removeKeyMenuItem;
	IBOutlet	YubiKeyDeviceManager *yubikeyDeviceManager;
	IBOutlet	SSHKeyManager *sshKeyManager;
	IBOutlet	PINManager *pinManager;
	IBOutlet	StatusMenuManager *menuIconManager;
				NSStatusItem *statusItem;
				NSMutableDictionary<NSString*, NSMenuItem*> *yubikeyMenuItemArray;
				NSString *pinText;
				NSString *pin;
}

+ (void)initialize{
	[[NSUserDefaults standardUserDefaults] registerDefaults:@{
		kPKCSPathKey:@"/usr/local/lib/libykcs11.dylib",
		kSSHAddPathKey:@"/usr/local/bin/ssh-add"
	}];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	unsetenv("DISPLAY");
	

	yubikeyMenuItemArray = [NSMutableDictionary<NSString*, NSMenuItem*> new];
	
	statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
	statusItem.menu = statusMenu;
	statusItem.highlightMode = YES;
	statusItem.image = [NSImage imageNamed:@"yubikey"];
	
	[statusItem bind:NSImageBinding toObject:menuIconManager withKeyPath:@"self.menuIcon" options:nil];
	
	pin = nil;

	kern_return_t kr = [yubikeyDeviceManager registerMatchingCallbacks];
	if(kr!=KERN_SUCCESS) {
		NSError *cause = [NSError errorWithDomain:NSMachErrorDomain code:kr userInfo:nil];
		NSAlert *alert = [NSAlert alertWithError:cause];
		alert.informativeText = @"[self initMatchingNotification] failed";
		[alert runModal];
		[NSApp terminate:self];
	}
	NSArray *keys = [sshKeyManager enumerateSSHKeys];
	[self keyStoreChanged:keys];
}

- (IBAction) confirmButtonAction:(id)sender {
	[[NSApplication sharedApplication] stopModalWithCode:1];
}

- (IBAction) cancelButtonAction:(id)sender {
	[[NSApplication sharedApplication] stopModalWithCode:0];
}

- (IBAction) preferenceAction:(id)sender {
	[[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
	[prefWindow makeKeyAndOrderFront:self];
}

- (NSString*) askPIN:(NSString*)informativeText {
	if(pin)
		return pin;

	[keyIDLabel setStringValue:informativeText];
	[rememberPINCheckbox setState:NSOnState];
	NSString *enteredPIN = nil;
	BOOL rememberPIN = NO;
	[[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
	if([[NSApplication sharedApplication] runModalForWindow:pinDialog]) {
		enteredPIN  = [pinTextField stringValue];
		rememberPIN = [rememberPINCheckbox state];
		if(rememberPIN) {
			pin = enteredPIN;
		}

		if ([[[prefsController values] valueForKey:kIsPINExpiresKey] intValue]) {
			uint32_t timeout = [[[prefsController values] valueForKey:kPINExpiresInKey] intValue];
			NSLog(@"PIN will expire in %d min",timeout);
			NSTimer *timer = [NSTimer timerWithTimeInterval:(timeout*60) target:self selector:@selector(forgetPINAction:) userInfo:nil repeats:NO];
			[[NSRunLoop mainRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
		}
	}

	[pinDialog orderOut:self];
	[pinTextField setStringValue:@""];
	[pinTextField becomeFirstResponder];
	[keyIDLabel setStringValue:@""];

	return enteredPIN;
}

- (IBAction) forgetPINAction:(id)sender {
	NSLog(@"forgetting PIN");
	pin = nil;
}

- (IBAction)addKeyAction:(id)sender {
	[sshKeyManager addSSHKeyWithPin:[self askPIN:@"Unspecified YubiKey"]];
}

- (IBAction)removeKeyAction:(id)sender {
	[sshKeyManager removeSSHKey];
}

- (IBAction)dummyAction:(id)sender {
	NSLog(@"%@",sender);
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
	yubikeyMenuItemArray[[yubikeyDeviceManager getUniqueIDFromDev:dev]] = newMenuItem;
	[yubikeysSubMenu addItem:newMenuItem];

	if([[[prefsController values] valueForKey:kExecSSHAddOnInsertionKey] intValue]){
		if(![sshKeyManager isSSHKeyFomYubiKeyAdded]) {
			int32_t result = [sshKeyManager addSSHKeyWithPin:[self askPIN:@""]];
			if (!result) {
				statusItem.image = [NSImage imageNamed:@"yubikey-ok"];
			} else {
				statusItem.image = [NSImage imageNamed:@"yubikey-ng"];
			}
		} else
			statusItem.image = [NSImage imageNamed:@"yubikey-ok"];
	}

	if([[[prefsController values] valueForKey:kWakeScreenOnInsertionKey] intValue]){
		NSLog(@"will wake screen");
		IOPMAssertionID assertionID;
		IOPMAssertionDeclareUserActivity(CFSTR(""), kIOPMUserActiveLocal, &assertionID);
	}
}

- (void) deviceRemoved:(NSDictionary*)dev {
	NSLog(@"deviceRemoved:%@(SN#%@)",dev[@kUSBProductString],dev[@kUSBSerialNumberString]);
	statusItem.image = [NSImage imageNamed:@"yubikey"];
	NSMenuItem *targetMenuItem = yubikeyMenuItemArray[[yubikeyDeviceManager getUniqueIDFromDev:dev]];
	if(targetMenuItem)
		[yubikeysSubMenu removeItem:targetMenuItem];
	
	if([[[prefsController values] valueForKey:kExecSSHAddOnRemovalKey] intValue]){
		int32_t result = [sshKeyManager removeSSHKey];
	}
	
	if([yubikeyDeviceManager isYubiKeyInserted])
		statusItem.image = [NSImage imageNamed:@"yubikey-c"];
	
	if([[[prefsController values] valueForKey:kSleepScreenOnRemovalKey] intValue]){
		NSLog(@"will sleep screen");
		io_registry_entry_t reg = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/IOResources/IODisplayWrangler");
		if (reg) {
			IORegistryEntrySetCFProperty(reg, CFSTR("IORequestIdle"), kCFBooleanTrue);
			IOObjectRelease(reg);
		}

		if([[[prefsController values] valueForKey:kLockScreenOnRemovalKey] intValue]){
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

- (void) keyStoreChanged:(NSArray<NSDictionary*>*)keys {
	[sshkeysSubMenu removeAllItems];
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
			statusItem.image = [NSImage imageNamed:@"yubikey-ok"];
		}
		[sshkeysSubMenu addItem:newMenuItem];
	}
}

@end

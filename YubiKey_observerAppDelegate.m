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

	IBOutlet	YubiKeyDeviceManager *yubikeyDeviceManager;
	IBOutlet	SSHKeyManager *sshKeyManager;
	IBOutlet	PINManager *pinManager;

				NSString *pinText;
}

+ (void)initialize {
	[[NSUserDefaults standardUserDefaults] registerDefaults:@{
		kPKCSPathKey:@"/usr/local/lib/libykcs11.dylib",
		kSSHAddPathKey:@"/usr/local/bin/ssh-add"
	}];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	unsetenv("DISPLAY");

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceAdded:) name:YubiKeyDeviceManagerKeyInsertedNotificationKey object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceRemoved:) name:YubiKeyDeviceManagerKeyRemovedNotificationKey object:nil];

	[sshKeyManager refreshKeyStore];
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		kern_return_t kr = [self->yubikeyDeviceManager registerMatchingCallbacks];
		if(kr!=KERN_SUCCESS) {
			NSError *cause = [NSError errorWithDomain:NSMachErrorDomain code:kr userInfo:nil];
			NSAlert *alert = [NSAlert alertWithError:cause];
			alert.informativeText = @"registerMatchingCallbacks failed";
			[alert runModal];
			[NSApp terminate:self];
		}
	});
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

- (NSString*) getPINFor:(NSDictionary*)dev {
	NSString *storedPIN = [pinManager getPinForKey:dev[YubiKeyDeviceDictionaryUSBSerialNumberKey]];
	if(storedPIN)
		return storedPIN;

	NSString *msg;
	if(dev)
		msg = [NSString stringWithFormat:@"for %@ SN#%@",dev[YubiKeyDeviceDictionaryUSBNameKey],dev[YubiKeyDeviceDictionaryUSBSerialNumberKey]];
	else
		msg = @"Unspecified YubiKey";

	[keyIDLabel setStringValue:msg];
	[rememberPINCheckbox setState:NSOnState];
	NSString *enteredPIN = nil;
	[[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
	if([[NSApplication sharedApplication] runModalForWindow:self->pinDialog]==NSModalResponseOK) {
		BOOL rememberPIN = NO;
		enteredPIN  = [self->pinTextField stringValue];
		rememberPIN = [self->rememberPINCheckbox state];
		if(rememberPIN) {
			NSString *labelStr = [NSString stringWithFormat:@"PIN for %@ SN#%@",dev[YubiKeyDeviceDictionaryUSBNameKey],dev[YubiKeyDeviceDictionaryUSBSerialNumberKey]];
			[self->pinManager storePin:enteredPIN forKey:dev[YubiKeyDeviceDictionaryUSBSerialNumberKey] withLabel:labelStr];
		}
		if ([[[self->prefsController values] valueForKey:kIsPINExpiresKey] intValue]) {
			uint32_t timeout = [[[self->prefsController values] valueForKey:kPINExpiresInKey] intValue];
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
}

- (IBAction)addKeyAction:(id)sender {
	[self addSSHKeyForDev:[yubikeyDeviceManager getAnySingleDevice]];
}

- (IBAction)removeKeyAction:(id)sender {
	[sshKeyManager removeSSHKey];
}

- (void) addSSHKeyForDev:(NSDictionary*)dev {
	dispatch_async(dispatch_get_main_queue(), ^{
		NSString *pin = [self getPINFor:dev];
		if(pin)
			[self->sshKeyManager addSSHKeyWithPin:pin];
	});
}

- (void) deviceAdded:(NSNotification*)notification {
	NSDictionary *dev = notification.userInfo;
	NSLog(@"deviceAdded:%@(SN#%@)",dev[YubiKeyDeviceDictionaryUSBNameKey],dev[YubiKeyDeviceDictionaryUSBSerialNumberKey]);

	if([[[prefsController values] valueForKey:kWakeScreenOnInsertionKey] intValue]){
		NSLog(@"will wake screen");
		IOPMAssertionID assertionID;
		IOPMAssertionDeclareUserActivity(CFSTR(""), kIOPMUserActiveLocal, &assertionID);
	}
	
	if([[[prefsController values] valueForKey:kExecSSHAddOnInsertionKey] intValue]){
		if(![sshKeyManager hasOurKey])
			[self addSSHKeyForDev:dev];
	}
}

- (void) deviceRemoved:(NSNotification*)notification {
	NSDictionary *dev = notification.userInfo;
	NSLog(@"deviceRemoved:%@(SN#%@)",dev[YubiKeyDeviceDictionaryUSBNameKey],dev[YubiKeyDeviceDictionaryUSBSerialNumberKey]);
	[NSApp abortModal];
	if([[[prefsController values] valueForKey:kExecSSHAddOnRemovalKey] intValue]){
		[sshKeyManager removeSSHKey];
	}
	
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

@end

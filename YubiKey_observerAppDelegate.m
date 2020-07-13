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

//- (IBAction) confirmButtonAction:(id)sender;
//- (IBAction) cancelButtonAction:(id)sender;
//- (IBAction) forgetPINAction:(id)sender;
//- (IBAction) preferenceAction:(id)sender;
@property BOOL pkcsProviderExists;
@end

@implementation YubiKey_observerAppDelegate {
IBOutlet NSUserDefaultsController *prefsController;
IBOutlet NSWindow *pinDialog;
IBOutlet NSButton *rememberPINCheckbox;
IBOutlet NSTextField *pinTextField;
IBOutlet NSTextField *keyIDLabel;
IBOutlet NSWindow *prefWindow;

IBOutlet YubiKeyDeviceManager *yubikeyDeviceManager;
IBOutlet PINManager *pinManager;

SSHKeyManager *sshKeyManager;
NSString *pinText;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
NSLog(@"%@:%@",NSStringFromClass([self class]),NSStringFromSelector(_cmd));
	[[NSUserDefaults standardUserDefaults] registerDefaults:@{
		kPKCSPathKey:@"/usr/local/lib/libykcs11.dylib",
		kSSHAddPathKey:@"/usr/local/bin/ssh-add"
	}];
	NSString *pkcsPath = [[prefsController values] valueForKey:kPKCSPathKey];
	self.pkcsProviderExists = [[NSURL fileURLWithPath:pkcsPath] checkResourceIsReachableAndReturnError:nil];
	if(self.pkcsProviderExists)
		sshKeyManager = [[SSHKeyManager alloc] initWithProvider:pkcsPath];

	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kPKCSPathKey options:NSKeyValueObservingOptionNew context:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceAdded:) name:YubiKeyDeviceManagerKeyInsertedNotificationKey object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceRemoved:) name:YubiKeyDeviceManagerKeyRemovedNotificationKey object:nil];

	[sshKeyManager startObserver];
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		kern_return_t kr = [self->yubikeyDeviceManager registerMatchingCallbacks];
		if(kr!=KERN_SUCCESS) {
			dispatch_sync(dispatch_get_main_queue(), ^{
				NSError *cause = [NSError errorWithDomain:NSMachErrorDomain code:kr userInfo:nil];
				NSAlert *alert = [NSAlert alertWithError:cause];
				alert.informativeText = @"registerMatchingCallbacks failed";
				[alert runModal];
				[NSApp terminate:self];
			});
		}
	});
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	if([keyPath isEqualToString:kPKCSPathKey]) {
		NSURL *pkcsPath = [NSURL fileURLWithPath:change[NSKeyValueChangeNewKey]];
		NSError *err;
		if((self.pkcsProviderExists = [pkcsPath checkResourceIsReachableAndReturnError:&err])) {
			sshKeyManager = nil;
			sshKeyManager = [[SSHKeyManager alloc]initWithProvider:change[NSKeyValueChangeNewKey]];
		}
		if(err)
			NSLog(@"%@",err);
	}
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
	[self removeSSHKey];
}

- (void) addSSHKeyForDev:(NSDictionary*)dev {
	if(self.pkcsProviderExists && (![sshKeyManager hasOurKey])) {
		dispatch_async(dispatch_get_main_queue(), ^{
			NSString *pin = [self getPINFor:dev];
			if(pin) {
				NSError *err = [self->sshKeyManager updateCardAdd:YES pin:pin];
				if(err) {
					NSAlert *alert = [NSAlert alertWithError:err];
					alert.informativeText = err.userInfo[NSLocalizedFailureReasonErrorKey];
					[alert runModal];
				}
			}
		});
	}
}

- (void) removeSSHKey {
	if(self.pkcsProviderExists)
		[self->sshKeyManager updateCardAdd:NO pin:nil];
}

- (void) deviceAdded:(NSNotification*)notification {
	NSDictionary *dev = notification.userInfo;
	NSLog(@"deviceAdded:%@(SN#%@)",dev[YubiKeyDeviceDictionaryUSBNameKey],dev[YubiKeyDeviceDictionaryUSBSerialNumberKey]);

	if([[[prefsController values] valueForKey:kWakeScreenOnInsertionKey] intValue]){
		NSLog(@"will wake screen");
		IOPMAssertionID assertionID;
		IOPMAssertionDeclareUserActivity(CFSTR(""), kIOPMUserActiveLocal, &assertionID);
	}
	
	if([[[prefsController values] valueForKey:kUnlockKeychainOnInsertionKey] intValue]){
		SecKeychainUnlock(nil, 0, nil, NO);
	}
	
	if([[[prefsController values] valueForKey:kExecSSHAddOnInsertionKey] intValue]){
		[self addSSHKeyForDev:dev];
	}
}

- (void) deviceRemoved:(NSNotification*)notification {
	NSDictionary *dev = notification.userInfo;
	NSLog(@"deviceRemoved:%@(SN#%@)",dev[YubiKeyDeviceDictionaryUSBNameKey],dev[YubiKeyDeviceDictionaryUSBSerialNumberKey]);
	[NSApp abortModal];
	if([[[prefsController values] valueForKey:kExecSSHAddOnRemovalKey] intValue]){
		[self removeSSHKey];
	}
	
	if([[[prefsController values] valueForKey:kLockKeychainOnRemovalKey] intValue]){
		SecKeychainLock(nil);
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
				//-undefined dynamic_lookup
				extern void SACLockScreenImmediate(void) __attribute__((weak_import, weak));;
				SACLockScreenImmediate();
			}
		}
	}
}

@end

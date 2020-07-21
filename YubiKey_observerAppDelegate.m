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
#import "YubiKey.h"

#import <Quartz/Quartz.h>

#include <IOKit/pwr_mgt/IOPMLib.h>

#define kExecSSHAddOnInsertionKey @"execSSHAddOnInsertion"
#define kExecSSHAddOnRemovalKey @"execSSHAddOnRemoval"
#define kSleepScreenOnRemovalKey @"sleepScreen"
#define kLockScreenOnRemovalKey @"lockScreen"
#define kWakeScreenOnInsertionKey @"wakeScreen"
#define kLockKeychainOnRemovalKey @"lockKeychain"
#define kUnlockKeychainOnInsertionKey @"unlockKeychain"
#define kIsPINExpiresKey @"pinExpires"
#define kPINExpiresInKey @"expiresIn"
#define kPKCSPathKey @"pkcsPath"
#define kSSHAddPathKey @"sshAddPath"
#define kFingerprintDigestKey @"digest"
#define kFingerprintRepresentationKey @"representation"

@interface YubiKey_observerAppDelegate() {
}
@property BOOL pkcsProviderExists;
@end

@implementation YubiKey_observerAppDelegate {
IBOutlet NSUserDefaultsController *prefsController;
IBOutlet NSWindow *pinDialog;
IBOutlet NSButton *rememberPINCheckbox;
IBOutlet NSTextField *pinTextField;
IBOutlet NSTextField *keyIDLabel;
IBOutlet NSWindow *prefWindow;
IBOutlet NSImageView *providerPathAlertIcon;

IBOutlet NSImageView *pinAlertIcon;
IBOutlet NSTextField *pinAlertLabel;

IBOutlet YubiKeyDeviceManager *yubikeyDeviceManager;
IBOutlet PINManager *pinManager;
IBOutlet StatusMenuManager *statusMenuManager;

IBOutlet NSMenu *testMenu;

SSHKeyManager *sshKeyManager;
NSString *pinText;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
//	NSLog(@"%@:%@",NSStringFromClass([self class]),NSStringFromSelector(_cmd));
	[[NSUserDefaults standardUserDefaults] registerDefaults:@{
		kPKCSPathKey:@"/usr/local/lib/opensc-pkcs11.so",
		kSSHAddPathKey:@"/usr/local/bin/ssh-add"
	}];
	NSString *pkcsPath = [[prefsController values] valueForKey:kPKCSPathKey];
	self.pkcsProviderExists = [[NSURL fileURLWithPath:pkcsPath] checkResourceIsReachableAndReturnError:nil];
	sshKeyManager = [SSHKeyManager new];
	sshKeyManager.fpDigest = [[[prefsController values] valueForKey:kFingerprintDigestKey] intValue]; 
	sshKeyManager.fpRepresentation = [[[prefsController values] valueForKey:kFingerprintRepresentationKey] intValue];
	sshKeyManager.provider = pkcsPath;

	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kPKCSPathKey options:NSKeyValueObservingOptionNew context:nil];

	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kFingerprintDigestKey options:NSKeyValueObservingOptionNew context:nil];
	[[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kFingerprintRepresentationKey options:NSKeyValueObservingOptionNew context:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceAdded:) name:YubiKeyDeviceManagerKeyInsertedNotificationKey object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceRemoved:) name:YubiKeyDeviceManagerKeyRemovedNotificationKey object:nil];

	[sshKeyManager startObserver];
	[sshKeyManager refreshKeyStore];
	
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
//	[NSApp setNextResponder:statusMenuManager];
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	if([keyPath isEqualToString:kPKCSPathKey]) {
		NSURL *pkcsPath = [NSURL fileURLWithPath:change[NSKeyValueChangeNewKey]];
		NSError *err;
		self.pkcsProviderExists = NO;
		if([pkcsPath checkResourceIsReachableAndReturnError:&err]) {
			NSNumber *isDir;
			[pkcsPath getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:&err];
			if(![isDir intValue]) {
				self.pkcsProviderExists = YES;
				sshKeyManager.provider = change[NSKeyValueChangeNewKey];
			} else {
				providerPathAlertIcon.toolTip = @"Path is not file";
			}
			if(err)
				NSLog(@"%@",err);
		}
		if(err) {
			providerPathAlertIcon.toolTip = [err localizedFailureReason];
			 if(err.code!=260)
				NSLog(@"%@",err);
		}
	} else if([keyPath isEqualToString:kFingerprintDigestKey]) { 
		sshKeyManager.fpDigest = [change[NSKeyValueChangeNewKey] intValue];
	} else if([keyPath isEqualToString:kFingerprintRepresentationKey]) {
		sshKeyManager.fpRepresentation = [change[NSKeyValueChangeNewKey] intValue];
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

-(void)shakeWindow:(NSWindow*)target {

    static int numberOfShakes = 3;
    static float durationOfShake = 0.5f;
    static float vigourOfShake = 0.05f;

    CGRect frame=[target frame];
    CAKeyframeAnimation *shakeAnimation = [CAKeyframeAnimation animation];

    CGMutablePathRef shakePath = CGPathCreateMutable();
    CGPathMoveToPoint(shakePath, NULL, NSMinX(frame), NSMinY(frame));
    for (NSInteger index = 0; index < numberOfShakes; index++){
        CGPathAddLineToPoint(shakePath, NULL, NSMinX(frame) - frame.size.width * vigourOfShake, NSMinY(frame));
        CGPathAddLineToPoint(shakePath, NULL, NSMinX(frame) + frame.size.width * vigourOfShake, NSMinY(frame));
    }
    CGPathCloseSubpath(shakePath);
    shakeAnimation.path = shakePath;
    shakeAnimation.duration = durationOfShake;

    [target setAnimations:[NSDictionary dictionaryWithObject: shakeAnimation forKey:@"frameOrigin"]];
    [[target animator] setFrameOrigin:[target frame].origin];
}

- (int8_t) verifyAndStorePIN:(NSString*)pin {
	
}

- (void) addSSHKeyForYubiKey:(YubiKey*)yubikey {
	if([sshKeyManager hasOurKey])return;
	if(!self.pkcsProviderExists)return;
	__block BOOL doAdd=NO, done=NO;
	__block NSString *pin;
	dispatch_sync(dispatch_get_main_queue(), ^{		
		NSString *storedPIN = [self->pinManager getPinForKey:yubikey.serial];
		if(storedPIN) {
			int8_t verifyResult = [yubikey verifyPIN:storedPIN];
			if (verifyResult==kYubiKeyDeviceManagerVerifyPINSuccess) {
				doAdd = YES;
				done = YES;
				pin = storedPIN;
			} else {
				[self->pinManager removePinForKey:yubikey.serial];
				if (verifyResult==kYubiKeyDeviceManagerVerifyPINBlockedErr) {
					doAdd = NO;
					done = YES;
				} else {
					[self->pinAlertIcon setHidden:NO];
					[self->pinAlertLabel setStringValue:[NSString stringWithFormat:@"Saved PIN is invalid. %u retries left.",verifyResult]];
					[self->pinAlertLabel setHidden:NO];
				}
			}
		}

		NSString *msg = [NSString stringWithFormat:@"for %@ SN#%@",yubikey.model,yubikey.serial];

		[self->keyIDLabel setStringValue:msg];
		[self->pinAlertIcon setHidden:YES];
		[self->pinAlertLabel setHidden:YES];
		
		NSString *enteredPIN = nil;
		[[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
		while(!done) {
			NSModalResponse res = [[NSApplication sharedApplication] runModalForWindow:self->pinDialog];
			if(res==NSModalResponseOK) {
				BOOL rememberPIN = NO;
				enteredPIN  = [self->pinTextField stringValue];
				rememberPIN = [self->rememberPINCheckbox state];
				int8_t verifyResult = [yubikey verifyPIN:enteredPIN];
				//int8_t verifyResult = [yubikey verifyPIN:enteredPIN];
				if (verifyResult==kYubiKeyDeviceManagerVerifyPINBlockedErr) {
					done = YES;
					doAdd = NO;
					NSAlert *alert = [NSAlert new];
					alert.messageText = @"PIN code blocked";
					alert.informativeText = @"Please unblock PIN code before use";
					alert.alertStyle = NSAlertStyleCritical;
					[alert runModal];
				} else if (verifyResult==kYubiKeyDeviceManagerVerifyPINSuccess) {
					done = YES;
					doAdd = YES;
					pin = enteredPIN;
					if(rememberPIN) {
						NSString *labelStr = [NSString stringWithFormat:@"PIN for %@ SN#%@",yubikey.model,yubikey.serial];
						[self->pinManager storePin:enteredPIN forKey:yubikey.serial withLabel:labelStr];
					}
				} else {
					[self->pinAlertIcon setHidden:NO];
					[self->pinAlertLabel setStringValue:[NSString stringWithFormat:@"Invalid PIN. %u retries left.",verifyResult]];
					[self->pinAlertLabel setHidden:NO];
					[self shakeWindow:self->pinDialog];
					continue;
				}
			} else if (res==NSModalResponseCancel) {
				done = YES;
			}
		}
		[self->pinDialog orderOut:self];
		[self->pinTextField setStringValue:@""];
		[self->pinTextField becomeFirstResponder];
		[self->keyIDLabel setStringValue:@""];
		[self->pinAlertIcon setHidden:YES];
		[self->pinAlertLabel setHidden:YES];
	});
	
	
	if(doAdd) {
		NSError *err = [self->sshKeyManager updateCardAdd:YES pin:pin];
		if(err) {
			dispatch_async(dispatch_get_main_queue(), ^{	
				NSAlert *alert = [NSAlert alertWithError:err];
				alert.informativeText = err.userInfo[NSLocalizedFailureReasonErrorKey];
				[alert runModal];
			});
		}
	}
}

- (IBAction)verifyPINAction:(NSMenuItem*)sender {
	YubiKey *yubikey = ((__bridge YubiKey*)((void*)sender.tag));
	NSLog(@"%@:%@",NSStringFromClass([self class]),NSStringFromSelector(_cmd));
	NSLog(@"%@:%@",sender,yubikey.serial);
}

- (IBAction)forgetPINAction:(NSMenuItem*)sender {
	YubiKey *yubikey = ((__bridge YubiKey*)((void*)sender.tag));
	NSLog(@"%@:%@",NSStringFromClass([self class]),NSStringFromSelector(_cmd));
	NSLog(@"%@:%@",sender,yubikey.serial);
	[self->pinManager removePinForKey:yubikey.serial];
}

- (IBAction)addKeyAction:(id)sender {
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		[self addSSHKeyForYubiKey:[self->yubikeyDeviceManager getAnyYubiKey]];
	});
}

- (IBAction)removeKeyAction:(id)sender {
	[self removeSSHKey];
}

- (void) removeSSHKey {
	if(self.pkcsProviderExists)
		[self->sshKeyManager updateCardAdd:NO pin:nil];
}

- (void) deviceAdded:(NSNotification*)notification {
	YubiKey *yubikey = notification.userInfo;
	NSLog(@"deviceAdded:%@",[yubikey getUniqueString]);

	if([[[prefsController values] valueForKey:kWakeScreenOnInsertionKey] intValue]){
		NSLog(@"will wake screen");
		IOPMAssertionID assertionID;
		IOPMAssertionDeclareUserActivity(CFSTR(""), kIOPMUserActiveLocal, &assertionID);
	}
	
	if([[[prefsController values] valueForKey:kUnlockKeychainOnInsertionKey] intValue]){
		SecKeychainUnlock(nil, 0, nil, NO);
	}
	
	if([[[prefsController values] valueForKey:kExecSSHAddOnInsertionKey] intValue]){
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{			
			[self addSSHKeyForYubiKey:yubikey];
		});		   
	}
}

- (void) deviceRemoved:(NSNotification*)notification {
	YubiKey *yubikey = notification.userInfo;
	NSLog(@"deviceRemoved:%@",[yubikey getUniqueString]);
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

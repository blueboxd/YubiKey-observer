//
//  YubiKey_observerAppDelegate.h
//  YubiKey-observer
//
//  Created by bluebox on 18/10/27.
//  Copyright 2018 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOMessage.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <IOKit/pwr_mgt/IOPMLib.h>

#define kExecSSHADDOnInsertionKey @"execSSHAddOnInsertion"
#define kExecSSHADDOnRemovalKey @"execSSHAddOnRemoval"
#define kSleepScreenOnRemovalKey @"sleepScreen"
#define kLockScreenOnRemovalKey @"lockScreen"
#define kWakeScreenOnInsertionKey @"wakeScreen"
#define kIsPINExpiresKey @"pinExpires"
#define kPINExpiresInKey @"expiresIn"
#define kPKCSPathKey @"pkcsPath"
#define kSSHADDPathKey @"sshAddPath"

#define sshKeyID @"id"
#define sshKeyBits @"bits"
#define sshKeyHash @"hash"
#define sshKeyAlgo @"algo"

@interface YubiKey_observerAppDelegate : NSObject <NSApplicationDelegate> {
	
}

@property (strong) IBOutlet NSUserDefaultsController *prefsController;

@property (strong) IBOutlet NSWindow *pinDialog;
@property (nonatomic) IBOutlet NSButton *rememberPINCheckbox;
@property (nonatomic) IBOutlet NSTextField * pinTextField;
@property (nonatomic) NSString *pinText;

@property (strong) IBOutlet NSWindow *prefWindow;

@property (strong) NSStatusItem *statusItem;
@property (strong) IBOutlet NSMenu *statusMenu;
@property (strong) IBOutlet NSMenu *yubikeysSubMenu;
@property (strong) IBOutlet NSMenu *sshkeysSubMenu;

@property (strong,nonatomic) NSString *pin;
@property (nonatomic) IONotificationPortRef notifyPort;
@property NSMutableDictionary<NSString*, NSMenuItem*> *yubikeyMenuItemArray;

- (IBAction) confirmButtonAction:(id)sender;
- (IBAction) cancelButtonAction:(id)sender;

- (IBAction) forgetPINAction:(id)sender;

- (IBAction) preferenceAction:(id)sender;
- (IBAction) quitAction:(id)sender;

@end

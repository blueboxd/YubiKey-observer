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
#include <IOKit/pwr_mgt/IOPMLib.h>

#define kExecSSHADDOnInsertionKey @"values.execSSHAddOnInsertion"
#define kExecSSHADDOnRemovalKey @"values.execSSHAddOnRemoval"
#define kSleepScreenOnRemovalKey @"values.sleepScreen"
#define kLockScreenOnRemovalKey @"values.lockScreen"
#define kWakeScreenOnInsertionKey @"values.wakeScreen"
#define kIsPINExpiresKey @"values.pinExpires"
#define kPINExpiresInKey @"values.expiresIn"
#define kPKCSPathKey @"values.pkcsPath"
#define kPKCSPathKeyDefault @"pkcsPath"
#define kSSHADDPathKey @"values.sshAddPath"
#define kSSHADDPathKeyDefault @"sshAddPath"

@interface YubiKey_observerAppDelegate : NSObject <NSApplicationDelegate> {
	
}

@property (strong) IBOutlet NSUserDefaultsController *prefsController;

@property (strong) IBOutlet NSWindow *pinDialog;
@property (nonatomic) IBOutlet NSButton *rememberPINCheckbox;
@property (nonatomic) IBOutlet NSTextField * pinTextField;
@property (nonatomic) IBOutlet NSString *pinText;

@property (strong) IBOutlet NSWindow *prefWindow;

@property (strong) IBOutlet NSMenu *statusMenu;
@property (strong) NSStatusItem *statusItem;

@property (strong,nonatomic) NSString *pin;
@property (nonatomic) IONotificationPortRef notifyPort;


- (IBAction) confirmButtonAction:(id)sender;
- (IBAction) cancelButtonAction:(id)sender;

- (IBAction) forgetPINAction:(id)sender;

- (IBAction) preferenceAction:(id)sender;
- (IBAction) quitAction:(id)sender;

@end

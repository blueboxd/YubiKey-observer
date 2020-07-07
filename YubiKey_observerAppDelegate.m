//
//  YubiKey_observerAppDelegate.m
//  YubiKey-observer
//
//  Created by bluebox on 18/10/27.
//  Copyright 2018 __MyCompanyName__. All rights reserved.
//

#import "YubiKey_observerAppDelegate.h"

@implementation YubiKey_observerAppDelegate

void IOServiceMatchedCallback(void* refcon, io_iterator_t iterator);
void IOServiceTerminatedCallback(void* refcon, io_iterator_t iterator);


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	unsetenv("DISPLAY");
	
	[[NSUserDefaults standardUserDefaults] registerDefaults:@{
		kPKCSPathKey:@"/usr/local/lib/libykcs11.dylib",
		kSSHADDPathKey:@"/usr/local/bin/ssh-add"
	}];

	self.yubikeyMenuItemArray = [[NSMutableDictionary<NSString*, NSMenuItem*> alloc] init];
	
	self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
	self.statusItem.menu = self.statusMenu;
	self.statusItem.highlightMode = YES;
	self.statusItem.image = [NSImage imageNamed:@"yubikey"];
	
	self.pin = nil;

	kern_return_t kr = [self initMatchingNotification];
	if(kr!=KERN_SUCCESS) {
		NSError *cause = [NSError errorWithDomain:NSMachErrorDomain code:kr userInfo:nil];
		NSAlert *alert = [NSAlert alertWithError:cause];
		alert.informativeText = @"[self initMatchingNotification] failed";
		[alert runModal];
		[NSApp terminate:self];
	}
	
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

- (NSString*) getPIN {
	if(self.pin)
		return self.pin;

	[self.rememberPINCheckbox setState:NSOnState];
	NSString *enteredPIN = nil;
	BOOL rememberPIN = NO;
	[[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
	if([[NSApplication sharedApplication] runModalForWindow:self.pinDialog]) {
		enteredPIN  = [self.pinTextField stringValue];
		rememberPIN = [self.rememberPINCheckbox state];
		if(rememberPIN) {
			self.pin = enteredPIN;
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

	return enteredPIN;
}

- (IBAction) forgetPINAction:(id)sender {
	NSLog(@"forgetting PIN");
	self.pin = nil;
}

- (NSDictionary*) enumerateSSHKeys {
	
}

- (void) addSSHKey {
	NSLog(@"will ssh-add -s");
	NSString *pin = [self getPIN];
	if (!pin) {
		NSLog(@"no PIN was supplied");
		return;
	}

	NSArray *args = @[
	  @"-s",
	  [[self.prefsController values] valueForKey:kPKCSPathKey],
	];

	NSArray *stdinArgs = @[
		pin,
		@"\n"
	];

	usleep(500000);

	NSString *stdoutStr, *stderrStr;
	uint32_t result;
	result = [self execSystemCmd:[[self.prefsController values] valueForKey:kSSHADDPathKey] withArgs:args withStdIn:stdinArgs withStdOut:&stdoutStr withStdErr:&stderrStr];
	if (!result)
		self.statusItem.image = [NSImage imageNamed:@"yubikey-ok"];
	else
		self.statusItem.image = [NSImage imageNamed:@"yubikey-ng"];
}

- (void) removeSSHKey {
	NSLog(@"will ssh-add -e");
	NSArray *args = @[
		@"-e",
		[[self.prefsController values] valueForKey:kPKCSPathKey],
	];
	NSString *stdoutStr, *stderrStr;
	uint32_t result;
	result = [self execSystemCmd:[[self.prefsController values] valueForKey:kSSHADDPathKey] withArgs:args withStdIn:@[] withStdOut:&stdoutStr withStdErr:&stderrStr];
}

- (NSString*) getPKeyFromDevDict:(NSDictionary*) dev {
	return [NSString stringWithFormat:@"%@/%@-%@",dev[@kUSBDevicePropertyLocationID],dev[@kUSBProductString],dev[@kUSBSerialNumberString]];
}

- (void) deviceAdded:(NSDictionary*)dev {
	NSLog(@"deviceAdded:%@(SN#%@)",dev[@kUSBProductString],dev[@kUSBSerialNumberString]);
	self.statusItem.image = [NSImage imageNamed:@"yubikey-c"];
	NSString *newKeyString = [NSString stringWithFormat:@"%@ (SN#%@) at %@",dev[@kUSBProductString],dev[@kUSBSerialNumberString],dev[@kUSBDevicePropertyLocationID]];
	NSMenuItem *newMenuItem = [[NSMenuItem alloc] initWithTitle:newKeyString action:nil keyEquivalent:@""];
	NSDictionary *attributes = @{
		NSFontAttributeName: [NSFont menuFontOfSize:[NSFont smallSystemFontSize]],
//		NSForegroundColorAttributeName: [NSColor textColor]
	};
	NSAttributedString *attributedTitle = [[NSAttributedString alloc] initWithString:[newMenuItem title] attributes:attributes];
	[newMenuItem setAttributedTitle:attributedTitle];
	self.yubikeyMenuItemArray[[self getPKeyFromDevDict:dev]] = newMenuItem;
	[self.yubikeysSubMenu addItem:newMenuItem];

	if([[[self.prefsController values] valueForKey:kExecSSHADDOnInsertionKey] intValue]){
		[self addSSHKey];
	}

	if([[[self.prefsController values] valueForKey:kWakeScreenOnInsertionKey] intValue]){
		NSLog(@"will wake screen");
		IOPMAssertionID assertionID;
		IOPMAssertionDeclareUserActivity(CFSTR(""), kIOPMUserActiveLocal, &assertionID);
	}
}

- (void) deviceRemoved:(NSDictionary*)dev {
	NSLog(@"deviceRemoved:%@(SN#%@)",dev[@kUSBProductString],dev[@kUSBSerialNumberString]);
	self.statusItem.image = [NSImage imageNamed:@"yubikey"];
	NSMenuItem *targetMenuItem = self.yubikeyMenuItemArray[[self getPKeyFromDevDict:dev]];
	if(targetMenuItem)
		[self.yubikeysSubMenu removeItem:targetMenuItem];
	
	if([[[self.prefsController values] valueForKey:kExecSSHADDOnRemovalKey] intValue]){
		[self removeSSHKey];
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

- (int32_t)execSystemCmd:(NSString*)cmd withArgs:(NSArray*)args withStdIn:(NSArray*)stdinArgs withStdOut:(NSString**)stdoutStr withStdErr:(NSString**)stderrStr {
	NSPipe *stdoutPipe = [NSPipe pipe];
	NSFileHandle *stdoutFile = stdoutPipe.fileHandleForReading;
	NSPipe *stderrPipe = [NSPipe pipe];
	NSFileHandle *stderrFile = stderrPipe.fileHandleForReading;
	NSPipe *stdinPipe = [NSPipe pipe];
	NSFileHandle *stdinFile = stdinPipe.fileHandleForWriting;

	NSTask *task = [[NSTask alloc] init];
	task.launchPath = cmd;
	task.arguments = args;
	task.standardOutput = stdoutPipe;
	task.standardError = stderrPipe;
	task.standardInput = stdinPipe;

	[task launch];
	[stdinArgs enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL *stop){
		[stdinFile writeData:[obj dataUsingEncoding:NSUTF8StringEncoding]];
	}];
	[task waitUntilExit];

	NSData *stdoutData = [stdoutFile readDataToEndOfFile];
	[stdoutFile closeFile];
	*stdoutStr = [[NSString alloc] initWithData: stdoutData encoding: NSUTF8StringEncoding];

	NSData *stderrData = [stderrFile readDataToEndOfFile];
	[stderrFile closeFile];
	*stderrStr = [[NSString alloc] initWithData: stderrData encoding: NSUTF8StringEncoding];
	NSLog(@"execSystemCmd(%@):terminationStatus: %d\nstdout: %@\nstderr: %@",cmd,task.terminationStatus,*stdoutStr,*stderrStr);
	return task.terminationStatus;
}

- (bool) initMatchingNotification {
	kern_return_t kr;

	IONotificationPortRef notifyPort = IONotificationPortCreate(kIOMasterPortDefault);
	CFRunLoopSourceRef loopSource = IONotificationPortGetRunLoopSource(notifyPort);
	CFRunLoopRef runLoop = CFRunLoopGetCurrent();
	CFRunLoopAddSource(runLoop, loopSource, kCFRunLoopDefaultMode);

	CFMutableDictionaryRef matchDict = (__bridge_retained CFMutableDictionaryRef)@{
		@kIOProviderClassKey : @kIOUSBDeviceClassName,
		@kUSBProductID : @"*",
		@kUSBVendorID : @0x1050
	};

	CFRetain(matchDict);

	io_iterator_t iterator;
	io_service_t usbDevice;

	kr = IOServiceAddMatchingNotification(notifyPort, kIOFirstMatchNotification, matchDict, IOServiceMatchedCallback, (void*)YES, &iterator);
	if(kr!=KERN_SUCCESS) return kr;
	while ((usbDevice=IOIteratorNext(iterator))) {
		CFDictionaryRef dict = GetKeyInfo(usbDevice);
		if(dict) {
			NSLog(@"initial device found:%@",dict);
			self.statusItem.image = [NSImage imageNamed:@"yubikey-c"];
		}
	}

	kr = IOServiceAddMatchingNotification(notifyPort, kIOTerminatedNotification, matchDict, IOServiceMatchedCallback, (void*)NO, &iterator);
	if(kr!=KERN_SUCCESS) return kr;
	while ((usbDevice=IOIteratorNext(iterator))) {
		CFDictionaryRef dict = GetKeyInfo(usbDevice);
		if(dict)
			NSLog(@"device found for termination:%@",dict);
	}
	return KERN_SUCCESS;
}

void IOServiceMatchedCallback(void* added, io_iterator_t iterator) {
	NSLog(@"IOServiceMatchedCallback");
	io_service_t usbDevice;

	while ((usbDevice=IOIteratorNext(iterator))) {
		CFDictionaryRef dict = GetKeyInfo(usbDevice);
		if(dict) {
			if(added) {
				NSLog(@"YubiKey inserted:%@",dict);
				[((YubiKey_observerAppDelegate*)[NSApp delegate]) deviceAdded:(__bridge_transfer NSDictionary*)dict];
			} else {
				NSLog(@"YubiKey removed:%@",dict);
				[((YubiKey_observerAppDelegate*)[NSApp delegate]) deviceRemoved:(__bridge_transfer NSDictionary*)dict];
			}
		}
	}
}

CFDictionaryRef GetKeyInfo(io_service_t usbDevice) {
	kern_return_t kr;
	CFMutableDictionaryRef devDict = nil;

	kr = IORegistryEntryCreateCFProperties(usbDevice, &devDict, kCFAllocatorDefault, kNilOptions);
	if(kr!=KERN_SUCCESS) return nil;
	NSLog(@"Yubico device (idVendor:0x1050) found:%@",devDict);

	io_name_t devName;
	IORegistryEntryGetName(usbDevice, devName);
	if(!strstr(devName,"CCID"))
		return nil;
	
	if(!CFDictionaryContainsKey(devDict, CFSTR(kUSBSerialNumberString)))
		CFDictionarySetValue(devDict, CFSTR(kUSBSerialNumberString), CFSTR("unknown"));
	
	return devDict;
}

@end

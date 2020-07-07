//
//  YubiKey_observerAppDelegate.m
//  YubiKey-observer
//
//  Created by bluebox on 18/10/27.
//  Copyright 2018 __MyCompanyName__. All rights reserved.
//

#import "YubiKey_observerAppDelegate.h"
#include <mach/task_info.h>

@implementation YubiKey_observerAppDelegate

void IOServiceMatchedCallback(void* refcon, io_iterator_t iterator);
void IOServiceTerminatedCallback(void* refcon, io_iterator_t iterator);


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
	self.statusItem.menu = self.statusMenu;
	self.statusItem.highlightMode = YES;
	self.statusItem.image = [NSImage imageNamed:@"yubikey"];
	
//	[self.prefsController addObserver:self forKeyPath:nil options:NSKeyValueObservingOptionNew context:nil];
//	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveNotification:) name:nil object:[NSUserDefaults standardUserDefaults]];

	self.pin = nil;
	[self initMatchingNotification];
	{
		NSString *stdoutStr, *stderrStr;
		uint32_t result;
		result = [self execSystemCmd:@"/usr/bin/ssh-add" withArgs:@[@"-l"] withStdOut:&stdoutStr withStdErr:&stderrStr];
	}
	
	[[NSUserDefaults standardUserDefaults] registerDefaults:@{
		kPKCSPathKeyDefault:@"/usr/local/lib/libykcs11.dylib",
		kSSHADDPathKeyDefault:@"/usr/local/bin/ssh-add"
	}];
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

	NSString *enteredPIN = nil;
	BOOL rememberPIN = NO;
	[[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
	if([[NSApplication sharedApplication] runModalForWindow:self.pinDialog]) {
		enteredPIN  = [self.pinTextField stringValue];
		rememberPIN = [self.rememberPINCheckbox state];
		if(rememberPIN) {
			self.pin = enteredPIN;
		}
		
		if ([[[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath:kIsPINExpiresKey] intValue]) {
			uint32_t timeout = [[[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath:kPINExpiresInKey] intValue];
			NSLog(@"PIN will expire in %d min",timeout);
			NSTimer *timer = [NSTimer timerWithTimeInterval:(timeout*60) target:self selector:@selector(forgetPINAction:) userInfo:nil repeats:NO];
			[[NSRunLoop mainRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
		}
	}
	
	[self.pinDialog orderOut:self];
	[self.pinTextField setStringValue:@""];
	[self.pinTextField becomeFirstResponder];
	[self.rememberPINCheckbox setState:NSOffState];
	
	return enteredPIN;
}

- (IBAction) forgetPINAction:(id)sender {
	NSLog(@"forgetting PIN");
	self.pin = nil;
}

- (void) deviceAdded:(NSString*)name {
	NSLog(@"deviceAdded:%@",name);
	self.statusItem.image = [NSImage imageNamed:@"yubikey-c"];

	if([[[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath:kExecSSHADDOnInsertionKey] intValue]){
		NSLog(@"will ssh-add -s");
		NSString *pin = [self getPIN];
		if (!pin) {
			NSLog(@"no PIN was supplied");
			return;
		}
		
		NSArray *args = @[
			@"-s",
			[[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath:kPKCSPathKey],
			@"-p",
			pin
		];
		
		sleep(1);
		
		NSString *stdoutStr, *stderrStr;
		uint32_t result;
		result = [self execSystemCmd:[[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath:kSSHADDPathKey] withArgs:args withStdOut:&stdoutStr withStdErr:&stderrStr];
		if (!result) 
			self.statusItem.image = [NSImage imageNamed:@"yubikey-ok"];
		else
			self.statusItem.image = [NSImage imageNamed:@"yubikey-ng"];
	}

	if([[[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath:kWakeScreenOnInsertionKey] intValue]){
		NSLog(@"will wake screen");
		IOPMAssertionID assertionID;
        IOPMAssertionDeclareUserActivity(CFSTR(""), kIOPMUserActiveLocal, &assertionID);
	}
}

- (void) deviceRemoved:(NSString*)name {
	NSLog(@"deviceRemoved:%@",name);
	self.statusItem.image = [NSImage imageNamed:@"yubikey"];
	
	if([[[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath:kExecSSHADDOnRemovalKey] intValue]){
		NSLog(@"will ssh-add -e");
		NSArray *args = @[
			@"-e",
			[[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath:kPKCSPathKey],
		];
		NSString *stdoutStr, *stderrStr;
		uint32_t result;
		result = [self execSystemCmd:[[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath:kSSHADDPathKey] withArgs:args withStdOut:&stdoutStr withStdErr:&stderrStr];
	}

	if([[[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath:kSleepScreenOnRemovalKey] intValue]){
		NSLog(@"will sleep screen");
		io_registry_entry_t reg = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/IOResources/IODisplayWrangler");
		if (reg) {
			IORegistryEntrySetCFProperty(reg, CFSTR("IORequestIdle"), kCFBooleanTrue);
			IOObjectRelease(reg);
		}
		
		if([[[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath:kLockScreenOnRemovalKey] intValue]){
			CFMessagePortRef port = CFMessagePortCreateRemote(kCFAllocatorDefault, CFSTR("com.apple.loginwindow.notify"));
			if(port) {
				CFMessagePortSendRequest(port, 600, NULL, 0, 0, NULL, NULL);
				CFRelease(port);
			} else {
				extern void SACLockScreenImmediate() __attribute__((weak_import, weak));;
				SACLockScreenImmediate();
			}
		}
	}
}

- (int32_t)execSystemCmd:(NSString*)cmd withArgs:(NSArray*)args withStdOut:(NSString**)stdoutStr withStdErr:(NSString**)stderrStr {
	NSPipe *stdoutPipe = [NSPipe pipe];
	NSFileHandle *stdoutFile = stdoutPipe.fileHandleForReading;
	NSPipe *stderrPipe = [NSPipe pipe];
	NSFileHandle *stderrFile = stderrPipe.fileHandleForReading;

	NSTask *task = [[NSTask alloc] init];
	task.launchPath = cmd;
	task.arguments = args;
	task.standardOutput = stdoutPipe;
	task.standardError = stderrPipe;

	[task launch];
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
	io_iterator_t iterator;
	kr = IOServiceAddMatchingNotification(notifyPort, kIOFirstMatchNotification, matchDict, IOServiceMatchedCallback, nil, &iterator);

	io_service_t usbDevice;
	io_name_t devName;
	while (usbDevice=IOIteratorNext(iterator)) {
		IORegistryEntryGetName(usbDevice, devName);
		NSLog(@"initial device found:%x:%s",usbDevice,devName);
		self.statusItem.image = [NSImage imageNamed:@"yubikey-c"];
	}

	CFMutableDictionaryRef terminateDict = (__bridge_retained CFMutableDictionaryRef)@{
		@kIOProviderClassKey : @kIOUSBDeviceClassName,
		@kUSBProductID : @"*",
		@kUSBVendorID : @0x1050
	};

	kr = IOServiceAddMatchingNotification(notifyPort, kIOTerminatedNotification, terminateDict, IOServiceTerminatedCallback, nil, &iterator);
	while (usbDevice=IOIteratorNext(iterator)) {
		IORegistryEntryGetName(usbDevice, devName);
		NSLog(@"device found for termination:%x:%s",usbDevice,devName);
	}
}

void IOServiceMatchedCallback(void* refcon, io_iterator_t iterator) {
	NSLog(@"IOServiceMatchedCallback");
	io_service_t usbDevice;
	io_name_t devName;
	
	while (usbDevice=IOIteratorNext(iterator)) {
		IORegistryEntryGetName(usbDevice, devName);
		NSLog(@"device added:%x:%s",usbDevice,devName);
	}

	[((YubiKey_observerAppDelegate*)[NSApp delegate]) deviceAdded:[[NSString alloc] initWithCString:devName]];
}

void IOServiceTerminatedCallback(void* refcon, io_iterator_t iterator) {
	NSLog(@"IOServiceTerminatedCallback");
	io_service_t usbDevice;
	io_name_t devName;
	BOOL removed=NO;
	
	while (usbDevice=IOIteratorNext(iterator)) {
		IORegistryEntryGetName(usbDevice, devName);
		NSLog(@"device removed:%x:%s",usbDevice,devName);
	}
	
	[((YubiKey_observerAppDelegate*)[NSApp delegate]) deviceRemoved:[[NSString alloc] initWithCString:devName]];
}
@end

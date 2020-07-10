//
//  SystemCommandExecutor.m
//  YubiKey-observer
//
//  Created by bluebox on 2020/07/08.
//  Copyright © 2020 cx.lab. All rights reserved.
//

#import "SystemCommandExecutor.h"

@implementation SystemCommandExecutor

+ (instancetype) initWithCmd:(NSString*)cmd withArgs:(NSArray*)args withStdIn:(NSArray*)stdinArgs {
	SystemCommandExecutor *executor = [self new];
	executor.execPath = cmd;
	executor.args = args;
	executor.stdIn = stdinArgs;
	return executor;
}

- (int32_t) execSystemCommand:(NSString*)cmd withArgs:(NSArray*)args withStdIn:(NSArray*)stdinArgs {
	self.execPath = cmd;
	self.args = args;
	self.stdIn = stdinArgs;
	return [self execute];
}

- (int32_t) execute {
	
	if((!self.execPath) || [self.execPath length]==0)
		return EINVAL;

	NSPipe *stdoutPipe = [NSPipe pipe];
	NSFileHandle *stdoutFile = stdoutPipe.fileHandleForReading;
	NSPipe *stderrPipe = [NSPipe pipe];
	NSFileHandle *stderrFile = stderrPipe.fileHandleForReading;
	NSPipe *stdinPipe = [NSPipe pipe];
	NSFileHandle *stdinFile = stdinPipe.fileHandleForWriting;

	NSTask *task = [NSTask new];
	task.launchPath = self.execPath;
	task.arguments = self.args;
	task.standardOutput = stdoutPipe;
	task.standardError = stderrPipe;
	task.standardInput = stdinPipe;

	[task launch];
	[self.stdIn enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL *stop){
		[stdinFile writeData:[obj dataUsingEncoding:NSUTF8StringEncoding]];
	}];
	[task waitUntilExit];

	_stdoutData = [stdoutFile readDataToEndOfFile];
	[stdoutFile closeFile];

	_stderrData = [stderrFile readDataToEndOfFile];
	[stderrFile closeFile];

//	NSLog(@"execSystemCmd(%@):terminationStatus: %d\nstdout: %@\nstderr: %@",self.execPath,task.terminationStatus,self.stdoutData,self.stderrData);
	return task.terminationStatus;
}

- (NSString*) stdoutStr {
	NSString *stdoutStr;
	stdoutStr = [[NSString alloc] initWithData: self.stdoutData encoding: NSUTF8StringEncoding];
	return stdoutStr;
}

- (NSString*) stderrStr {
	NSString *stderrStr;
	stderrStr = [[NSString alloc] initWithData: self.stderrData encoding: NSUTF8StringEncoding];
	return stderrStr;
}

@end

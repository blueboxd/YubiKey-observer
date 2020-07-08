//
//  SystemCommandExecutor.h
//  YubiKey-observer
//
//  Created by bluebox on 2020/07/08.
//  Copyright © 2020 cx.lab. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SystemCommandExecutor : NSObject

@property NSString *execPath;
@property NSArray *args;
@property NSArray *stdIn;
@property (readonly) NSData *stdoutData;
@property (readonly) NSData *stderrData;
@property (readonly,nonatomic) NSString *stdoutStr;
@property (readonly,nonatomic) NSString *stderrStr;

+ (instancetype) initWithCmd:(NSString*)cmd withArgs:(NSArray* _Nullable)args withStdIn:(NSArray* _Nullable)stdinArgs;
- (int32_t) execute;
- (int32_t) execSystemCommand:(NSString*)cmd withArgs:(NSArray* _Nullable)args withStdIn:(NSArray* _Nullable)stdinArgs;
@end

NS_ASSUME_NONNULL_END

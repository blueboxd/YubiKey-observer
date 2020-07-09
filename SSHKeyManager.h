//
//  SSHKeyManager.h
//  YubiKey-observer
//
//  Created by bluebox on 2020/07/08.
//  Copyright © 2020 cx.lab. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SSHKeyManagerDelegate <NSObject>

- (void) keyStoreChanged:(NSArray<NSDictionary*>*)keys;

@end

#define sshKeyID @"id"
#define sshKeyBits @"bits"
#define sshKeyHash @"hash"
#define sshKeyAlgo @"algo"
#define sshKeyOurs @"ours"

@interface SSHKeyManager : NSObject
- (int32_t) addSSHKeyWithPin:(NSString*)pin;
- (int32_t) removeSSHKey;
- (NSArray* _Nullable) enumerateSSHKeys;
@property (nonatomic) BOOL isSSHKeyFomYubiKeyAdded;

@property (strong) IBOutlet NSUserDefaultsController *prefsController;

@property (weak, nonatomic) IBOutlet id <SSHKeyManagerDelegate> delegate;
@end

NS_ASSUME_NONNULL_END

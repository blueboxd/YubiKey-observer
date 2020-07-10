//
//  SSHKeyManager.h
//  YubiKey-observer
//
//  Created by bluebox on 2020/07/08.
//  Copyright © 2020 cx.lab. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString* const SSHKeyManagerSSHKeyDictionaryHashKey;
extern NSString* const SSHKeyManagerSSHKeyDictionaryNameKey;
extern NSString* const SSHKeyManagerSSHKeyDictionaryAlgoKey;
extern NSString* const SSHKeyManagerSSHKeyDictionaryBitsKey;
extern NSString* const SSHKeyManagerSSHKeyDictionaryOursKey;

extern NSNotificationName SSHKeyManagerKeyStoreDidChangeNotificationKey;

@interface SSHKeyManager : NSObject
- (void) refreshKeyStore;
- (int32_t) addSSHKeyWithPin:(NSString*)pin;
- (int32_t) removeSSHKey;
- (NSArray* _Nullable) enumerateSSHKeys;
@end

NS_ASSUME_NONNULL_END

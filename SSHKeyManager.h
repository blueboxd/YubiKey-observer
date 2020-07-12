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
extern NSNotificationName SSHKeyManagerCommandFailedNotificationKey;
extern NSString* const SSHKeyManagerCommandFailedActionKey;
extern NSString* const SSHKeyManagerCommandFailedActionAddKey;
extern NSString* const SSHKeyManagerCommandFailedActionRemoveKey;
extern NSString* const SSHKeyManagerCommandFailedErrorKey;
extern NSString* const SSHKeyManagerCommandFailedStdErrStrKey;

@interface SSHKeyManager : NSObject
- (void) refreshKeyStore;
- (int32_t) addSSHKeyWithPin:(NSString*)pin;
- (int32_t) removeSSHKey;
- (NSDictionary* _Nullable) enumerateSSHKeys;
- (BOOL) hasOurKey;
@end

NS_ASSUME_NONNULL_END

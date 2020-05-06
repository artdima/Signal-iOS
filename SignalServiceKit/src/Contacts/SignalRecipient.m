//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "SignalRecipient.h"
#import "OWSDevice.h"
#import "ProfileManagerProtocol.h"
#import "SSKEnvironment.h"
#import "SSKSessionStore.h"
#import "TSAccountManager.h"
#import "TSSocketManager.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

const NSUInteger SignalRecipientSchemaVersion = 1;

@interface SignalRecipient ()

@property (nonatomic) NSOrderedSet<NSNumber *> *devices;
@property (nonatomic) NSUInteger recipientSchemaVersion;

@end

#pragma mark -

@implementation SignalRecipient

#pragma mark - Dependencies

- (id<ProfileManagerProtocol>)profileManager
{
    return SSKEnvironment.shared.profileManager;
}

- (id<OWSUDManager>)udManager
{
    return SSKEnvironment.shared.udManager;
}

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);
    
    return SSKEnvironment.shared.tsAccountManager;
}

- (TSSocketManager *)socketManager
{
    OWSAssertDebug(SSKEnvironment.shared.socketManager);
    
    return SSKEnvironment.shared.socketManager;
}

+ (id<StorageServiceManagerProtocol>)storageServiceManager
{
    return SSKEnvironment.shared.storageServiceManager;
}

+ (SSKSessionStore *)sessionStore
{
    return SSKEnvironment.shared.sessionStore;
}

#pragma mark -

+ (instancetype)getOrBuildUnsavedRecipientForAddress:(SignalServiceAddress *)address
                                         transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(address.isValid);

    SignalRecipient *_Nullable recipient = [self registeredRecipientForAddress:address
                                                               mustHaveDevices:NO
                                                                   transaction:transaction];
    if (!recipient) {
        recipient = [[self alloc] initWithAddress:address];
    }
    return recipient;
}

- (instancetype)initWithAddress:(SignalServiceAddress *)address
{
    self = [super init];

    if (!self) {
        return self;
    }

    _recipientUUID = address.uuidString;
    _recipientPhoneNumber = address.phoneNumber;
    _recipientSchemaVersion = SignalRecipientSchemaVersion;

    _devices = [NSOrderedSet orderedSetWithObject:@(OWSDevicePrimaryDeviceId)];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (_devices == nil) {
        _devices = [NSOrderedSet new];
    }

    // Migrating from an everyone has a phone number world to a
    // world in which we have UUIDs
    if (_recipientSchemaVersion < 1) {
        // Copy uniqueId to recipientPhoneNumber
        _recipientPhoneNumber = [coder decodeObjectForKey:@"uniqueId"];

        OWSAssert(_recipientPhoneNumber != nil);
    }

    // Since we use device count to determine whether a user is registered or not,
    // ensure the local user always has at least *this* device.
    if (![_devices containsObject:@(OWSDevicePrimaryDeviceId)]) {
        if (self.address.isLocalAddress) {
            DDLogInfo(@"Adding primary device to self recipient.");
            [self addDevices:[NSSet setWithObject:@(OWSDevicePrimaryDeviceId)]];
        }
    }

    _recipientSchemaVersion = SignalRecipientSchemaVersion;

    return self;
}

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
                         devices:(NSOrderedSet<NSNumber *> *)devices
            recipientPhoneNumber:(nullable NSString *)recipientPhoneNumber
                   recipientUUID:(nullable NSString *)recipientUUID
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId];

    if (!self) {
        return self;
    }

    _devices = devices;
    _recipientPhoneNumber = recipientPhoneNumber;
    _recipientUUID = recipientUUID;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

+ (AnySignalRecipientFinder *)recipientFinder
{
    return [AnySignalRecipientFinder new];
}

+ (nullable instancetype)registeredRecipientForAddress:(SignalServiceAddress *)address
                                       mustHaveDevices:(BOOL)mustHaveDevices
                                           transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(address.isValid);
    SignalRecipient *_Nullable signalRecipient = [self.recipientFinder signalRecipientForAddress:address
                                                                                     transaction:transaction];
    if (mustHaveDevices && signalRecipient.devices.count < 1) {
        return nil;
    }

    return signalRecipient;
}

#pragma mark -

- (void)addDevices:(NSSet<NSNumber *> *)devices
{
    OWSAssertDebug(devices.count > 0);

    NSMutableOrderedSet<NSNumber *> *updatedDevices = [self.devices mutableCopy];
    [updatedDevices unionSet:devices];
    self.devices = [updatedDevices copy];
}

- (void)removeDevices:(NSSet<NSNumber *> *)devices
{
    OWSAssertDebug(devices.count > 0);

    NSMutableOrderedSet<NSNumber *> *updatedDevices = [self.devices mutableCopy];
    [updatedDevices minusSet:devices];
    self.devices = [updatedDevices copy];
}

- (void)updateRegisteredRecipientWithDevicesToAdd:(nullable NSArray<NSNumber *> *)devicesToAdd
                                  devicesToRemove:(nullable NSArray<NSNumber *> *)devicesToRemove
                                      transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(devicesToAdd.count > 0 || devicesToRemove.count > 0);

    // Add before we remove, since removeDevicesFromRecipient:...
    // can markRecipientAsUnregistered:... if the recipient has
    // no devices left.
    if (devicesToAdd.count > 0) {
        [self addDevicesToRegisteredRecipient:[NSSet setWithArray:devicesToAdd] transaction:transaction];
    }
    if (devicesToRemove.count > 0) {
        [self removeDevicesFromRecipient:[NSSet setWithArray:devicesToRemove] transaction:transaction];
    }

    // Device changes
    dispatch_async(dispatch_get_main_queue(), ^{
        // Device changes can affect the UD access mode for a recipient,
        // so we need to fetch the profile for this user to update UD access mode.
        [self.profileManager updateProfileForAddress:self.address];

        if (self.address.isLocalAddress) {
            [self.socketManager cycleSocket];
        }
    });
}

- (void)addDevicesToRegisteredRecipient:(NSSet<NSNumber *> *)devices transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(devices.count > 0);
    OWSLogDebug(@"adding devices: %@, to recipient: %@", devices, self);

    [self anyReloadWithTransaction:transaction];
    [self anyUpdateWithTransaction:transaction
                             block:^(SignalRecipient *signalRecipient) {
                                 [signalRecipient addDevices:devices];
                             }];
}

- (void)removeDevicesFromRecipient:(NSSet<NSNumber *> *)devices transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(devices.count > 0);

    OWSLogDebug(@"removing devices: %@, from registered recipient: %@", devices, self);
    [self anyReloadWithTransaction:transaction ignoreMissing:YES];
    [self anyUpdateWithTransaction:transaction
                             block:^(SignalRecipient *signalRecipient) {
                                 [signalRecipient removeDevices:devices];
                             }];
}

#pragma mark -

- (SignalServiceAddress *)address
{
    return [[SignalServiceAddress alloc] initWithUuidString:self.recipientUUID phoneNumber:self.recipientPhoneNumber];
}

#pragma mark -

- (NSComparisonResult)compare:(SignalRecipient *)other
{
    return [self.address compare:other.address];
}

- (void)anyWillInsertWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyWillInsertWithTransaction:transaction];

    OWSLogVerbose(@"Inserted signal recipient: %@ (%lu)", self.address, (unsigned long)self.devices.count);
}

- (void)anyWillUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyWillUpdateWithTransaction:transaction];

    OWSLogVerbose(@"Updated signal recipient: %@ (%lu)", self.address, (unsigned long)self.devices.count);
}

+ (BOOL)isRegisteredRecipient:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(address.isValid);
    return nil != [self registeredRecipientForAddress:address mustHaveDevices:YES transaction:transaction];
}

+ (SignalRecipient *)markRecipientAsRegisteredAndGet:(SignalServiceAddress *)address
                                         transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(transaction);

    SignalRecipient *_Nullable phoneNumberInstance = nil;
    SignalRecipient *_Nullable uuidInstance = nil;
    if (address.phoneNumber != nil) {
        phoneNumberInstance = [self.recipientFinder signalRecipientForPhoneNumber:address.phoneNumber
                                                                      transaction:transaction];
    }
    if (address.uuid != nil) {
        uuidInstance = [self.recipientFinder signalRecipientForUUID:address.uuid transaction:transaction];
    }

    BOOL shouldUpdate = NO;
    SignalRecipient *_Nullable existingInstance = nil;

    if (phoneNumberInstance != nil && uuidInstance != nil) {
        if ([NSObject isNullableObject:phoneNumberInstance.recipientPhoneNumber
                               equalTo:uuidInstance.recipientPhoneNumber]
            && [NSObject isNullableObject:phoneNumberInstance.recipientUUID equalTo:uuidInstance.recipientUUID]) {
            existingInstance = phoneNumberInstance;
        } else {
            // We have separate recipients in the db for the uuid and phone number.
            // There isn't an ideal way to do this, but we need to converge on one
            // recipient and discard the other.
            //
            // TODO: Should we clean up any state related to the discarded recipient?

            // We try to preserve the recipient that has a session.
            NSNumber *_Nullable sessionIndexForUuid =
                [self.sessionStore maxSessionSenderChainKeyIndexForAccountId:uuidInstance.accountId
                                                                 transaction:transaction];
            NSNumber *_Nullable sessionIndexForPhoneNumber =
                [self.sessionStore maxSessionSenderChainKeyIndexForAccountId:phoneNumberInstance.accountId
                                                                 transaction:transaction];

            if (SSKDebugFlags.verboseSignalRecipientLogging) {
                OWSLogInfo(@"phoneNumberInstance: %@", phoneNumberInstance);
                OWSLogInfo(@"uuidInstance: %@", uuidInstance);
                OWSLogInfo(@"sessionIndexForUuid: %@", sessionIndexForUuid);
                OWSLogInfo(@"sessionIndexForPhoneNumber: %@", sessionIndexForPhoneNumber);
            }

            // We want to retain the phone number recipient if it
            // has a session and the uuid recipient doesn't or if
            // both have a session but the phone number recipient
            // has seen more use.
            //
            // All things being equal, we default to retaining the
            // UUID recipient.
            BOOL shouldUseUuid = (sessionIndexForPhoneNumber.intValue > sessionIndexForUuid.intValue);
            if (shouldUseUuid) {
                OWSFailDebug(@"Discarding phone number recipient in favor of uuid recipient.");
                existingInstance = uuidInstance;
                [phoneNumberInstance anyRemoveWithTransaction:transaction];
            } else {
                OWSFailDebug(@"Discarding uuid recipient in favor of phone number recipient.");
                existingInstance = phoneNumberInstance;
                [uuidInstance anyRemoveWithTransaction:transaction];
            }
            shouldUpdate = YES;
        }
    } else if (phoneNumberInstance != nil) {
        existingInstance = phoneNumberInstance;
    } else if (uuidInstance != nil) {
        existingInstance = uuidInstance;
    }

    if (existingInstance == nil) {
        OWSLogDebug(@"creating recipient: %@", address);

        SignalRecipient *newInstance = [[self alloc] initWithAddress:address];
        [newInstance anyInsertWithTransaction:transaction];

        // Record with the new contact in the social graph
        [self.storageServiceManager recordPendingUpdatesWithUpdatedAccountIds:@[ newInstance.accountId ]];

        return newInstance;
    }

    if (existingInstance.devices.count == 0) {
        shouldUpdate = YES;

        // We know they're registered, so make sure they have at least one device.
        // We assume it's the default device. If we're wrong, the service will correct us when we
        // try to send a message to them
        existingInstance.devices = [NSOrderedSet orderedSetWithObject:@(OWSDevicePrimaryDeviceId)];
    }

    // If we've learned a users UUID, record it.
    if (existingInstance.recipientUUID == nil && address.uuid != nil) {
        shouldUpdate = YES;

        existingInstance.recipientUUID = address.uuidString;
    }

    // If we've learned a users phone number, record it.
    if (existingInstance.recipientPhoneNumber == nil && address.phoneNumber != nil) {
        shouldUpdate = YES;

        OWSFailDebug(@"unexpectedly learned about a users phone number");
        existingInstance.recipientPhoneNumber = address.phoneNumber;
    }

    // Record the updated contact in the social graph
    if (shouldUpdate) {
        [existingInstance anyOverwritingUpdateWithTransaction:transaction];
        [self.storageServiceManager recordPendingUpdatesWithUpdatedAccountIds:@[ existingInstance.accountId ]];
    }

    return existingInstance;
}

+ (void)markRecipientAsRegistered:(SignalServiceAddress *)address
                         deviceId:(UInt32)deviceId
                      transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(deviceId > 0);
    OWSAssertDebug(transaction);

    SignalRecipient *recipient = [self markRecipientAsRegisteredAndGet:address transaction:transaction];
    if (![recipient.devices containsObject:@(deviceId)]) {
        OWSLogDebug(@"Adding device %u to existing recipient.", (unsigned int)deviceId);

        [recipient anyReloadWithTransaction:transaction];
        [recipient anyUpdateWithTransaction:transaction
                                      block:^(SignalRecipient *signalRecipient) {
                                          [signalRecipient addDevices:[NSSet setWithObject:@(deviceId)]];
                                      }];
    }
}

+ (void)markRecipientAsUnregistered:(SignalServiceAddress *)address transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(transaction);

    SignalRecipient *recipient = [self getOrBuildUnsavedRecipientForAddress:address transaction:transaction];
    OWSLogDebug(@"Marking recipient as not registered: %@", address);
    if (recipient.devices.count > 0) {
        if ([SignalRecipient anyFetchWithUniqueId:recipient.uniqueId transaction:transaction] == nil) {
            [recipient removeDevices:recipient.devices.set];
            [recipient anyInsertWithTransaction:transaction];
        } else {
            [recipient anyUpdateWithTransaction:transaction
                                          block:^(SignalRecipient *signalRecipient) {
                                              signalRecipient.devices = [NSOrderedSet new];
                                          }];
        }

        // Remove the contact from our social graph
        [self.storageServiceManager recordPendingDeletionsWithDeletedAccountIds:@[ recipient.accountId ]];
    }
}

@end

NS_ASSUME_NONNULL_END

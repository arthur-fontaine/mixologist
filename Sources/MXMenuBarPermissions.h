#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The outcome of reconciling Control Center's approvals with what should be hidden.
@interface MXPermissionReconciliation : NSObject
@property (nonatomic, readonly, copy) NSArray *entries;
@property (nonatomic, readonly, copy) NSSet<NSString *> *journal;
@property (nonatomic, readonly, getter=hasChanges) BOOL changes;

/// Pure: `entries` is Control Center's `trackedApplications` (a flat
/// [location, record, …] array), `journal` the apps Mixologist turned off
/// earlier, `target` the apps that should be off now. An app that is off but
/// not in the journal was turned off by the user and is never touched.
+ (instancetype)reconcileEntries:(NSArray *)entries
                         journal:(NSSet<NSString *> *)journal
                          target:(NSSet<NSString *> *)target;
@end

/// Hides apps by turning off their "Allow in the Menu Bar" approval, the switch
/// System Settings › Menu Bar shows. Unlike the restriction, this leaves
/// Control Center modules such as Now Playing alone, but it also outlives the
/// process: every app Mixologist turns off is journaled first so a later launch,
/// or `--restore-menu-bar-permissions`, can turn it back on.
@interface MXMenuBarPermissions : NSObject

@property (class, nonatomic, readonly) MXMenuBarPermissions *shared;

/// NO when the CoreFoundation calls this relies on are missing.
@property (nonatomic, readonly, getter=isAvailable) BOOL available;
/// Apps Mixologist has turned off and not yet turned back on.
@property (nonatomic, readonly, copy) NSSet<NSString *> *journal;

/// Makes `bundleIdentifiers` exactly the set of apps Mixologist keeps turned
/// off: turns them off, and turns back on any it turned off before that is no
/// longer listed. Writes only when something changes.
- (BOOL)turnOffExactly:(NSSet<NSString *> *)bundleIdentifiers error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

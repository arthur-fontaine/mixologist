#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Immutable description of the allow list handed to the macOS visibility
/// restriction service. Kept free of AppKit/AX so it can be unit tested from the
/// command line.
@interface MXVisibilityPlan : NSObject

@property (nonatomic, readonly) BOOL shouldRestrict;
@property (nonatomic, copy, readonly) NSArray<NSString *> *allowedBundleIdentifiers;
/// `MBSystemItemIdentifier` raw values (NSNumber) that stay visible: all nine
/// minus the ones the user hid. Leaving one out hides that Apple module even
/// though MenuBarAgent, which draws it, stays in the bundle allow list.
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *allowedSystemItemRawValues;
@property (nonatomic, copy, readonly) NSString *signature;

+ (instancetype)planWithScannedBundleIdentifiers:(NSSet<NSString *> *)scannedBundleIdentifiers
                          runningBundleIdentifiers:(NSSet<NSString *> *)runningBundleIdentifiers
                                hiddenBundleIdentifiers:(NSSet<NSString *> *)hiddenBundleIdentifiers
                                      hiddenSystemItems:(NSSet<NSNumber *> *)hiddenSystemItems
                                       ownBundleIdentifier:(nullable NSString *)ownBundleIdentifier;

/// Maps an Apple module's AX identifier (`com.apple.menuextra.clock`, …) to its
/// `MBSystemItemIdentifier` raw value, or nil for items the API cannot address.
+ (nullable NSNumber *)systemItemRawValueForItemIdentifier:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END

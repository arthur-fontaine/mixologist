#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Immutable description of the allow list handed to the macOS visibility
/// restriction service. Kept free of AppKit/AX so it can be unit tested from the
/// command line.
@interface MXVisibilityPlan : NSObject

@property (nonatomic, readonly) BOOL shouldRestrict;
@property (nonatomic, copy, readonly) NSArray<NSString *> *allowedBundleIdentifiers;
/// `MBSystemItemIdentifier` raw values (NSNumber). Keeping all nine visible is
/// what prevents the restriction from also hiding Apple's Clock, Wi-Fi and
/// Control Center items.
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *allowedSystemItemRawValues;
@property (nonatomic, copy, readonly) NSString *signature;

+ (instancetype)planWithScannedBundleIdentifiers:(NSSet<NSString *> *)scannedBundleIdentifiers
                          runningBundleIdentifiers:(NSSet<NSString *> *)runningBundleIdentifiers
                                hiddenBundleIdentifiers:(NSSet<NSString *> *)hiddenBundleIdentifiers
                                       ownBundleIdentifier:(nullable NSString *)ownBundleIdentifier;

@end

NS_ASSUME_NONNULL_END

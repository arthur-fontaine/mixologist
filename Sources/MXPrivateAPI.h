#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^MXAssessmentCompletion)(NSError * _Nullable error);

/// Thin, defensive wrapper around the private MenuBarClientCore assessment-mode
/// API introduced with the macOS 26/27 menu bar agent.
///
/// No private headers are required: the framework is loaded with dlopen and the
/// two Objective-C classes are looked up by name. If any step fails the wrapper
/// reports itself unavailable instead of crashing.
@interface MXAssessmentMode : NSObject

@property (class, nonatomic, readonly) MXAssessmentMode *shared;

@property (nonatomic, readonly, getter=isAvailable) BOOL available;
@property (nonatomic, readonly, getter=isActive) BOOL active;
@property (nonatomic, readonly, copy, nullable) NSString *unavailableReason;

/// Raw values of the nine system menu-bar items understood by the private
/// assessment API, in `MBSystemItemIdentifier` order.
///
/// Passing these keeps Apple's own menu-bar items visible while a bundle allow
/// list hides third-party items. Items the user has already turned off in
/// Control Center stay off; the allow list does not force them on.
@property (class, nonatomic, readonly) NSArray<NSNumber *> *allSystemItemRawValues;

/// Activate a visibility restriction that keeps only the listed system items
/// and bundle identifiers visible. Passing empty arrays hides every item.
- (BOOL)activateWithAllowedSystemItems:(NSArray<NSNumber *> *)systemItems
               allowedBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers
                            completion:(nullable MXAssessmentCompletion)completion;

/// Release the restriction. Safe to call repeatedly.
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END

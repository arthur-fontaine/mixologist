#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MXMenuItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *help;
@property (nonatomic, copy) NSString *role;
@property (nonatomic, copy) NSString *subrole;
@property (nonatomic) NSRect frame;
@property (nonatomic, getter=isSystemItem) BOOL systemItem;
@end

@interface MXAppMenuItems : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSString *bundlePath;
@property (nonatomic) pid_t processIdentifier;
@property (nonatomic, copy) NSArray<MXMenuItem *> *items;
@property (nonatomic, getter=isSystemApp) BOOL systemApp;
@end

@interface MXScanResult : NSObject
@property (nonatomic, copy) NSArray<MXAppMenuItems *> *apps;
/// Unique non-empty AX identifiers of Apple's own menu bar modules.
@property (nonatomic, copy) NSArray<NSString *> *systemItemIdentifiers;
/// Bundle identifiers of third-party apps that currently expose menu bar items.
@property (nonatomic, copy) NSArray<NSString *> *thirdPartyBundleIdentifiers;
/// Bundle identifiers of every running application we could identify.
@property (nonatomic, copy) NSArray<NSString *> *runningBundleIdentifiers;
@property (nonatomic, getter=isAccessibilityTrusted) BOOL accessibilityTrusted;
@property (nonatomic, copy) NSDate *date;
@property (nonatomic) NSTimeInterval duration;
@end

@interface MXMenuBarScanner : NSObject

/// Returns YES when the process already has Accessibility access. When prompt is
/// YES macOS shows its own consent dialog (the app should call this sparingly).
+ (BOOL)accessibilityTrustedWithPrompt:(BOOL)prompt;

/// Synchronous scan. Call from a background queue; it performs IPC with every
/// running application and can take a few hundred milliseconds.
- (MXScanResult *)scan;

@end

NS_ASSUME_NONNULL_END

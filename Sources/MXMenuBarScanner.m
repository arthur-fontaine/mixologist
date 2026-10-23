#import "MXMenuBarScanner.h"
#import <ApplicationServices/ApplicationServices.h>

static CFStringRef const kMXExtrasMenuBarAttribute = CFSTR("AXExtrasMenuBar");
static const NSUInteger kMXMaximumTreeDepth = 6;

@implementation MXMenuItem
- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ id=%@ frame=%@>", self.title, self.identifier,
            NSStringFromRect(self.frame)];
}
@end

@implementation MXAppMenuItems
- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ %@ items=%lu>", self.appName,
            self.bundleIdentifier, (unsigned long)self.items.count];
}
@end

@implementation MXScanResult
- (instancetype)init {
    self = [super init];
    if (self) {
        _apps = @[];
        _systemItemIdentifiers = @[];
        _thirdPartyBundleIdentifiers = @[];
        _runningBundleIdentifiers = @[];
        _date = [NSDate date];
    }
    return self;
}
@end

static id MXCopyAttribute(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = NULL;
    AXError error = AXUIElementCopyAttributeValue(element, attribute, &value);
    if (error != kAXErrorSuccess || value == NULL) {
        return nil;
    }
    return CFBridgingRelease(value);
}

static NSString *MXStringAttribute(AXUIElementRef element, CFStringRef attribute) {
    id value = MXCopyAttribute(element, attribute);
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static BOOL MXReadFrame(AXUIElementRef element, NSRect *outFrame) {
    if (!outFrame) {
        return NO;
    }
    id positionValue = MXCopyAttribute(element, kAXPositionAttribute);
    id sizeValue = MXCopyAttribute(element, kAXSizeAttribute);
    if (!positionValue || !sizeValue) {
        return NO;
    }
    if (CFGetTypeID((__bridge CFTypeRef)positionValue) != AXValueGetTypeID() ||
        CFGetTypeID((__bridge CFTypeRef)sizeValue) != AXValueGetTypeID()) {
        return NO;
    }
    CGPoint point = CGPointZero;
    CGSize size = CGSizeZero;
    BOOL havePoint = AXValueGetValue((__bridge AXValueRef)positionValue, kAXValueCGPointType, &point);
    BOOL haveSize = AXValueGetValue((__bridge AXValueRef)sizeValue, kAXValueCGSizeType, &size);
    if (!havePoint || !haveSize) {
        return NO;
    }
    *outFrame = NSMakeRect(point.x, point.y, size.width, size.height);
    return YES;
}

static BOOL MXBundleIsSystem(NSString *bundleIdentifier) {
    static NSSet<NSString *> *systemBundleIdentifiers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        systemBundleIdentifiers = [NSSet setWithArray:@[
            @"com.apple.controlcenter",
            @"com.apple.systemuiserver",
            @"com.apple.MenuBarAgent",
            @"com.apple.Spotlight",
            @"com.apple.Siri",
            @"com.apple.notificationcenterui",
            @"com.apple.controlcenterui",
        ]];
    });
    if (!bundleIdentifier.length) {
        return NO;
    }
    // Every Apple-owned process is treated as system: its status items are never
    // candidates for hiding, and treating them as system also keeps their item
    // identifiers in the system allow list.
    if ([bundleIdentifier hasPrefix:@"com.apple."]) {
        return YES;
    }
    return [systemBundleIdentifiers containsObject:bundleIdentifier];
}

static BOOL MXIdentifierLooksLikeSystemItem(NSString *identifier) {
    if (!identifier.length) {
        return NO;
    }
    return [identifier hasPrefix:@"com.apple.menuextra."] ||
           [identifier hasPrefix:@"com.apple.controlcenter-"] ||
           [identifier hasPrefix:@"com.apple.MenuBarAgent."];
}

static void MXCollectItems(AXUIElementRef element,
                           NSString *bundleIdentifier,
                           BOOL systemApp,
                           NSUInteger depth,
                           NSMutableArray<MXMenuItem *> *items,
                           NSMutableSet<NSString *> *seenKeys) {
    if (depth > kMXMaximumTreeDepth) {
        return;
    }

    NSString *role = MXStringAttribute(element, kAXRoleAttribute);
    NSString *subrole = MXStringAttribute(element, kAXSubroleAttribute);
    BOOL isMenuBarItem = [role isEqualToString:(__bridge NSString *)kAXMenuBarItemRole];
    if (isMenuBarItem) {
        NSString *title = MXStringAttribute(element, kAXTitleAttribute);
        NSString *description = MXStringAttribute(element, kAXDescriptionAttribute);
        NSString *help = MXStringAttribute(element, kAXHelpAttribute);
        NSString *identifier = MXStringAttribute(element, kAXIdentifierAttribute);

        NSString *displayTitle = title.length ? title : (description.length ? description : help);
        if (!displayTitle.length) {
            displayTitle = identifier.length ? identifier : @"Item";
        }

        NSRect frame = NSZeroRect;
        MXReadFrame(element, &frame);

        BOOL systemItem = systemApp || MXIdentifierLooksLikeSystemItem(identifier);
        NSString *key = [NSString stringWithFormat:@"%@|%@|%@|%.0f|%.0f",
                         bundleIdentifier ?: @"", identifier ?: @"", displayTitle,
                         frame.origin.x, frame.origin.y];
        if (![seenKeys containsObject:key]) {
            [seenKeys addObject:key];
            MXMenuItem *item = [[MXMenuItem alloc] init];
            item.title = displayTitle;
            item.identifier = identifier ?: @"";
            item.help = help ?: @"";
            item.role = role ?: @"";
            item.subrole = subrole ?: @"";
            item.frame = frame;
            item.systemItem = systemItem;
            [items addObject:item];
        }
    }

    id children = MXCopyAttribute(element, kAXChildrenAttribute);
    if ([children isKindOfClass:[NSArray class]]) {
        for (id child in (NSArray *)children) {
            if (CFGetTypeID((__bridge CFTypeRef)child) == AXUIElementGetTypeID()) {
                MXCollectItems((__bridge AXUIElementRef)child, bundleIdentifier, systemApp,
                               depth + 1, items, seenKeys);
            }
        }
    }
}

@implementation MXMenuBarScanner

+ (BOOL)accessibilityTrustedWithPrompt:(BOOL)prompt {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @(prompt)};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

- (MXScanResult *)scan {
    NSDate *started = [NSDate date];
    MXScanResult *result = [[MXScanResult alloc] init];
    result.accessibilityTrusted = [MXMenuBarScanner accessibilityTrustedWithPrompt:NO];

    NSMutableArray<MXAppMenuItems *> *apps = [NSMutableArray array];
    NSMutableOrderedSet<NSString *> *systemIdentifiers = [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet<NSString *> *thirdPartyBundleIDs = [NSMutableOrderedSet orderedSet];
    NSMutableOrderedSet<NSString *> *runningBundleIDs = [NSMutableOrderedSet orderedSet];

    NSString *ownBundleIdentifier = NSBundle.mainBundle.bundleIdentifier;

    for (NSRunningApplication *runningApp in NSWorkspace.sharedWorkspace.runningApplications) {
        NSString *bundleIdentifier = runningApp.bundleIdentifier;
        if (bundleIdentifier.length) {
            [runningBundleIDs addObject:bundleIdentifier];
        }
        if (!result.accessibilityTrusted) {
            continue;
        }
        if (runningApp.processIdentifier == NSProcessInfo.processInfo.processIdentifier) {
            continue;
        }

        @autoreleasepool {
            AXUIElementRef appElement = AXUIElementCreateApplication(runningApp.processIdentifier);
            if (!appElement) {
                continue;
            }
            AXUIElementSetMessagingTimeout(appElement, 0.35);

            // Only AXExtrasMenuBar holds status items. An app's regular
            // AXMenuBar exposes File/Edit/View/... and must never be treated as
            // a menu bar extra, otherwise every running app looks hideable.
            id extras = MXCopyAttribute(appElement, kMXExtrasMenuBarAttribute);
            BOOL systemApp = MXBundleIsSystem(bundleIdentifier);
            NSMutableArray<MXMenuItem *> *items = [NSMutableArray array];
            NSMutableSet<NSString *> *seenKeys = [NSMutableSet set];
            if (extras && CFGetTypeID((__bridge CFTypeRef)extras) == AXUIElementGetTypeID()) {
                MXCollectItems((__bridge AXUIElementRef)extras, bundleIdentifier ?: @"",
                               systemApp, 0, items, seenKeys);
            }
            CFRelease(appElement);

            if (!items.count) {
                continue;
            }

            [items sortUsingComparator:^NSComparisonResult(MXMenuItem *a, MXMenuItem *b) {
                if (a.frame.origin.x < b.frame.origin.x) return NSOrderedAscending;
                if (a.frame.origin.x > b.frame.origin.x) return NSOrderedDescending;
                return NSOrderedSame;
            }];

            MXAppMenuItems *app = [[MXAppMenuItems alloc] init];
            app.bundleIdentifier = bundleIdentifier ?: @"";
            app.appName = runningApp.localizedName ?: bundleIdentifier ?: @"Unknown";
            app.bundlePath = runningApp.bundleURL.path ?: @"";
            app.processIdentifier = runningApp.processIdentifier;
            app.items = items;
            app.systemApp = systemApp;
            [apps addObject:app];

            for (MXMenuItem *item in items) {
                if (item.isSystemItem && item.identifier.length) {
                    [systemIdentifiers addObject:item.identifier];
                }
            }
            if (!systemApp && bundleIdentifier.length &&
                ![bundleIdentifier isEqualToString:ownBundleIdentifier ?: @""]) {
                [thirdPartyBundleIDs addObject:bundleIdentifier];
            }
        }
    }

    [apps sortUsingComparator:^NSComparisonResult(MXAppMenuItems *a, MXAppMenuItems *b) {
        return [a.appName localizedCaseInsensitiveCompare:b.appName];
    }];

    result.apps = apps;
    result.systemItemIdentifiers = systemIdentifiers.array;
    result.thirdPartyBundleIdentifiers = thirdPartyBundleIDs.array;
    result.runningBundleIdentifiers = runningBundleIDs.array;
    result.duration = -[started timeIntervalSinceNow];
    result.date = [NSDate date];
    return result;
}

@end

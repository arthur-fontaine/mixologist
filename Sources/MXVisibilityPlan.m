#import "MXVisibilityPlan.h"
#import "MXPrivateAPI.h"

@implementation MXVisibilityPlan

+ (instancetype)planWithScannedBundleIdentifiers:(NSSet<NSString *> *)scannedBundleIdentifiers
                          runningBundleIdentifiers:(NSSet<NSString *> *)runningBundleIdentifiers
                                hiddenBundleIdentifiers:(NSSet<NSString *> *)hiddenBundleIdentifiers
                                      hiddenSystemItems:(NSSet<NSNumber *> *)hiddenSystemItems
                                       ownBundleIdentifier:(NSString *)ownBundleIdentifier {
    MXVisibilityPlan *plan = [[MXVisibilityPlan alloc] init];
    plan->_shouldRestrict = hiddenBundleIdentifiers.count > 0 || hiddenSystemItems.count > 0;

    NSMutableSet<NSString *> *allowed = [NSMutableSet set];
    [allowed unionSet:scannedBundleIdentifiers ?: [NSSet set]];
    // Running apps without a discovered status item still belong in the allow
    // list: a whitelist restriction would otherwise hide every new app the
    // moment it creates an item, before the next scan has seen it.
    [allowed unionSet:runningBundleIdentifiers ?: [NSSet set]];
    // Apple's own status-item owners stay allowed even when not seen running,
    // unless the user hid them (SystemUIServer owns VPN, for instance).
    [allowed addObjectsFromArray:@[@"com.apple.controlcenter", @"com.apple.systemuiserver"]];
    [allowed minusSet:hiddenBundleIdentifiers ?: [NSSet set]];
    if (ownBundleIdentifier.length) {
        [allowed addObject:ownBundleIdentifier];
    }
    // MenuBarAgent draws the Apple modules; those are hidden through the system
    // item list instead, so the agent itself is never taken out.
    [allowed addObject:@"com.apple.MenuBarAgent"];
    // Empty strings or unresolved placeholders must never reach the private API.
    [allowed filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *value, NSDictionary *bindings) {
        return value.length > 0 && ![value isEqualToString:@"(null)"];
    }]];

    NSMutableArray<NSNumber *> *systemItems = [NSMutableArray array];
    for (NSNumber *rawValue in MXAssessmentMode.allSystemItemRawValues) {
        if (![hiddenSystemItems containsObject:rawValue]) {
            [systemItems addObject:rawValue];
        }
    }

    plan->_allowedBundleIdentifiers = [[allowed allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    plan->_allowedSystemItemRawValues = systemItems;
    plan->_signature = [NSString stringWithFormat:@"b:%@|s:%@",
                        [plan->_allowedBundleIdentifiers componentsJoinedByString:@","],
                        [plan->_allowedSystemItemRawValues componentsJoinedByString:@","]];
    return plan;
}

+ (NSNumber *)systemItemRawValueForItemIdentifier:(NSString *)identifier {
    NSString *prefix = @"com.apple.menuextra.";
    if (![identifier hasPrefix:prefix]) {
        return nil;
    }
    NSString *name = [identifier substringFromIndex:prefix.length].lowercaseString;
    // Clock, Wi-Fi, Battery and Control Center were observed on macOS 27; the
    // other names follow the same pattern and are matched loosely.
    NSArray<NSArray *> *table = @[
        @[@0, @[@"battery"]],
        @[@1, @[@"bluetooth"]],
        @[@2, @[@"clock"]],
        @[@3, @[@"display"]],
        @[@4, @[@"keyboardbrightness", @"brightness"]],
        @[@5, @[@"sound", @"volume"]],
        @[@6, @[@"wifi", @"airport"]],
        @[@7, @[@"screenmirroring", @"airplay"]],
        @[@8, @[@"controlcenter"]],
    ];
    for (NSArray *entry in table) {
        for (NSString *candidate in entry[1]) {
            if ([name hasPrefix:candidate]) {
                return entry[0];
            }
        }
    }
    return nil;
}

+ (NSArray<NSString *> *)systemItemNames {
    // Indexed by raw value.
    return @[@"battery", @"bluetooth", @"clock", @"display", @"keyboardBrightness",
             @"sound", @"wifi", @"screenMirroring", @"controlCenter"];
}

+ (NSString *)nameForSystemItemRawValue:(NSInteger)rawValue {
    NSArray<NSString *> *names = [self systemItemNames];
    return rawValue >= 0 && rawValue < (NSInteger)names.count ? names[(NSUInteger)rawValue] : nil;
}

+ (NSNumber *)systemItemRawValueForName:(NSString *)name {
    NSUInteger index = [[self systemItemNames] indexOfObject:name];
    return index == NSNotFound ? nil : @(index);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<MXVisibilityPlan restrict=%d bundles=%lu system=%lu>",
            self.shouldRestrict,
            (unsigned long)self.allowedBundleIdentifiers.count,
            (unsigned long)self.allowedSystemItemRawValues.count];
}

@end

#import "MXVisibilityPlan.h"
#import "MXPrivateAPI.h"

@implementation MXVisibilityPlan

+ (instancetype)planWithScannedBundleIdentifiers:(NSSet<NSString *> *)scannedBundleIdentifiers
                          runningBundleIdentifiers:(NSSet<NSString *> *)runningBundleIdentifiers
                                hiddenBundleIdentifiers:(NSSet<NSString *> *)hiddenBundleIdentifiers
                                       ownBundleIdentifier:(NSString *)ownBundleIdentifier {
    MXVisibilityPlan *plan = [[MXVisibilityPlan alloc] init];
    plan->_shouldRestrict = hiddenBundleIdentifiers.count > 0;

    NSMutableSet<NSString *> *allowed = [NSMutableSet set];
    [allowed unionSet:scannedBundleIdentifiers ?: [NSSet set]];
    // Running apps without a discovered status item still belong in the allow
    // list: a whitelist restriction would otherwise hide every new app the
    // moment it creates an item, before the next scan has seen it.
    [allowed unionSet:runningBundleIdentifiers ?: [NSSet set]];
    [allowed minusSet:hiddenBundleIdentifiers ?: [NSSet set]];
    if (ownBundleIdentifier.length) {
        [allowed addObject:ownBundleIdentifier];
    }
    // Never hide the system menu bar owner itself.
    [allowed addObjectsFromArray:@[
        @"com.apple.controlcenter",
        @"com.apple.systemuiserver",
        @"com.apple.MenuBarAgent",
    ]];
    // Empty strings or unresolved placeholders must never reach the private API.
    [allowed filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *value, NSDictionary *bindings) {
        return value.length > 0 && ![value isEqualToString:@"(null)"];
    }]];

    plan->_allowedBundleIdentifiers = [[allowed allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    plan->_allowedSystemItemRawValues = MXAssessmentMode.allSystemItemRawValues;
    plan->_signature = [NSString stringWithFormat:@"b:%@|s:%@",
                        [plan->_allowedBundleIdentifiers componentsJoinedByString:@","],
                        [plan->_allowedSystemItemRawValues componentsJoinedByString:@","]];
    return plan;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<MXVisibilityPlan restrict=%d bundles=%lu system=%lu>",
            self.shouldRestrict,
            (unsigned long)self.allowedBundleIdentifiers.count,
            (unsigned long)self.allowedSystemItemRawValues.count];
}

@end

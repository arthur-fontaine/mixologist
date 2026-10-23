#import "MXSettingsStore.h"

static NSString *const kMXHiddenBundleIdentifiersKey = @"hiddenBundleIdentifiers";
static NSString *const kMXHasShownWelcomeKey = @"hasShownWelcome";
static NSString *const kMXRevealForFifteenSecondsKey = @"revealForFifteenSeconds";

@implementation MXSettingsStore

- (instancetype)init {
    self = [super init];
    return self;
}

- (NSSet<NSString *> *)hiddenBundleIdentifiers {
    NSArray *stored = [NSUserDefaults.standardUserDefaults arrayForKey:kMXHiddenBundleIdentifiersKey];
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    for (id value in stored) {
        if ([value isKindOfClass:[NSString class]] && [value length]) {
            [set addObject:value];
        }
    }
    return set;
}

- (void)setHiddenBundleIdentifiers:(NSSet<NSString *> *)hiddenBundleIdentifiers {
    NSArray *array = [hiddenBundleIdentifiers.allObjects sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [NSUserDefaults.standardUserDefaults setObject:array forKey:kMXHiddenBundleIdentifiersKey];
}

- (BOOL)isBundleHidden:(NSString *)bundleIdentifier {
    return [self.hiddenBundleIdentifiers containsObject:bundleIdentifier];
}

- (void)setBundle:(NSString *)bundleIdentifier hidden:(BOOL)hidden {
    if (!bundleIdentifier.length) {
        return;
    }
    NSMutableSet *set = [self.hiddenBundleIdentifiers mutableCopy];
    if (hidden) {
        [set addObject:bundleIdentifier];
    } else {
        [set removeObject:bundleIdentifier];
    }
    self.hiddenBundleIdentifiers = set;
}

- (BOOL)hasShownWelcome {
    return [NSUserDefaults.standardUserDefaults boolForKey:kMXHasShownWelcomeKey];
}

- (void)setHasShownWelcome:(BOOL)hasShownWelcome {
    [NSUserDefaults.standardUserDefaults setBool:hasShownWelcome forKey:kMXHasShownWelcomeKey];
}

- (BOOL)revealForFifteenSeconds {
    if (![NSUserDefaults.standardUserDefaults objectForKey:kMXRevealForFifteenSecondsKey]) {
        return YES;
    }
    return [NSUserDefaults.standardUserDefaults boolForKey:kMXRevealForFifteenSecondsKey];
}

- (void)setRevealForFifteenSeconds:(BOOL)revealForFifteenSeconds {
    [NSUserDefaults.standardUserDefaults setBool:revealForFifteenSeconds
                                         forKey:kMXRevealForFifteenSecondsKey];
}

@end

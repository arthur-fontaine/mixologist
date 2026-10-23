#import "MXSettingsStore.h"
#import "MXVisibilityPlan.h"

NSNotificationName const MXSettingsDidChangeNotification = @"MXSettingsDidChangeNotification";
MXHidingMethod const MXHidingMethodRestriction = @"restriction";
MXHidingMethod const MXHidingMethodPermission = @"permission";

static NSString *const kMXHidingMethodKey = @"hidingMethod";
static NSString *const kMXHiddenAppsKey = @"hiddenApps";
static NSString *const kMXHiddenAppleItemsKey = @"hiddenAppleItems";

// Pre-file NSUserDefaults keys, read once for migration.
static NSString *const kMXLegacyHiddenBundleIdentifiersKey = @"hiddenBundleIdentifiers";
static NSString *const kMXLegacyHiddenSystemItemsKey = @"hiddenSystemItems";
static NSString *const kMXHasShownWelcomeKey = @"hasShownWelcome";

@interface MXSettingsStore ()
@property (nonatomic, readwrite) NSURL *fileURL;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *fileIssues;
@property (nonatomic, readwrite) BOOL fileIsUsable;
/// The bytes last read or written, so the watcher's echo of a save is not taken for an edit.
@property (nonatomic, copy, nullable) NSData *lastSeenData;
@property (nonatomic, strong, nullable) dispatch_source_t folderSource;
@property (nonatomic, strong, nullable) dispatch_source_t fileSource;
@property (nonatomic) NSUInteger settleGeneration;
@end

@implementation MXSettingsStore {
    NSSet<NSString *> *_hiddenBundleIdentifiers;
    NSSet<NSNumber *> *_hiddenSystemItems;
    MXHidingMethod _hidingMethod;
}

+ (NSURL *)defaultFileURL {
    return [NSFileManager.defaultManager.homeDirectoryForCurrentUser
        URLByAppendingPathComponent:@".config/mixologist/settings.json"];
}

- (instancetype)init {
    self = [self initWithFileURL:MXSettingsStore.defaultFileURL];
    if (self && ![NSFileManager.defaultManager fileExistsAtPath:self.fileURL.path]) {
        [self migrateFromUserDefaults];
    }
    return self;
}

- (instancetype)initWithFileURL:(NSURL *)fileURL {
    self = [super init];
    if (self) {
        _fileURL = fileURL;
        _hiddenBundleIdentifiers = [NSSet set];
        _hiddenSystemItems = [NSSet set];
        _hidingMethod = MXHidingMethodRestriction;
        _fileIssues = @[];
        _fileIsUsable = YES;
        NSData *data = [NSData dataWithContentsOfURL:fileURL];
        if (data) {
            _lastSeenData = data;
            [self applyFileData:data];
        }
    }
    return self;
}

- (void)dealloc {
    if (_folderSource) {
        dispatch_source_cancel(_folderSource);
    }
    if (_fileSource) {
        dispatch_source_cancel(_fileSource);
    }
}

- (void)migrateFromUserDefaults {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableSet<NSString *> *bundles = [NSMutableSet set];
    for (id value in [defaults arrayForKey:kMXLegacyHiddenBundleIdentifiersKey]) {
        if ([value isKindOfClass:[NSString class]] && [value length]) {
            [bundles addObject:value];
        }
    }
    NSMutableSet<NSNumber *> *items = [NSMutableSet set];
    for (id value in [defaults arrayForKey:kMXLegacyHiddenSystemItemsKey]) {
        if ([value isKindOfClass:[NSNumber class]]) {
            [items addObject:@([value integerValue])];
        }
    }
    _hiddenBundleIdentifiers = bundles;
    _hiddenSystemItems = items;
    if ([self save]) {
        [defaults removeObjectForKey:kMXLegacyHiddenBundleIdentifiersKey];
        [defaults removeObjectForKey:kMXLegacyHiddenSystemItemsKey];
    }
}

#pragma mark - Values

- (NSSet<NSString *> *)hiddenBundleIdentifiers {
    return _hiddenBundleIdentifiers;
}

- (void)setHiddenBundleIdentifiers:(NSSet<NSString *> *)hiddenBundleIdentifiers {
    _hiddenBundleIdentifiers = [hiddenBundleIdentifiers copy] ?: [NSSet set];
    [self save];
}

- (NSSet<NSNumber *> *)hiddenSystemItems {
    return _hiddenSystemItems;
}

- (void)setHiddenSystemItems:(NSSet<NSNumber *> *)hiddenSystemItems {
    _hiddenSystemItems = [hiddenSystemItems copy] ?: [NSSet set];
    [self save];
}

- (MXHidingMethod)hidingMethod {
    return _hidingMethod;
}

- (void)setHidingMethod:(MXHidingMethod)hidingMethod {
    _hidingMethod = [hidingMethod isEqualToString:MXHidingMethodPermission] ? MXHidingMethodPermission
                                                                             : MXHidingMethodRestriction;
    [self save];
}

- (BOOL)isBundleHidden:(NSString *)bundleIdentifier {
    return [_hiddenBundleIdentifiers containsObject:bundleIdentifier];
}

- (void)setBundle:(NSString *)bundleIdentifier hidden:(BOOL)hidden {
    if (!bundleIdentifier.length) {
        return;
    }
    NSMutableSet *set = [_hiddenBundleIdentifiers mutableCopy];
    if (hidden) {
        [set addObject:bundleIdentifier];
    } else {
        [set removeObject:bundleIdentifier];
    }
    self.hiddenBundleIdentifiers = set;
}

- (BOOL)isSystemItemHidden:(NSInteger)rawValue {
    return [_hiddenSystemItems containsObject:@(rawValue)];
}

- (void)setSystemItem:(NSInteger)rawValue hidden:(BOOL)hidden {
    NSMutableSet *set = [_hiddenSystemItems mutableCopy];
    if (hidden) {
        [set addObject:@(rawValue)];
    } else {
        [set removeObject:@(rawValue)];
    }
    self.hiddenSystemItems = set;
}

- (BOOL)hasShownWelcome {
    return [NSUserDefaults.standardUserDefaults boolForKey:kMXHasShownWelcomeKey];
}

- (void)setHasShownWelcome:(BOOL)hasShownWelcome {
    [NSUserDefaults.standardUserDefaults setBool:hasShownWelcome forKey:kMXHasShownWelcomeKey];
}

#pragma mark - File

- (NSData *)render {
    NSMutableArray<NSString *> *appleItems = [NSMutableArray array];
    for (NSNumber *rawValue in [_hiddenSystemItems.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *name = [MXVisibilityPlan nameForSystemItemRawValue:rawValue.integerValue];
        if (name) {
            [appleItems addObject:name];
        }
    }
    NSDictionary *contents = @{
        kMXHidingMethodKey: _hidingMethod,
        kMXHiddenAppsKey: [_hiddenBundleIdentifiers.allObjects sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)],
        kMXHiddenAppleItemsKey: appleItems,
    };
    return [NSJSONSerialization dataWithJSONObject:contents
                                           options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys |
                                                   NSJSONWritingWithoutEscapingSlashes
                                             error:NULL];
}

- (BOOL)save {
    if (!self.fileIsUsable) {
        return NO;
    }
    NSData *data = [self render];
    if (!data || [data isEqualToData:self.lastSeenData]) {
        return data != nil;
    }
    NSError *error = nil;
    [NSFileManager.defaultManager createDirectoryAtURL:self.fileURL.URLByDeletingLastPathComponent
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:NULL];
    if (![data writeToURL:self.fileURL options:NSDataWritingAtomic error:&error]) {
        NSLog(@"[Mixologist] Could not save %@: %@", self.fileURL.path, error);
        return NO;
    }
    self.lastSeenData = data;
    return YES;
}

- (NSArray<NSString *> *)applyFileData:(NSData *)data {
    NSMutableArray<NSString *> *issues = [NSMutableArray array];
    NSError *error = nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (!root) {
        NSString *detail = error.userInfo[NSDebugDescriptionErrorKey] ?: error.localizedDescription;
        [issues addObject:[NSString stringWithFormat:@"Not valid JSON: %@", detail]];
    } else if (![root isKindOfClass:[NSDictionary class]]) {
        [issues addObject:@"The file must hold one JSON object."];
    }
    if (issues.count) {
        self.fileIsUsable = NO;
        self.fileIssues = issues;
        return issues;
    }
    self.fileIsUsable = YES;

    NSDictionary *contents = root;
    for (NSString *key in contents) {
        if (![@[kMXHidingMethodKey, kMXHiddenAppsKey, kMXHiddenAppleItemsKey] containsObject:key]) {
            [issues addObject:[NSString stringWithFormat:@"Unknown setting “%@”.", key]];
        }
    }

    // A missing key means its default; a malformed one keeps the current value.
    id method = contents[kMXHidingMethodKey];
    if (!method) {
        _hidingMethod = MXHidingMethodRestriction;
    } else if ([method isEqual:MXHidingMethodRestriction] || [method isEqual:MXHidingMethodPermission]) {
        _hidingMethod = method;
    } else {
        [issues addObject:@"“hidingMethod” must be \"restriction\" or \"permission\"."];
    }

    id apps = contents[kMXHiddenAppsKey];
    if (!apps) {
        _hiddenBundleIdentifiers = [NSSet set];
    } else if ([apps isKindOfClass:[NSArray class]]) {
        NSMutableSet<NSString *> *bundles = [NSMutableSet set];
        for (id value in apps) {
            if ([value isKindOfClass:[NSString class]] && [value length]) {
                [bundles addObject:value];
            } else {
                [issues addObject:[NSString stringWithFormat:@"“hiddenApps” has an entry that isn't a bundle identifier: %@", value]];
            }
        }
        _hiddenBundleIdentifiers = bundles;
    } else {
        [issues addObject:@"“hiddenApps” must be a list of bundle identifiers."];
    }

    id appleItems = contents[kMXHiddenAppleItemsKey];
    if (!appleItems) {
        _hiddenSystemItems = [NSSet set];
    } else if ([appleItems isKindOfClass:[NSArray class]]) {
        NSMutableSet<NSNumber *> *items = [NSMutableSet set];
        for (id value in appleItems) {
            NSNumber *rawValue = [value isKindOfClass:[NSString class]]
                ? [MXVisibilityPlan systemItemRawValueForName:value]
                : nil;
            if (rawValue) {
                [items addObject:rawValue];
            } else {
                [issues addObject:[NSString stringWithFormat:@"“hiddenAppleItems” has an unknown item: %@", value]];
            }
        }
        _hiddenSystemItems = items;
    } else {
        [issues addObject:@"“hiddenAppleItems” must be a list such as [\"clock\", \"wifi\"]."];
    }

    self.fileIssues = issues;
    return issues;
}

#pragma mark - Watching

- (void)startWatching {
    [self arm];
}

/// The file is reopened every time: a save by rename leaves the old descriptor on a dead inode.
- (void)arm {
    NSURL *folder = self.fileURL.URLByDeletingLastPathComponent;
    [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    if (!self.folderSource) {
        self.folderSource = [self sourceWatching:folder
                                          events:DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE |
                                                 DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE];
    }
    if (self.fileSource) {
        dispatch_source_cancel(self.fileSource);
    }
    self.fileSource = [self sourceWatching:self.fileURL
                                    events:DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_DELETE |
                                           DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE];
}

- (nullable dispatch_source_t)sourceWatching:(NSURL *)url events:(dispatch_source_vnode_flags_t)events {
    int descriptor = open(url.fileSystemRepresentation, O_EVTONLY);
    if (descriptor < 0) {
        return nil;
    }
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)descriptor,
                                                      events, dispatch_get_main_queue());
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(source, ^{
        [weakSelf scheduleReload];
    });
    dispatch_source_set_cancel_handler(source, ^{
        close(descriptor);
    });
    dispatch_resume(source);
    return source;
}

/// Editors write in bursts (temp file, rename, attributes); wait for them to settle.
- (void)scheduleReload {
    NSUInteger generation = ++self.settleGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || generation != self.settleGeneration) {
            return;
        }
        [self arm];
        [self reload];
    });
}

- (void)reload {
    NSData *data = [NSData dataWithContentsOfURL:self.fileURL];
    // Missing mid-save is normal: the rename that completes it fires an event of its own.
    if (!data || [data isEqualToData:self.lastSeenData]) {
        return;
    }
    self.lastSeenData = data;
    [self applyFileData:data];
    [NSNotificationCenter.defaultCenter postNotificationName:MXSettingsDidChangeNotification object:self];
}

@end

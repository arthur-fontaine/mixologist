#import "MXSettingsWindowController.h"
#import "MXMenuBarScanner.h"
#import <ServiceManagement/ServiceManagement.h>

@interface MXSettingsWindowController ()
@property (nonatomic, strong) MXVisibilityController *controller;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *accessibilityLabel;
@property (nonatomic, strong) NSTextField *apiLabel;
@property (nonatomic, strong) NSTextField *errorLabel;
@property (nonatomic, strong) NSButton *grantButton;
@property (nonatomic, strong) NSButton *revealButton;
@property (nonatomic, strong) NSButton *loginCheckbox;
@property (nonatomic, strong) NSStackView *appsStack;
@property (nonatomic, strong) NSView *appsContainer;
@property (nonatomic, copy) NSArray<NSString *> *rowBundleIdentifiers;
@property (nonatomic) BOOL reloading;
@end

@implementation MXSettingsWindowController

- (instancetype)initWithController:(MXVisibilityController *)controller {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 620)
                                                   styleMask:NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable |
                                                             NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Mixologist";
    window.minSize = NSMakeSize(620, 520);
    window.releasedWhenClosed = NO;
    self = [super initWithWindow:window];
    if (self) {
        _controller = controller;
        [self buildInterface];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(dataDidChange:)
                                                   name:MXVisibilityDidChangeNotification
                                                 object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(dataDidChange:)
                                                   name:MXScanDidChangeNotification
                                                 object:nil];
        [self reloadData];
        [window center];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSTextField *)labelWithString:(NSString *)string font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:string];
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.maximumNumberOfLines = 2;
    return label;
}

- (void)buildInterface {
    NSView *content = self.window.contentView;
    NSScrollView *rootScroll = [[NSScrollView alloc] init];
    rootScroll.translatesAutoresizingMaskIntoConstraints = NO;
    rootScroll.hasVerticalScroller = YES;
    rootScroll.drawsBackground = NO;
    rootScroll.borderType = NSNoBorder;
    [content addSubview:rootScroll];
    [NSLayoutConstraint activateConstraints:@[
        [rootScroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [rootScroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [rootScroll.topAnchor constraintEqualToAnchor:content.topAnchor],
        [rootScroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
    ]];

    NSView *documentView = [[NSView alloc] init];
    documentView.translatesAutoresizingMaskIntoConstraints = NO;
    rootScroll.documentView = documentView;
    [NSLayoutConstraint activateConstraints:@[
        [documentView.widthAnchor constraintEqualToAnchor:rootScroll.contentView.widthAnchor],
    ]];

    NSStackView *root = [[NSStackView alloc] init];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 14;
    [documentView addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:documentView.leadingAnchor constant:24],
        [root.trailingAnchor constraintEqualToAnchor:documentView.trailingAnchor constant:-24],
        [root.topAnchor constraintEqualToAnchor:documentView.topAnchor constant:20],
        [root.bottomAnchor constraintEqualToAnchor:documentView.bottomAnchor constant:-20],
    ]];

    NSTextField *title = [self labelWithString:@"Mixologist"
                                         font:[NSFont systemFontOfSize:26 weight:NSFontWeightSemibold]
                                        color:NSColor.labelColor];
    NSTextField *subtitle = [self labelWithString:
        @"A free, open-source menu bar organizer. Uses macOS's built-in menu bar visibility restriction — no screen recording."
                                                      font:[NSFont systemFontOfSize:12]
                                                     color:NSColor.secondaryLabelColor];
    subtitle.maximumNumberOfLines = 3;
    subtitle.lineBreakMode = NSLineBreakByWordWrapping;
    [root addArrangedSubview:title];
    [root addArrangedSubview:subtitle];

    NSBox *statusBox = [[NSBox alloc] init];
    statusBox.translatesAutoresizingMaskIntoConstraints = NO;
    statusBox.boxType = NSBoxCustom;
    statusBox.borderWidth = 1;
    statusBox.cornerRadius = 10;
    statusBox.borderColor = NSColor.separatorColor;
    statusBox.fillColor = [NSColor.controlBackgroundColor colorWithAlphaComponent:0.55];
    [root addArrangedSubview:statusBox];
    [NSLayoutConstraint activateConstraints:@[
        [statusBox.widthAnchor constraintEqualToAnchor:root.widthAnchor],
    ]];

    NSStackView *statusStack = [[NSStackView alloc] init];
    statusStack.translatesAutoresizingMaskIntoConstraints = NO;
    statusStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    statusStack.alignment = NSLayoutAttributeLeading;
    statusStack.spacing = 6;
    [statusBox addSubview:statusStack];
    [NSLayoutConstraint activateConstraints:@[
        [statusStack.leadingAnchor constraintEqualToAnchor:statusBox.leadingAnchor constant:14],
        [statusStack.trailingAnchor constraintEqualToAnchor:statusBox.trailingAnchor constant:-14],
        [statusStack.topAnchor constraintEqualToAnchor:statusBox.topAnchor constant:12],
        [statusStack.bottomAnchor constraintEqualToAnchor:statusBox.bottomAnchor constant:-12],
    ]];

    self.statusLabel = [self labelWithString:@""
                                        font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium]
                                       color:NSColor.labelColor];
    self.statusLabel.maximumNumberOfLines = 3;
    [statusStack addArrangedSubview:self.statusLabel];

    self.accessibilityLabel = [self labelWithString:@""
                                               font:[NSFont systemFontOfSize:11]
                                              color:NSColor.secondaryLabelColor];
    self.apiLabel = [self labelWithString:@""
                                     font:[NSFont systemFontOfSize:11]
                                    color:NSColor.secondaryLabelColor];
    [statusStack addArrangedSubview:self.accessibilityLabel];
    [statusStack addArrangedSubview:self.apiLabel];

    self.errorLabel = [self labelWithString:@""
                                       font:[NSFont systemFontOfSize:11]
                                      color:NSColor.systemRedColor];
    self.errorLabel.maximumNumberOfLines = 3;
    [statusStack addArrangedSubview:self.errorLabel];

    self.grantButton = [NSButton buttonWithTitle:@"Grant Accessibility…"
                                          target:self
                                          action:@selector(grantAccessibility:)];
    self.grantButton.bezelStyle = NSBezelStyleRounded;
    [statusStack addArrangedSubview:self.grantButton];

    NSStackView *buttons = [[NSStackView alloc] init];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.alignment = NSLayoutAttributeCenterY;
    buttons.spacing = 8;
    [root addArrangedSubview:buttons];

    NSButton *rescan = [NSButton buttonWithTitle:@"Rescan" target:self action:@selector(rescan:)];
    rescan.bezelStyle = NSBezelStyleRounded;
    [buttons addArrangedSubview:rescan];

    self.revealButton = [NSButton buttonWithTitle:@"Reveal Hidden (15 s)" target:self action:@selector(toggleReveal:)];
    self.revealButton.bezelStyle = NSBezelStyleRounded;
    [buttons addArrangedSubview:self.revealButton];

    NSButton *showAll = [NSButton buttonWithTitle:@"Unhide All Apps" target:self action:@selector(showAll:)];
    showAll.bezelStyle = NSBezelStyleRounded;
    [buttons addArrangedSubview:showAll];

    NSButton *hideAll = [NSButton buttonWithTitle:@"Hide All Third-Party Apps" target:self action:@selector(hideAll:)];
    hideAll.bezelStyle = NSBezelStyleRounded;
    [buttons addArrangedSubview:hideAll];

    NSTextField *appsHeader = [self labelWithString:@"Applications with menu bar items"
                                              font:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]
                                             color:NSColor.labelColor];
    [root addArrangedSubview:appsHeader];

    NSScrollView *appsScroll = [[NSScrollView alloc] init];
    appsScroll.translatesAutoresizingMaskIntoConstraints = NO;
    appsScroll.hasVerticalScroller = YES;
    appsScroll.drawsBackground = NO;
    appsScroll.borderType = NSBezelBorder;
    [root addArrangedSubview:appsScroll];
    [NSLayoutConstraint activateConstraints:@[
        [appsScroll.widthAnchor constraintEqualToAnchor:root.widthAnchor],
        [appsScroll.heightAnchor constraintGreaterThanOrEqualToConstant:230],
    ]];

    self.appsContainer = [[NSView alloc] init];
    self.appsContainer.translatesAutoresizingMaskIntoConstraints = NO;
    appsScroll.documentView = self.appsContainer;
    [NSLayoutConstraint activateConstraints:@[
        [self.appsContainer.widthAnchor constraintEqualToAnchor:appsScroll.contentView.widthAnchor],
    ]];

    self.appsStack = [[NSStackView alloc] init];
    self.appsStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.appsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.appsStack.alignment = NSLayoutAttributeLeading;
    self.appsStack.spacing = 4;
    [self.appsContainer addSubview:self.appsStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.appsStack.leadingAnchor constraintEqualToAnchor:self.appsContainer.leadingAnchor constant:8],
        [self.appsStack.trailingAnchor constraintEqualToAnchor:self.appsContainer.trailingAnchor constant:-8],
        [self.appsStack.topAnchor constraintEqualToAnchor:self.appsContainer.topAnchor constant:8],
        [self.appsStack.bottomAnchor constraintEqualToAnchor:self.appsContainer.bottomAnchor constant:-8],
    ]];

    self.loginCheckbox = [NSButton checkboxWithTitle:@"Start Mixologist at login"
                                              target:self
                                              action:@selector(toggleLogin:)];
    [root addArrangedSubview:self.loginCheckbox];

    NSTextField *footer = [self labelWithString:
        @"Global shortcut: ⌃⌥⌘M reveals hidden items. The shortcut and this window keep working even if Mixologist's own menu bar icon is hidden. Quit restores every item."
                                             font:[NSFont systemFontOfSize:11]
                                            color:NSColor.tertiaryLabelColor];
    footer.maximumNumberOfLines = 4;
    footer.lineBreakMode = NSLineBreakByWordWrapping;
    [root addArrangedSubview:footer];
}

- (void)dataDidChange:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reloadData];
    });
}

- (void)reloadData {
    if (self.reloading) {
        return;
    }
    self.reloading = YES;

    BOOL trusted = self.controller.lastScan.isAccessibilityTrusted;
    self.accessibilityLabel.stringValue = trusted
        ? @"Accessibility: granted — menu bar items can be discovered."
        : @"Accessibility: not granted — Mixologist cannot discover menu bar items. Grant it in System Settings → Privacy & Security → Accessibility.";
    self.grantButton.hidden = trusted;

    self.apiLabel.stringValue = self.controller.isPrivateAPIAvailable
        ? @"Menu bar visibility API: available (assessment mode)."
        : @"Menu bar visibility API: unavailable on this macOS build.";

    self.statusLabel.stringValue = self.controller.statusDescription;
    NSError *error = self.controller.lastError;
    self.errorLabel.stringValue = error ? error.localizedDescription : @"";
    self.errorLabel.hidden = error == nil;

    self.revealButton.title = self.controller.isRevealing
        ? @"Hide Revealed Items"
        : @"Reveal Hidden (15 s)";

    [self reloadApps];

    if (@available(macOS 13.0, *)) {
        self.loginCheckbox.state = SMAppService.mainAppService.status == SMAppServiceStatusEnabled
            ? NSControlStateValueOn
            : NSControlStateValueOff;
    } else {
        self.loginCheckbox.hidden = YES;
    }

    self.reloading = NO;
}

- (void)reloadApps {
    for (NSView *view in [self.appsStack.arrangedSubviews copy]) {
        [self.appsStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    NSMutableArray<MXAppMenuItems *> *apps = [NSMutableArray array];
    for (MXAppMenuItems *app in self.controller.lastScan.apps) {
        if (!app.isSystemApp && app.bundleIdentifier.length > 0) {
            [apps addObject:app];
        }
    }

    if (!apps.count) {
        NSTextField *empty = [self labelWithString:
            self.controller.lastScan.isAccessibilityTrusted
                ? @"No third-party menu bar items found yet. Open an app that has a menu bar extra, then press Rescan."
                : @"Grant Accessibility access, then press Rescan."
                                             font:[NSFont systemFontOfSize:12]
                                            color:NSColor.secondaryLabelColor];
        empty.maximumNumberOfLines = 3;
        empty.lineBreakMode = NSLineBreakByWordWrapping;
        [self.appsStack addArrangedSubview:empty];
        [empty.widthAnchor constraintEqualToAnchor:self.appsStack.widthAnchor].active = YES;
        return;
    }

    NSMutableArray<NSString *> *rowBundleIdentifiers = [NSMutableArray array];
    for (MXAppMenuItems *app in apps) {
        NSButton *checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(toggleApp:)];
        checkbox.state = [self.controller isBundleHidden:app.bundleIdentifier]
            ? NSControlStateValueOff
            : NSControlStateValueOn;
        checkbox.toolTip = @"Tick to keep this application's menu bar items visible.";
        checkbox.translatesAutoresizingMaskIntoConstraints = NO;
        checkbox.tag = (NSInteger)rowBundleIdentifiers.count;
        [rowBundleIdentifiers addObject:app.bundleIdentifier];
        [checkbox.widthAnchor constraintEqualToConstant:22].active = YES;

        NSString *detail = [NSString stringWithFormat:@"%@  ·  %lu item%@",
                            app.bundleIdentifier,
                            (unsigned long)app.items.count,
                            app.items.count == 1 ? @"" : @"s"];
        NSMutableArray<NSString *> *titles = [NSMutableArray array];
        for (MXMenuItem *item in app.items) {
            if (item.title.length) {
                [titles addObject:item.title];
            }
        }
        if (titles.count) {
            detail = [detail stringByAppendingFormat:@"  ·  %@", [titles componentsJoinedByString:@", "]];
        }

        NSTextField *name = [self labelWithString:app.appName
                                            font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium]
                                           color:NSColor.labelColor];
        NSTextField *detailLabel = [self labelWithString:detail
                                                   font:[NSFont systemFontOfSize:10.5]
                                                  color:NSColor.secondaryLabelColor];
        detailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        detailLabel.maximumNumberOfLines = 1;

        NSStackView *text = [[NSStackView alloc] init];
        text.orientation = NSUserInterfaceLayoutOrientationVertical;
        text.alignment = NSLayoutAttributeLeading;
        text.spacing = 1;
        [text addArrangedSubview:name];
        [text addArrangedSubview:detailLabel];

        NSStackView *row = [[NSStackView alloc] init];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row.alignment = NSLayoutAttributeCenterY;
        row.spacing = 8;
        [row addArrangedSubview:checkbox];
        [row addArrangedSubview:text];
        [self.appsStack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:self.appsStack.widthAnchor].active = YES;
    }
    self.rowBundleIdentifiers = rowBundleIdentifiers;
}

- (void)toggleApp:(NSButton *)sender {
    if (sender.tag < 0 || (NSUInteger)sender.tag >= self.rowBundleIdentifiers.count) {
        return;
    }
    NSString *bundleIdentifier = self.rowBundleIdentifiers[(NSUInteger)sender.tag];
    if (![bundleIdentifier isKindOfClass:[NSString class]]) {
        return;
    }
    BOOL hidden = sender.state == NSControlStateValueOff;
    sender.enabled = NO;
    [self.controller setBundle:bundleIdentifier hidden:hidden];
    sender.enabled = YES;
    [self reloadData];
}

- (void)rescan:(id)sender {
    self.statusLabel.stringValue = @"Scanning running applications…";
    __weak typeof(self) weakSelf = self;
    [self.controller refreshScanWithCompletion:^(MXScanResult *result) {
        __strong typeof(weakSelf) self = weakSelf;
        [self reloadData];
        if (!result.isAccessibilityTrusted) {
            [self grantAccessibility:nil];
        }
    }];
}

- (void)toggleReveal:(id)sender {
    if (self.controller.isRevealing) {
        [self.controller setRevealing:NO];
    } else {
        [self.controller revealForSeconds:15];
    }
    [self reloadData];
}

- (void)showAll:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Unhide every application?";
    alert.informativeText = @"Every menu bar item will become visible and Mixologist will stop hiding items. The list of applications is kept.";
    [alert addButtonWithTitle:@"Unhide All"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }
    [self.controller showAllAppsPermanently];
    [self reloadData];
}

- (void)hideAll:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Hide all third-party menu bar items?";
    alert.informativeText = @"Every third-party application currently exposing a menu bar item will be hidden. Apple's own items, Mixologist's icon and this window stay available. Use ⌃⌥⌘M or the Reveal button to bring them back.";
    [alert addButtonWithTitle:@"Hide Them"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }
    [self.controller hideAllThirdPartyApps];
    [self reloadData];
}

- (void)grantAccessibility:(id)sender {
    [MXMenuBarScanner accessibilityTrustedWithPrompt:YES];
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    if (url) {
        [NSWorkspace.sharedWorkspace openURL:url];
    }
}

- (void)toggleLogin:(NSButton *)sender {
    if (@available(macOS 13.0, *)) {
        NSError *error = nil;
        BOOL enable = sender.state == NSControlStateValueOn;
        BOOL success = enable
            ? [SMAppService.mainAppService registerAndReturnError:&error]
            : [SMAppService.mainAppService unregisterAndReturnError:&error];
        if (!success || error) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = enable ? @"Could not enable login item" : @"Could not disable login item";
            alert.informativeText = error.localizedDescription ?: @"macOS refused the request. Move Mixologist to /Applications and sign it with a development identity, then try again.";
            [alert runModal];
        }
        sender.state = SMAppService.mainAppService.status == SMAppServiceStatusEnabled
            ? NSControlStateValueOn
            : NSControlStateValueOff;
    }
}

@end

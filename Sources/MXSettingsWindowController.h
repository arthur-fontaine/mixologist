#import <Cocoa/Cocoa.h>
#import "MXVisibilityController.h"

NS_ASSUME_NONNULL_BEGIN

@interface MXSettingsWindowController : NSWindowController

- (instancetype)initWithController:(MXVisibilityController *)controller;
- (void)reloadData;

@end

NS_ASSUME_NONNULL_END

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A system-wide hotkey that does not require Accessibility access. Uses the
/// Carbon hotkey API, which remains available on macOS 27.
@interface MXHotKey : NSObject

- (instancetype)initWithKeyCode:(UInt32)keyCode
                      modifiers:(UInt32)carbonModifiers
                        handler:(void (^)(void))handler;
- (void)unregister;

@end

NS_ASSUME_NONNULL_END

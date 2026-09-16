//
//  MainWindowController.h
//  Quassel for GNUstep
//
//  Replaces iQuassel's UISplitViewController + UINavigationController stack with
//  a single desktop window. The content area swaps between the connection
//  screens (login / connecting / error) and the chat interface, which is what
//  the five storyboard segues did on iOS.
//

#import <AppKit/AppKit.h>
#import "QuasselCoreConnectionDelegate.h"

@class QuasselCoreConnection;
@class BufferListController;
@class ChatViewController;

typedef NS_ENUM(NSInteger, QuasselUIState) {
    QuasselUIStateLogin,
    QuasselUIStateConnecting,
    QuasselUIStateError,
    QuasselUIStateChat
};

@interface MainWindowController : NSWindowController <QuasselCoreConnectionDelegate>

@property (nonatomic, strong) QuasselCoreConnection *connection;
@property (nonatomic, readonly) QuasselUIState state;

- (instancetype)init;

- (void)showState:(QuasselUIState)state;
- (void)connectWithHost:(NSString *)host
                   port:(int)port
                   user:(NSString *)user
               password:(NSString *)password;
- (void)disconnect;

/// Called by the buffer list when the user picks a buffer.
- (void)selectBufferId:(id)bufferId;

@end

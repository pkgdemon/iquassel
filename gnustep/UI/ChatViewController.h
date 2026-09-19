//
//  ChatViewController.h
//  Quassel for GNUstep
//
//  The chat log plus input field. The log is a read-only NSTextView so long
//  lines word-wrap and reflow when the window resizes. gnustep-gui's
//  NSTableView ignores -tableView:heightOfRow: and draws every cell as a single
//  line, so a table cannot show a wrapped message.
//

#import <AppKit/AppKit.h>
#import "QuasselCoreConnectionDelegate.h"

@class QuasselCoreConnection;
@class MainWindowController;
@class Message;

@interface ChatViewController : NSObject

@property (nonatomic, weak)   MainWindowController  *windowController;
@property (nonatomic, strong) QuasselCoreConnection *connection;

- (instancetype)initWithWindowController:(MainWindowController *)wc;

- (NSView *)view;

- (void)showBufferId:(id)bufferId;
- (void)messageReceived:(Message *)msg style:(enum ReceiveStyle)style atIndex:(int)index;
- (void)messagesReceived:(NSArray *)messages style:(enum ReceiveStyle)style;

@end

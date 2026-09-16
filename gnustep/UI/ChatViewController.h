//
//  ChatViewController.h
//  Quassel for GNUstep
//
//  The chat log plus input field. Uses NSTableView with
//  -tableView:heightOfRow:, which is exactly the capability libs-uikit's
//  UITableView lacks and the reason this port went native.
//

#import <AppKit/AppKit.h>
#import "QuasselCoreConnectionDelegate.h"

@class QuasselCoreConnection;
@class MainWindowController;
@class Message;

@interface ChatViewController : NSObject <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, weak)   MainWindowController  *windowController;
@property (nonatomic, strong) QuasselCoreConnection *connection;

- (instancetype)initWithWindowController:(MainWindowController *)wc;

- (NSView *)view;

- (void)showBufferId:(id)bufferId;
- (void)messageReceived:(Message *)msg style:(enum ReceiveStyle)style atIndex:(int)index;
- (void)messagesReceived:(NSArray *)messages style:(enum ReceiveStyle)style;

@end

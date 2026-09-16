//
//  BufferListController.h
//  Quassel for GNUstep
//
//  The buffer sidebar. iQuassel faked a two-level hierarchy inside a flat
//  UITableView using sections; NSOutlineView gives us real expandable network
//  groups, which is a better fit for the data than the original.
//

#import <AppKit/AppKit.h>

@class QuasselCoreConnection;
@class MainWindowController;

@interface BufferListController : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>

@property (nonatomic, weak)   MainWindowController  *windowController;
@property (nonatomic, strong) QuasselCoreConnection *connection;

- (instancetype)initWithWindowController:(MainWindowController *)wc;

- (NSView *)view;
- (void)reload;
- (void)selectBufferId:(id)bufferId;

@end

//
//  BufferListController.m
//  Quassel for GNUstep
//

#import "BufferListController.h"
#import "MainWindowController.h"

#import "QuasselCoreConnection.h"
#import "BufferInfo.h"
#import "SignedId.h"

/// Wrapper for a network row, so -outlineView:isItemExpandable: can tell a
/// network apart from a BufferId without relying on class checks against the
/// engine's model types.
@interface QSNetworkNode : NSObject
@property (nonatomic, strong) NetworkId *networkId;
@property (nonatomic, copy)   NSString  *name;
@property (nonatomic, strong) NSArray   *bufferIds;
@end

@implementation QSNetworkNode
@end


@interface BufferListController ()
{
    NSScrollView  *_scroll;
    NSOutlineView *_outline;
    NSArray       *_networks;      // of QSNetworkNode
}
@end


@implementation BufferListController

- (instancetype)initWithWindowController:(MainWindowController *)wc
{
    if ((self = [super init])) {
        _windowController = wc;
        _networks = @[];
        [self buildView];
    }
    return self;
}

- (void)buildView
{
    NSRect frame = NSMakeRect(0, 0, 220, 600);

    _outline = [[NSOutlineView alloc] initWithFrame:frame];

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"buffer"];
    [col setWidth:frame.size.width - 4];
    [[col headerCell] setStringValue:@"Buffers"];
    [_outline addTableColumn:col];
    [_outline setOutlineTableColumn:col];

    [_outline setHeaderView:nil];
    [_outline setDataSource:self];
    [_outline setDelegate:self];
    [_outline setRowHeight:18.0];
    [_outline setAutoresizesOutlineColumn:YES];
    [_outline setAllowsEmptySelection:YES];
    [_outline setAllowsMultipleSelection:NO];
    [_outline setTarget:self];
    [_outline setAction:@selector(rowClicked:)];

    _scroll = [[NSScrollView alloc] initWithFrame:frame];
    [_scroll setDocumentView:_outline];
    [_scroll setHasVerticalScroller:YES];
    [_scroll setHasHorizontalScroller:NO];
    [_scroll setBorderType:NSNoBorder];
    [_scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
}

- (NSView *)view { return _scroll; }

#pragma mark - Model

- (void)setConnection:(QuasselCoreConnection *)connection
{
    _connection = connection;
    [self reload];
}

- (void)reload
{
    QuasselCoreConnection *c = self.connection;
    if (c == nil) {
        _networks = @[];
        [_outline reloadData];
        return;
    }

    NSMutableArray *nodes = [NSMutableArray array];
    for (NetworkId *nid in c.neworkIdList) {
        QSNetworkNode *n = [[QSNetworkNode alloc] init];
        n.networkId = nid;
        n.name      = [c.networkIdNetworkNameMap objectForKey:nid] ?: @"(network)";

        // Keep only ids we actually have a BufferInfo for; the engine populates
        // these maps across several InitData rounds, so reload can land midway.
        NSMutableArray *ids = [NSMutableArray array];
        for (BufferId *bid in [c.networkIdBufferIdListMap objectForKey:nid]) {
            if ([c.bufferIdBufferInfoMap objectForKey:bid]) {
                [ids addObject:bid];
            }
        }
        n.bufferIds = ids;
        [nodes addObject:n];
    }
    _networks = nodes;

    [_outline reloadData];
    for (QSNetworkNode *n in _networks) {
        [_outline expandItem:n];
    }
}

- (void)selectBufferId:(id)bufferId
{
    NSInteger row = [_outline rowForItem:bufferId];
    if (row >= 0) {
        [_outline selectRowIndexes:[NSIndexSet indexSetWithIndex:row]
              byExtendingSelection:NO];
    }
}

- (void)rowClicked:(id)sender
{
    NSInteger row = [_outline clickedRow];
    if (row < 0) row = [_outline selectedRow];
    if (row < 0) return;

    id item = [_outline itemAtRow:row];
    if ([item isKindOfClass:[QSNetworkNode class]]) return;   // network header

    [self.windowController selectBufferId:item];
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item
{
    if (item == nil) return (NSInteger)_networks.count;
    if ([item isKindOfClass:[QSNetworkNode class]]) {
        return (NSInteger)[(QSNetworkNode *)item bufferIds].count;
    }
    return 0;
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)index ofItem:(id)item
{
    if (item == nil) return _networks[(NSUInteger)index];
    if ([item isKindOfClass:[QSNetworkNode class]]) {
        return [(QSNetworkNode *)item bufferIds][(NSUInteger)index];
    }
    return nil;
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item
{
    return [item isKindOfClass:[QSNetworkNode class]];
}

- (id)outlineView:(NSOutlineView *)ov
objectValueForTableColumn:(NSTableColumn *)col
           byItem:(id)item
{
    if ([item isKindOfClass:[QSNetworkNode class]]) {
        return [(QSNetworkNode *)item name];
    }

    BufferInfo *info = [self.connection.bufferIdBufferInfoMap objectForKey:item];
    if (info == nil) return @"?";

    NSString *name = info.bufferName ?: @"";
    // Mark unread activity the way the sidebar did on iOS.
    NSNumber *activity = [self.connection.bufferIdBufferActivityMap objectForKey:item];
    if (activity && [activity intValue] == BufferActivityHighlight) {
        return [NSString stringWithFormat:@"%@ •", name];
    }
    return name;
}

#pragma mark - NSOutlineViewDelegate

- (BOOL)outlineView:(NSOutlineView *)ov shouldSelectItem:(id)item
{
    return ![item isKindOfClass:[QSNetworkNode class]];
}

- (BOOL)outlineView:(NSOutlineView *)ov isGroupItem:(id)item
{
    return [item isKindOfClass:[QSNetworkNode class]];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)note
{
    NSInteger row = [_outline selectedRow];
    if (row < 0) return;
    id item = [_outline itemAtRow:row];
    if ([item isKindOfClass:[QSNetworkNode class]]) return;
    [self.windowController selectBufferId:item];
}

@end

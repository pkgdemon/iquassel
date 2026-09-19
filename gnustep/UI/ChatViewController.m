//
//  ChatViewController.m
//  Quassel for GNUstep
//

#import "ChatViewController.h"
#import "MainWindowController.h"

#import "QuasselCoreConnection.h"
#import "QuasselUtils.h"
#import "Message.h"
#import "BufferInfo.h"
#import "SignedId.h"

static const CGFloat kInputH   = 26.0;
static const CGFloat kHPad     = 6.0;
static const CGFloat kVPad     = 3.0;

@interface ChatViewController ()
{
    NSView        *_root;
    NSScrollView  *_scroll;
    NSTextView    *_log;
    NSTextField   *_input;

    NSFont          *_font;
    NSParagraphStyle *_paragraph;
}
@property (nonatomic, strong) id currentBufferId;
@end


@implementation ChatViewController

- (instancetype)initWithWindowController:(MainWindowController *)wc
{
    if ((self = [super init])) {
        _windowController = wc;
        _font = [NSFont userFixedPitchFontOfSize:11] ?: [NSFont systemFontOfSize:12];

        NSMutableParagraphStyle *p = [[NSMutableParagraphStyle alloc] init];
        [p setLineBreakMode:NSLineBreakByWordWrapping];
        [p setParagraphSpacing:2 * kVPad];
        _paragraph = p;
        [self buildView];
    }
    return self;
}

- (void)buildView
{
    NSRect frame = NSMakeRect(0, 0, 760, 600);
    _root = [[NSView alloc] initWithFrame:frame];
    [_root setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    // --- input field along the bottom ---
    _input = [[NSTextField alloc] initWithFrame:
              NSMakeRect(0, 0, frame.size.width, kInputH)];
    [_input setBezeled:YES];
    [_input setEditable:YES];
    [_input setFont:[NSFont systemFontOfSize:12]];
    [_input setTarget:self];
    [_input setAction:@selector(inputSubmitted:)];
    [_input setDelegate:(id)self];
    [_input setAutoresizingMask:NSViewWidthSizable];
    [_root addSubview:_input];

    // --- chat log filling the rest ---
    NSRect logFrame = NSMakeRect(0, kInputH + 1,
                                 frame.size.width, frame.size.height - kInputH - 1);

    _scroll = [[NSScrollView alloc] initWithFrame:logFrame];
    [_scroll setHasVerticalScroller:YES];
    [_scroll setHasHorizontalScroller:NO];
    [_scroll setBorderType:NSNoBorder];
    [_scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    // The text container tracks the view's width, so lines rewrap whenever the
    // window or split view is resized.
    NSSize content = [_scroll contentSize];
    _log = [[NSTextView alloc] initWithFrame:
            NSMakeRect(0, 0, content.width, content.height)];
    [_log setEditable:NO];
    [_log setSelectable:YES];
    [_log setRichText:YES];
    [_log setDrawsBackground:YES];
    [_log setBackgroundColor:[NSColor whiteColor]];
    [_log setTextContainerInset:NSMakeSize(kHPad, kVPad)];
    [_log setMinSize:NSMakeSize(0, content.height)];
    [_log setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    [_log setVerticallyResizable:YES];
    [_log setHorizontallyResizable:NO];
    [_log setAutoresizingMask:NSViewWidthSizable];
    [[_log textContainer] setContainerSize:NSMakeSize(content.width, FLT_MAX)];
    [[_log textContainer] setWidthTracksTextView:YES];

    [_scroll setDocumentView:_log];
    [_root addSubview:_scroll];
}

- (NSView *)view { return _root; }

- (void)setConnection:(QuasselCoreConnection *)connection
{
    _connection = connection;
    if (connection == nil) {
        self.currentBufferId = nil;
        [self rebuildLog];
    }
}

#pragma mark - Buffer switching

- (void)showBufferId:(id)bufferId
{
    self.currentBufferId = bufferId;

    BufferInfo *info = [self.connection.bufferIdBufferInfoMap objectForKey:bufferId];
    [[_windowController window] setTitle:
        info ? [NSString stringWithFormat:@"Quassel — %@", info.bufferName] : @"Quassel"];

    // Ask the core for backlog the first time a buffer is opened.
    if (bufferId && ![self.connection.backlogRequestedForAlreadyBufferIdSet containsObject:bufferId]) {
        [self.connection.backlogRequestedForAlreadyBufferIdSet addObject:bufferId];
        [self.connection fetchSomeBacklog:bufferId];
    }

    [self rebuildLog];
    [self scrollToBottom];
}

- (NSArray *)currentMessages
{
    if (self.currentBufferId == nil) return @[];
    return [self.connection.bufferIdMessageListMap objectForKey:self.currentBufferId] ?: @[];
}

- (void)rebuildLog
{
    NSMutableAttributedString *log = [[NSMutableAttributedString alloc] init];
    for (Message *m in [self currentMessages]) {
        [self appendMessage:m to:log];
    }
    [[_log textStorage] setAttributedString:log];
}

/// One message per paragraph; every line after the first starts with a newline.
- (void)appendMessage:(Message *)m to:(NSMutableAttributedString *)log
{
    if (log.length > 0) {
        [log appendAttributedString:
            [[NSAttributedString alloc] initWithString:@"\n"
                                            attributes:[self baseAttributes]]];
    }
    [log appendAttributedString:[self attributedLineForMessage:m]];
}

- (void)scrollToBottom
{
    [_log scrollRangeToVisible:NSMakeRange([[_log textStorage] length], 0)];
}

#pragma mark - Incoming messages

- (void)messageReceived:(Message *)msg style:(enum ReceiveStyle)style atIndex:(int)index
{
    if (![[self bufferIdOfMessage:msg] isEqual:self.currentBufferId]) return;

    // A live message lands at the end of the list, so it can be appended
    // without re-laying out the whole log. Anything else rebuilds.
    if (style == ReceiveStyleAppended && index == (int)[self currentMessages].count - 1) {
        NSTextStorage *ts = [_log textStorage];
        [ts beginEditing];
        [self appendMessage:msg to:ts];
        [ts endEditing];
    } else {
        [self rebuildLog];
    }
    if (style == ReceiveStyleAppended) [self scrollToBottom];
}

- (void)messagesReceived:(NSArray *)messages style:(enum ReceiveStyle)style
{
    Message *first = messages.firstObject;
    if (first && ![[self bufferIdOfMessage:first] isEqual:self.currentBufferId]) return;
    [self rebuildLog];
    if (style != ReceiveStyleBacklog) [self scrollToBottom];
}

- (id)bufferIdOfMessage:(Message *)m
{
    return [[m bufferInfo] bufferId];
}

#pragma mark - Rendering
//
// Ported from BufferViewController.m:559-661. The formatting is unchanged; only
// the colour handling differs, because QuasselUtils now returns a packed RGB
// value rather than a UIColor.

- (NSString *)plainLineForMessage:(Message *)message
{
    NSString *ts     = [QuasselUtils extractTimestamp:message];
    NSString *nick   = [QuasselUtils extractNick:message.sender];
    NSString *body   = message.contents ?: @"";

    switch (message.messageType) {
        case MessageTypeNotice:
        case MessageTypePlain:
            return [NSString stringWithFormat:@"%@ <%@> %@", ts, nick, body];
        case MessageTypeAction:
            return [NSString stringWithFormat:@"%@ * %@ %@", ts, nick, body];
        case MessageTypeJoin:
            return [NSString stringWithFormat:@"%@ --> %@", ts, message.sender];
        case MessageTypePart:
        case MessageTypeQuit:
            return [NSString stringWithFormat:@"%@ <-- %@ (%@)", ts, message.sender, body];
        case MessageTypeNick:
            return [NSString stringWithFormat:@"%@ <-> %@ is now known as %@", ts, nick, body];
        case MessageTypeDayChange:
            return @"-{ Day changed }-";
        case MessageTypeServer:
            return [NSString stringWithFormat:@"%@ * %@", ts, body];
        case MessageTypeError:
            return [NSString stringWithFormat:@"%@ Error: %@", ts, body];
        default:
            return [NSString stringWithFormat:@"%@ %@ %@", ts, nick, body];
    }
}

- (NSColor *)colorForNick:(NSString *)nick
{
    uint32_t rgb = [QuasselUtils rgbFromNick:nick];
    return [NSColor colorWithCalibratedRed:((rgb & 0xFF0000) >> 16) / 255.0
                                     green:((rgb & 0x00FF00) >>  8) / 255.0
                                      blue:( rgb & 0x0000FF)        / 255.0
                                     alpha:1.0];
}

- (NSDictionary *)baseAttributes
{
    return @{ NSFontAttributeName:            _font,
              NSParagraphStyleAttributeName:  _paragraph,
              NSForegroundColorAttributeName: [NSColor blackColor] };
}

- (NSAttributedString *)attributedLineForMessage:(Message *)message
{
    NSString *line = [self plainLineForMessage:message];

    NSMutableAttributedString *s =
        [[NSMutableAttributedString alloc] initWithString:line
                                               attributes:[self baseAttributes]];
    NSRange all = NSMakeRange(0, line.length);

    // Timestamps in grey.
    NSRange tsRange = [line rangeOfString:@"]"];
    if (tsRange.location != NSNotFound && [line hasPrefix:@"["]) {
        [s addAttribute:NSForegroundColorAttributeName
                  value:[NSColor grayColor]
                  range:NSMakeRange(0, tsRange.location + 1)];
    }

    // Nick in its hashed colour, matching the iOS client's palette.
    NSString *nick = [QuasselUtils extractNick:message.sender];
    if (nick.length) {
        NSRange nickRange = [line rangeOfString:nick];
        if (nickRange.location != NSNotFound) {
            [s addAttribute:NSForegroundColorAttributeName
                      value:[self colorForNick:nick]
                      range:nickRange];
        }
    }

    // Status lines are de-emphasised.
    switch (message.messageType) {
        case MessageTypeJoin:
        case MessageTypePart:
        case MessageTypeQuit:
        case MessageTypeNick:
        case MessageTypeServer:
            [s addAttribute:NSForegroundColorAttributeName
                      value:[NSColor darkGrayColor] range:all];
            break;
        case MessageTypeError:
            [s addAttribute:NSForegroundColorAttributeName
                      value:[NSColor redColor] range:all];
            break;
        default:
            break;
    }

    return s;
}

#pragma mark - Input

- (void)inputSubmitted:(id)sender
{
    NSString *text = [[_input stringValue]
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (text.length == 0 || self.currentBufferId == nil) return;

    [self.connection sendMessage:text toBuffer:self.currentBufferId];
    [_input setStringValue:@""];
    [self scrollToBottom];
}

/// Tab completion, ported from BufferViewController.m:62-107.
- (BOOL)control:(NSControl *)control
       textView:(NSTextView *)textView
doCommandBySelector:(SEL)command
{
    if (command != @selector(insertTab:)) return NO;

    NSString *text = [_input stringValue];
    NSRange lastSpace = [text rangeOfString:@" " options:NSBackwardsSearch];
    NSString *prefix  = (lastSpace.location == NSNotFound)
                        ? text
                        : [text substringFromIndex:lastSpace.location + 1];
    if (prefix.length == 0) return YES;

    BufferInfo *info = [self.connection.bufferIdBufferInfoMap
                        objectForKey:self.currentBufferId];
    if (info == nil) return YES;

    NSDictionary *users = [self.connection.networkIdUserMapMap
                           objectForKey:[info networkId]];
    NSString *match = nil;
    for (NSString *nick in users) {
        if ([[nick lowercaseString] hasPrefix:[prefix lowercaseString]]) {
            match = nick;
            break;
        }
    }
    if (match == nil) return YES;

    NSString *completed;
    if (lastSpace.location == NSNotFound) {
        completed = [NSString stringWithFormat:@"%@: ", match];
    } else {
        completed = [NSString stringWithFormat:@"%@%@ ",
                     [text substringToIndex:lastSpace.location + 1], match];
    }
    [_input setStringValue:completed];
    return YES;
}

@end

//
//  quasselcli.m
//  Quassel for GNUstep -- Phase 1 harness
//
//  A headless client that drives the unmodified QuasselCoreConnection engine and
//  prints what it sees. This is the Phase 1 gate: it proves the whole network and
//  protocol stack -- socket, STARTTLS, handshake, QVariant codec, SignalProxy
//  dispatch -- before a single line of AppKit exists.
//
//  usage: quasselcli <host> <port> <user> [password]
//         QUASSEL_PASSWORD may be used instead of the argument.
//

#import <Foundation/Foundation.h>

#import "QuasselCoreConnection.h"
#import "QuasselCoreConnectionDelegate.h"
#import "BufferInfo.h"
#import "SignedId.h"
#import "Message.h"
#import "QuasselUtils.h"
#import "IrcUser.h"
#import "IrcChannel.h"

static const char *kReset = "\033[0m";
static const char *kDim   = "\033[2m";
static const char *kBold  = "\033[1m";
static const char *kGreen = "\033[32m";
static const char *kRed   = "\033[31m";
static const char *kCyan  = "\033[36m";

static void step(const char *fmt, ...)
{
    va_list ap; va_start(ap, fmt);
    fprintf(stdout, "%s  ->%s ", kGreen, kReset);
    vfprintf(stdout, fmt, ap);
    fprintf(stdout, "\n"); fflush(stdout);
    va_end(ap);
}

static void fail(const char *fmt, ...)
{
    va_list ap; va_start(ap, fmt);
    fprintf(stdout, "%s  !! %s", kRed, kReset);
    vfprintf(stdout, fmt, ap);
    fprintf(stdout, "\n"); fflush(stdout);
    va_end(ap);
}


@interface QuasselCLI : NSObject <QuasselCoreConnectionDelegate>
@property (nonatomic, strong) QuasselCoreConnection *conn;
@property (nonatomic, assign) BOOL finished;
@property (nonatomic, assign) BOOL succeeded;
@property (nonatomic, assign) NSUInteger messageCount;
@end


@implementation QuasselCLI

#pragma mark - Connection lifecycle

- (void) quasselSocketFailedConnect:(NSString*)msg
{
    fail("socket failed to connect: %s", msg.UTF8String);
    self.finished = YES;
}

- (void) quasselConnected      { step("TCP connected"); }
- (void) quasselEncrypted      { step("TLS established  %s(STARTTLS after ClientInitAck)%s", kDim, kReset); }
- (void) quasselAuthenticated  { step("authenticated"); }

- (void) quasselBufferListReceived
{
    step("buffer list received");
}

- (void) quasselNetworkInitReceived:(NSString*)networkName
{
    step("network init: %s%s%s", kBold, networkName.UTF8String, kReset);
}

- (void) quasselAllNetworkInitReceived { step("all networks initialised"); }

- (void) quasselFullyConnected
{
    step("fully connected");
    [self dumpBuffers];
    self.succeeded = YES;
    self.finished  = YES;
}

- (void) quasselBufferListUpdated { }

- (void) quasselSocketDidDisconnect:(NSString*)msg
{
    fail("disconnected: %s", msg ? msg.UTF8String : "(no reason given)");
    self.finished = YES;
}

#pragma mark - Data callbacks

- (void) quasselSwitchToBuffer:(BufferId*)bufferId { }

- (void) quasselMessageReceived:(Message*)msg received:(enum ReceiveStyle)style onIndex:(int)i
{
    self.messageCount++;
}

- (void) quasselMessagesReceived:(NSArray*)messages received:(enum ReceiveStyle)style
{
    self.messageCount += messages.count;
}

- (void) quasselLastSeenMsgUpdated:(MsgId*)messageId forBuffer:(BufferId*)bufferId { }
- (void) quasselNetworkNameUpdated:(NetworkId*)networkId { }

#pragma mark - Report

- (void) dumpBuffers
{
    QuasselCoreConnection *c = self.conn;

    printf("\n%s=== buffers ===%s\n", kBold, kReset);

    NSUInteger total = 0;
    for (NetworkId *nid in c.neworkIdList) {
        NSString *name = [c.networkIdNetworkNameMap objectForKey:nid];
        NSString *nick = [c.networkIdMyNickMap objectForKey:nid];
        printf("\n%s%s%s  %s(nick: %s)%s\n",
               kBold, name ? name.UTF8String : "?", kReset,
               kDim,  nick ? nick.UTF8String : "?", kReset);

        NSArray *bufferIds = [c.networkIdBufferIdListMap objectForKey:nid];
        for (BufferId *bid in bufferIds) {
            BufferInfo *info = [c.bufferIdBufferInfoMap objectForKey:bid];
            if (!info) continue;

            const char *kind = "?";
            switch (info.bufferType) {
                case StatusBuffer:  kind = "status";  break;
                case ChannelBuffer: kind = "channel"; break;
                case QueryBuffer:   kind = "query";   break;
                default: break;
            }
            printf("    %s%-9s%s %s", kCyan, kind, kReset, info.bufferName.UTF8String);

            // Same accessor the AppKit member pane uses, so this exercises the
            // real data path rather than a parallel one.
            if (info.bufferType == ChannelBuffer) {
                NSArray *users = [c ircUsersForChannelWithBufferId:bid];
                if (users.count) {
                    NSMutableArray *nicks = [NSMutableArray array];
                    for (IrcUser *u in users) {
                        [nicks addObject:(u.away
                            ? [NSString stringWithFormat:@"%@(away)", u.nick]
                            : (u.nick ?: @"?"))];
                    }
                    printf("  %s[%lu: %s]%s", kDim, (unsigned long)users.count,
                           [[nicks componentsJoinedByString:@" "] UTF8String], kReset);
                } else {
                    printf("  %s[no members]%s", kDim, kReset);
                }
            }
            printf("\n");
            total++;
        }
    }

    printf("\n%s=== summary ===%s\n", kBold, kReset);
    printf("  networks : %lu\n", (unsigned long)c.neworkIdList.count);
    printf("  buffers  : %lu\n", (unsigned long)total);
    printf("  messages : %lu\n", (unsigned long)self.messageCount);
}

@end


int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc < 4) {
            fprintf(stderr,
                "usage: %s <host> <port> <user> [password]\n"
                "       (or set QUASSEL_PASSWORD)\n", argv[0]);
            return 2;
        }

        NSString *host = [NSString stringWithUTF8String:argv[1]];
        int       port = atoi(argv[2]);
        NSString *user = [NSString stringWithUTF8String:argv[3]];
        NSString *pass = (argc > 4)
            ? [NSString stringWithUTF8String:argv[4]]
            : ([[NSProcessInfo processInfo] environment][@"QUASSEL_PASSWORD"] ?: @"");

        printf("%squassel-gnustep%s  phase 1 harness\n", kBold, kReset);
        printf("  %sconnecting to %s:%d as %s%s\n\n",
               kDim, host.UTF8String, port, user.UTF8String, kReset);

        QuasselCLI *cli = [[QuasselCLI alloc] init];
        QuasselCoreConnection *conn = [[QuasselCoreConnection alloc] init];
        conn.delegate = cli;
        cli.conn = conn;

        [conn connectTo:host port:port userName:user passWord:pass];

        // Drive the run loop until the handshake resolves or we time out.
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30.0];
        NSRunLoop *rl = [NSRunLoop currentRunLoop];
        while (!cli.finished && [deadline timeIntervalSinceNow] > 0) {
            @autoreleasepool {
                [rl runMode:NSDefaultRunLoopMode
                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            }
        }

        if (!cli.finished) {
            fail("timed out after 30s");
            return 1;
        }
        return cli.succeeded ? 0 : 1;
    }
}

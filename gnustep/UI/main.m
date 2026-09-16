//
//  main.m
//  Quassel for GNUstep
//

#import <AppKit/AppKit.h>
#import "QuasselAppDelegate.h"

int main(int argc, const char **argv)
{
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        QuasselAppDelegate *delegate = [[QuasselAppDelegate alloc] init];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}

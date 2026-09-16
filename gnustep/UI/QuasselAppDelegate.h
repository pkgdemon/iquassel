//
//  QuasselAppDelegate.h
//  Quassel for GNUstep
//

#import <AppKit/AppKit.h>

@class MainWindowController;

@interface QuasselAppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, strong) MainWindowController *windowController;

@end

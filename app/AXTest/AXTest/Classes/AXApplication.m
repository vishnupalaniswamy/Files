#import "AXApplication.h"
#import "AXUtilities.h"
#import "NotificationKeys.h"

@interface AXApplication ()
{
  AXUIElementRef applicationElement_;
  AXUIElementRef focusedWindowElementForAXTitleChangedNotification_;
  AXObserverRef observer_;
}
- (void) registerTitleChangedNotification;
@end

static void
observerCallback(AXObserverRef observer, AXUIElementRef element, CFStringRef notification, void* refcon)
{
  AXApplication* self = (__bridge AXApplication*)(refcon);
  if (! self) return;

  if (CFStringCompare(notification, kAXTitleChangedNotification, 0) == kCFCompareEqualTo) {}
  if (CFStringCompare(notification, kAXFocusedUIElementChangedNotification, 0) == kCFCompareEqualTo) {}
  if (CFStringCompare(notification, kAXFocusedWindowChangedNotification, 0) == kCFCompareEqualTo) {
    // ----------------------------------------
    // refresh notification.
    [self registerTitleChangedNotification];
  }

  NSDictionary* userInfo = @{
    @"runningApplication" : self.runningApplication,
    @"notification" : (__bridge NSString*)(notification),
  };
  [[NSNotificationCenter defaultCenter] postNotificationName:kFocusedUIElementChanged object:self userInfo:userInfo];
}

@implementation AXApplication

- (instancetype) initWithRunningApplication:(NSRunningApplication*)runningApplication
{
  self = [super init];

  if (self) {
    self.runningApplication = runningApplication;

    pid_t pid = [self.runningApplication processIdentifier];

    // ----------------------------------------
    // Create applicationElement_

    applicationElement_ = AXUIElementCreateApplication(pid);
    if (! applicationElement_) {
      NSLog(@"AXUIElementCreateApplication is failed. %@", self.runningApplication);
      goto finish;
    }

    // ----------------------------------------
    // Create observer_

    AXError error = AXObserverCreate(pid, observerCallback, &observer_);
    if (error != kAXErrorSuccess) {
      NSLog(@"AXObserverCreate is failed. error:%d %@", error, self.runningApplication);
      goto finish;
    }

    CFRunLoopAddSource(CFRunLoopGetCurrent(),
                       AXObserverGetRunLoopSource(observer_),
                       kCFRunLoopDefaultMode);

    // ----------------------------------------
    // Observe notifications
    [self observeAXNotification:applicationElement_ notification:kAXFocusedUIElementChangedNotification add:YES];
    [self observeAXNotification:applicationElement_ notification:kAXFocusedWindowChangedNotification add:YES];
    [self registerTitleChangedNotification];
  }

finish:
  return self;
}

- (void) dealloc
{
  if (observer_) {
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(),
                          AXObserverGetRunLoopSource(observer_),
                          kCFRunLoopDefaultMode);
    CFRelease(observer_);
    observer_ = NULL;
  }

  if (applicationElement_) {
    CFRelease(applicationElement_);
    applicationElement_ = NULL;
  }
}

- (BOOL) observeAXNotification:(AXUIElementRef)element notification:(CFStringRef)notification add:(BOOL)add
{
  if (! element) return YES;
  if (! observer_) return YES;

  if (add) {
    AXError error = AXObserverAddNotification(observer_,
                                              element,
                                              notification,
                                              (__bridge void*)self);
    if (error != kAXErrorSuccess) {
      if (error == kAXErrorNotificationUnsupported ||
          error == kAXErrorNotificationAlreadyRegistered) {
        // We ignore this error.
        return YES;
      }
      NSLog(@"AXObserverAddNotification is failed: error:%d %@", error, self.runningApplication);
      return NO;
    }

  } else {
    AXError error = AXObserverRemoveNotification(observer_,
                                                 element,
                                                 notification);
    if (error != kAXErrorSuccess) {
      // Note: Ignore kAXErrorInvalidUIElement because it is expected error when focused window is closed.
      if (error == kAXErrorInvalidUIElement ||
          error == kAXErrorNotificationNotRegistered) {
        // We ignore this error.
        return YES;
      }
      NSLog(@"AXObserverRemoveNotification is failed: error:%d %@", error, self.runningApplication);
      return NO;
    }
  }

  return YES;
}

- (void) unregisterTitleChangedNotification
{
  @synchronized(self) {
    if (focusedWindowElementForAXTitleChangedNotification_) {
      [self observeAXNotification:focusedWindowElementForAXTitleChangedNotification_
                     notification:kAXTitleChangedNotification
                              add:NO];

      focusedWindowElementForAXTitleChangedNotification_ = NULL;
    }
  }
}

- (void) registerTitleChangedNotification
{
  @synchronized(self) {
    if (! applicationElement_) return;

    [self unregisterTitleChangedNotification];

    focusedWindowElementForAXTitleChangedNotification_ = [AXUtilities copyFocusedWindow:applicationElement_];
    if (! focusedWindowElementForAXTitleChangedNotification_) return;

    [self observeAXNotification:focusedWindowElementForAXTitleChangedNotification_
                   notification:kAXTitleChangedNotification
                            add:YES];

    NSLog(@"%@ %@", @"registerTitleChangedNotification", self.runningApplication);
  }
}

@end

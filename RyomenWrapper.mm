// ============================================================================
// RosCambo - RyomenX Anti-Record & Hardware StreamProof Stealth Wrapper
// Target: Rules of Survival (ROS Hariki) iOS arm64
// Features: Hardware Screen Recording Masking + Hardware Screenshot Masking +
//           In-Game Anti-Cheat Screenshot Hooking + Capture State Fallback
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

// Forward function pointers
static void (*orig_drawInMTKView)(id self, SEL _cmd, MTKView *view) = NULL;
static UIView* (*orig_superview)(id self, SEL _cmd) = NULL;
static void (*orig_setFrame)(id self, SEL _cmd, CGRect frame) = NULL;
static void (*orig_addSubview)(id self, SEL _cmd, UIView *subview) = NULL;
static void (*orig_bringSubviewToFront)(id self, SEL _cmd, UIView *subview) = NULL;
static BOOL (*orig_drawViewHierarchyInRect)(id self, SEL _cmd, CGRect rect, BOOL afterUpdates) = NULL;
static UIView* (*orig_snapshotViewAfterScreenUpdates)(id self, SEL _cmd, BOOL afterUpdates) = NULL;

// Global references (MRC - non-ARC)
static Class g_overlayClass = Nil;
static UIView *g_targetWindow = nil;
static UIView *g_ryomenOverlayView = nil;

// ----------------------------------------------------------------------------
// Secure Text Field Subclass for Hardware DRM Masking
// ----------------------------------------------------------------------------
@interface RosSecureTextField : UITextField
@end

@implementation RosSecureTextField

- (BOOL)canBecomeFirstResponder {
    return NO;
}

- (BOOL)becomeFirstResponder {
    return NO;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) {
        return nil; // Ignore touches on the container background so game receives them
    }
    return hit;
}

@end

static RosSecureTextField *g_secureTextField = nil;

// ----------------------------------------------------------------------------
// Resolve the internal iOS Secure Canvas (_UITextLayoutCanvasView)
// ----------------------------------------------------------------------------
static UIView* GetSecureCanvas(RosSecureTextField *field) {
    if (!field) return nil;
    [field setNeedsLayout];
    [field layoutIfNeeded];
    
    // Look for canvas subview created by iOS for secureTextEntry
    for (UIView *sub in field.subviews) {
        NSString *cls = NSStringFromClass([sub class]);
        if ([cls containsString:@"Canvas"]) {
            sub.userInteractionEnabled = YES;
            return sub;
        }
    }
    if (field.subviews.count > 0) {
        UIView *first = field.subviews.firstObject;
        first.userInteractionEnabled = YES;
        return first;
    }
    return nil;
}

// ----------------------------------------------------------------------------
// Attach RyomenXOverlayView to the Hardware Secure Container
// ----------------------------------------------------------------------------
static void AttachOverlayToSecureContainer(UIView *targetWindow, UIView *overlayView) {
    if (!targetWindow || !overlayView) return;
    
    if (!g_secureTextField) {
        g_secureTextField = [[RosSecureTextField alloc] initWithFrame:targetWindow.bounds];
        g_secureTextField.backgroundColor = [UIColor clearColor];
        g_secureTextField.secureTextEntry = YES;
        g_secureTextField.userInteractionEnabled = YES;
        g_secureTextField.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        if (orig_addSubview) {
            orig_addSubview(targetWindow, @selector(addSubview:), g_secureTextField);
        } else {
            [targetWindow addSubview:g_secureTextField];
        }
        if (orig_bringSubviewToFront) {
            orig_bringSubviewToFront(targetWindow, @selector(bringSubviewToFront:), g_secureTextField);
        } else {
            [targetWindow bringSubviewToFront:g_secureTextField];
        }
    }
    
    [g_secureTextField setNeedsLayout];
    [g_secureTextField layoutIfNeeded];
    
    UIView *canvas = GetSecureCanvas(g_secureTextField);
    UIView *mountTarget = canvas ? canvas : g_secureTextField;
    
    if (overlayView.superview != mountTarget) {
        [overlayView removeFromSuperview];
        overlayView.frame = mountTarget.bounds;
        overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        if (orig_addSubview) {
            orig_addSubview(mountTarget, @selector(addSubview:), overlayView);
        } else {
            [mountTarget addSubview:overlayView];
        }
        NSLog(@"[RosCambo] Attached RyomenXOverlayView to Secure Canvas (%@)!", [mountTarget class]);
    }
}

// ----------------------------------------------------------------------------
// Hooked methods on RyomenXOverlayView
// ----------------------------------------------------------------------------

// 1. superview: Trick RyomenX's 1-second watchdog into thinking overlay is in window
static UIView* hooked_superview(id self, SEL _cmd) {
    if (g_targetWindow) {
        return g_targetWindow;
    }
    if (orig_superview) {
        return orig_superview(self, _cmd);
    }
    return nil;
}

// 2. setFrame: Keep secureTextField matching window bounds
static void hooked_setFrame(id self, SEL _cmd, CGRect frame) {
    if (g_secureTextField && g_targetWindow) {
        g_secureTextField.frame = g_targetWindow.bounds;
    }
    if (orig_setFrame) {
        orig_setFrame(self, _cmd, frame);
    }
}

// 3. drawInMTKView: Render loop & Screen Recording protection
static void hooked_drawInMTKView(id self, SEL _cmd, MTKView *view) {
    if (!g_ryomenOverlayView && [self isKindOfClass:[UIView class]]) {
        g_ryomenOverlayView = (UIView *)self;
    }
    
    // Ensure overlay remains anchored inside the secure container
    if (g_secureTextField && g_targetWindow && view) {
        UIView *canvas = GetSecureCanvas(g_secureTextField);
        UIView *mountTarget = canvas ? canvas : g_secureTextField;
        if (view.superview != mountTarget) {
            AttachOverlayToSecureContainer(g_targetWindow, (UIView *)view);
        }
    }
    
    // Fallback: If hardware screen recording is active, completely hide overlay
    if (@available(iOS 11.0, *)) {
        if ([UIScreen mainScreen].isCaptured) {
            if (!view.hidden) {
                view.hidden = YES;
            }
            return;
        } else {
            if (view.hidden) {
                view.hidden = NO;
            }
        }
    }
    
    if (orig_drawInMTKView) {
        orig_drawInMTKView(self, _cmd, view);
    }
}

// ----------------------------------------------------------------------------
// Hooked methods on UIView (Interception of RyomenX adding its view to window)
// ----------------------------------------------------------------------------

static void hooked_addSubview(id self, SEL _cmd, UIView *subview) {
    if (subview && g_overlayClass && [subview isKindOfClass:g_overlayClass]) {
        NSLog(@"[RosCambo] Intercepted addSubview: for RyomenXOverlayView!");
        g_targetWindow = (UIView *)self;
        g_ryomenOverlayView = subview;
        AttachOverlayToSecureContainer(g_targetWindow, subview);
        return;
    }
    if (orig_addSubview) {
        orig_addSubview(self, _cmd, subview);
    }
}

static void hooked_bringSubviewToFront(id self, SEL _cmd, UIView *subview) {
    if (subview && g_overlayClass && [subview isKindOfClass:g_overlayClass]) {
        if (g_secureTextField) {
            orig_bringSubviewToFront(self, _cmd, g_secureTextField);
        }
        return;
    }
    if (orig_bringSubviewToFront) {
        orig_bringSubviewToFront(self, _cmd, subview);
    }
}

// ----------------------------------------------------------------------------
// In-Game Anti-Cheat Screenshot Protection
// ----------------------------------------------------------------------------

static BOOL hooked_drawViewHierarchyInRect(id self, SEL _cmd, CGRect rect, BOOL afterUpdates) {
    BOOL wasHidden = NO;
    if (g_secureTextField) {
        wasHidden = g_secureTextField.hidden;
        g_secureTextField.hidden = YES;
    }
    if (g_ryomenOverlayView) {
        g_ryomenOverlayView.hidden = YES;
    }
    
    BOOL result = NO;
    if (orig_drawViewHierarchyInRect) {
        result = orig_drawViewHierarchyInRect(self, _cmd, rect, afterUpdates);
    }
    
    if (g_secureTextField) {
        g_secureTextField.hidden = wasHidden;
    }
    if (g_ryomenOverlayView) {
        g_ryomenOverlayView.hidden = wasHidden;
    }
    return result;
}

static UIView* hooked_snapshotViewAfterScreenUpdates(id self, SEL _cmd, BOOL afterUpdates) {
    BOOL wasHidden = NO;
    if (g_secureTextField) {
        wasHidden = g_secureTextField.hidden;
        g_secureTextField.hidden = YES;
    }
    if (g_ryomenOverlayView) {
        g_ryomenOverlayView.hidden = YES;
    }
    
    UIView *result = nil;
    if (orig_snapshotViewAfterScreenUpdates) {
        result = orig_snapshotViewAfterScreenUpdates(self, _cmd, afterUpdates);
    }
    
    if (g_secureTextField) {
        g_secureTextField.hidden = wasHidden;
    }
    if (g_ryomenOverlayView) {
        g_ryomenOverlayView.hidden = wasHidden;
    }
    return result;
}

// ----------------------------------------------------------------------------
// Swizzle helper
// ----------------------------------------------------------------------------
static void SafeOverrideSubclassMethod(Class cls, SEL sel, IMP newImp, IMP *origImp) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    const char *types = m ? method_getTypeEncoding(m) : "@@:";
    if (m && origImp) {
        *origImp = method_getImplementation(m);
    }
    if (!class_addMethod(cls, sel, newImp, types)) {
        method_setImplementation(m, newImp);
    }
}

static void SwizzleMethod(Class cls, SEL origSel, IMP newImp, IMP *origImp) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, origSel);
    if (!m) return;
    if (origImp) {
        *origImp = method_getImplementation(m);
    }
    method_setImplementation(m, newImp);
}

// ----------------------------------------------------------------------------
// Constructor: Runs when @executable_path/roscheat.dylib is loaded
// ----------------------------------------------------------------------------
__attribute__((constructor))
static void InitRyomenWrapper() {
    NSLog(@"[RosCambo] Initializing RyomenX Hardware StreamProof & Anti-Record Wrapper...");
    
    // 1. Hook In-game Screenshot APIs on UIView
    SwizzleMethod([UIView class], @selector(drawViewHierarchyInRect:afterScreenUpdates:), 
                  (IMP)hooked_drawViewHierarchyInRect, (IMP*)&orig_drawViewHierarchyInRect);
    SwizzleMethod([UIView class], @selector(snapshotViewAfterScreenUpdates:), 
                  (IMP)hooked_snapshotViewAfterScreenUpdates, (IMP*)&orig_snapshotViewAfterScreenUpdates);
    
    // 2. Hook addSubview: and bringSubviewToFront: to trap RyomenX overlay
    SwizzleMethod([UIView class], @selector(addSubview:), 
                  (IMP)hooked_addSubview, (IMP*)&orig_addSubview);
    SwizzleMethod([UIView class], @selector(bringSubviewToFront:), 
                  (IMP)hooked_bringSubviewToFront, (IMP*)&orig_bringSubviewToFront);
    
    // 3. Register screen capture state listener
    if (@available(iOS 11.0, *)) {
        [[NSNotificationCenter defaultCenter] addObserverForName:UIScreenCapturedDidChangeNotification 
                                                         object:nil 
                                                          queue:[NSOperationQueue mainQueue] 
                                                     usingBlock:^(NSNotification *note) {
            BOOL captured = [UIScreen mainScreen].isCaptured;
            NSLog(@"[RosCambo] UIScreen captured state changed: %d", captured);
            if (g_ryomenOverlayView) {
                g_ryomenOverlayView.hidden = captured;
            }
            if (g_secureTextField) {
                g_secureTextField.hidden = captured;
            }
        }];
    }
    
    // 4. Load the cracked/patched RyomenX.dylib
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *ryomenPath = [bundlePath stringByAppendingPathComponent:@"RyomenX.dylib"];
    
    void *handle = dlopen([ryomenPath UTF8String], RTLD_NOW | RTLD_GLOBAL);
    if (!handle) {
        handle = dlopen("@executable_path/RyomenX.dylib", RTLD_NOW | RTLD_GLOBAL);
    }
    
    if (handle) {
        NSLog(@"[RosCambo] RyomenX.dylib loaded successfully at %p", handle);
        
        g_overlayClass = objc_getClass("RyomenXOverlayView");
        if (g_overlayClass) {
            SwizzleMethod(g_overlayClass, sel_registerName("drawInMTKView:"), 
                          (IMP)hooked_drawInMTKView, (IMP*)&orig_drawInMTKView);
            SafeOverrideSubclassMethod(g_overlayClass, @selector(superview), 
                                       (IMP)hooked_superview, (IMP*)&orig_superview);
            SafeOverrideSubclassMethod(g_overlayClass, @selector(setFrame:), 
                                       (IMP)hooked_setFrame, (IMP*)&orig_setFrame);
            NSLog(@"[RosCambo] RyomenXOverlayView swizzled successfully (drawInMTKView, superview, setFrame)!");
        } else {
            NSLog(@"[RosCambo] Warning: RyomenXOverlayView class not found immediately, retrying...");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                g_overlayClass = objc_getClass("RyomenXOverlayView");
                if (g_overlayClass) {
                    SwizzleMethod(g_overlayClass, sel_registerName("drawInMTKView:"), 
                                  (IMP)hooked_drawInMTKView, (IMP*)&orig_drawInMTKView);
                    SafeOverrideSubclassMethod(g_overlayClass, @selector(superview), 
                                               (IMP)hooked_superview, (IMP*)&orig_superview);
                    SafeOverrideSubclassMethod(g_overlayClass, @selector(setFrame:), 
                                               (IMP)hooked_setFrame, (IMP*)&orig_setFrame);
                    NSLog(@"[RosCambo] RyomenXOverlayView swizzled on retry!");
                }
            });
        }
    } else {
        NSLog(@"[RosCambo] Failed to load RyomenX.dylib: %s", dlerror());
    }
}

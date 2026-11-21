// ============================================================================
// RosCambo - RyomenX Anti-Record & Stealth StreamProof Wrapper
// Target: Rules of Survival (ROS Hariki) iOS arm64
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static void (*orig_drawInMTKView)(id self, SEL _cmd, MTKView *view) = NULL;
static BOOL (*orig_drawViewHierarchyInRect)(id self, SEL _cmd, CGRect rect, BOOL afterUpdates) = NULL;
static UIView* (*orig_snapshotViewAfterScreenUpdates)(id self, SEL _cmd, BOOL afterUpdates) = NULL;

static __weak UIView *g_ryomenOverlayView = nil;

// ----------------------------------------------------------------------------
// 1. Hook drawInMTKView: on RyomenXOverlayView
// ----------------------------------------------------------------------------
static void hooked_drawInMTKView(id self, SEL _cmd, MTKView *view) {
    if (!g_ryomenOverlayView && [self isKindOfClass:[UIView class]]) {
        g_ryomenOverlayView = (UIView *)self;
    }
    
    // STREAMPROOF / ANTI-RECORD:
    // If iOS screen recording is active, or if AirPlay / QuickTime USB capture is active:
    // Completely skip rendering. Game framebuffer remains 100% clean and cheat-free.
    if (@available(iOS 11.0, *)) {
        if ([UIScreen mainScreen].isCaptured) {
            return;
        }
    }
    
    if (orig_drawInMTKView) {
        orig_drawInMTKView(self, _cmd, view);
    }
}

// ----------------------------------------------------------------------------
// 2. In-Game Anti-Cheat Screenshot Protection:
// Hook drawViewHierarchyInRect:afterScreenUpdates:
// ----------------------------------------------------------------------------
static BOOL hooked_drawViewHierarchyInRect(id self, SEL _cmd, CGRect rect, BOOL afterUpdates) {
    BOOL wasHidden = NO;
    if (g_ryomenOverlayView) {
        wasHidden = g_ryomenOverlayView.hidden;
        g_ryomenOverlayView.hidden = YES;
    }
    
    BOOL result = NO;
    if (orig_drawViewHierarchyInRect) {
        result = orig_drawViewHierarchyInRect(self, _cmd, rect, afterUpdates);
    }
    
    if (g_ryomenOverlayView) {
        g_ryomenOverlayView.hidden = wasHidden;
    }
    return result;
}

// ----------------------------------------------------------------------------
// 3. In-Game Anti-Cheat Screenshot Protection:
// Hook snapshotViewAfterScreenUpdates:
// ----------------------------------------------------------------------------
static UIView* hooked_snapshotViewAfterScreenUpdates(id self, SEL _cmd, BOOL afterUpdates) {
    BOOL wasHidden = NO;
    if (g_ryomenOverlayView) {
        wasHidden = g_ryomenOverlayView.hidden;
        g_ryomenOverlayView.hidden = YES;
    }
    
    UIView *result = nil;
    if (orig_snapshotViewAfterScreenUpdates) {
        result = orig_snapshotViewAfterScreenUpdates(self, _cmd, afterUpdates);
    }
    
    if (g_ryomenOverlayView) {
        g_ryomenOverlayView.hidden = wasHidden;
    }
    return result;
}

// ----------------------------------------------------------------------------
// Swizzle helper
// ----------------------------------------------------------------------------
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
    NSLog(@"[RosCambo] Initializing RyomenX Stealth & Anti-Record Wrapper...");
    
    // 1. Hook In-game Screenshot APIs on UIView and UIWindow
    SwizzleMethod([UIView class], @selector(drawViewHierarchyInRect:afterScreenUpdates:), 
                  (IMP)hooked_drawViewHierarchyInRect, (IMP*)&orig_drawViewHierarchyInRect);
    SwizzleMethod([UIView class], @selector(snapshotViewAfterScreenUpdates:), 
                  (IMP)hooked_snapshotViewAfterScreenUpdates, (IMP*)&orig_snapshotViewAfterScreenUpdates);
    
    // 2. Load the cracked/patched RyomenX.dylib
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *ryomenPath = [bundlePath stringByAppendingPathComponent:@"RyomenX.dylib"];
    
    void *handle = dlopen([ryomenPath UTF8String], RTLD_NOW | RTLD_GLOBAL);
    if (!handle) {
        handle = dlopen("@executable_path/RyomenX.dylib", RTLD_NOW | RTLD_GLOBAL);
    }
    
    if (handle) {
        NSLog(@"[RosCambo] RyomenX.dylib loaded successfully at %p", handle);
        
        // 3. Swizzle drawInMTKView: on RyomenXOverlayView for Anti-Record
        Class overlayCls = objc_getClass("RyomenXOverlayView");
        if (overlayCls) {
            SwizzleMethod(overlayCls, sel_registerName("drawInMTKView:"), 
                          (IMP)hooked_drawInMTKView, (IMP*)&orig_drawInMTKView);
            NSLog(@"[RosCambo] Swizzled RyomenXOverlayView drawInMTKView: -> Anti-Record ARMED!");
        } else {
            NSLog(@"[RosCambo] Warning: RyomenXOverlayView class not found immediately, setting up retry timer...");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                Class cls = objc_getClass("RyomenXOverlayView");
                if (cls) {
                    SwizzleMethod(cls, sel_registerName("drawInMTKView:"), 
                                  (IMP)hooked_drawInMTKView, (IMP*)&orig_drawInMTKView);
                    NSLog(@"[RosCambo] Swizzled RyomenXOverlayView drawInMTKView: on retry!");
                }
            });
        }
    } else {
        NSLog(@"[RosCambo] Failed to load RyomenX.dylib: %s", dlerror());
    }
}

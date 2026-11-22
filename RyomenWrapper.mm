// ============================================================================
// RosCambo - RyomenX Stealth Hardware StreamProof & Anti-Record Wrapper
// Target: Rules of Survival (ROS Hariki) iOS arm64
// Features: CoreAnimation Hardware DRM Masking (disableUpdateMask 0x12) +
//           ReplayKit / Control Center Active Capture Protection +
//           In-Game Anti-Cheat Screenshot Hooking (UIView & CALayer)
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

// Forward function pointers
static void (*orig_drawInMTKView)(id self, SEL _cmd, MTKView *view) = NULL;
static void (*orig_addSubview)(id self, SEL _cmd, UIView *subview) = NULL;
static BOOL (*orig_drawViewHierarchyInRect)(id self, SEL _cmd, CGRect rect, BOOL afterUpdates) = NULL;
static UIView* (*orig_snapshotViewAfterScreenUpdates)(id self, SEL _cmd, BOOL afterUpdates) = NULL;
static void (*orig_renderInContext)(id self, SEL _cmd, CGContextRef ctx) = NULL;

// Global references
static Class g_overlayClass = Nil;
static UIView *g_ryomenOverlayView = nil;

// ----------------------------------------------------------------------------
// CoreAnimation Hardware DRM StreamProof (disableUpdateMask = 0x12)
// Bit 1 (1 << 1 = 0x02): Mask during ALL Screenshots (Power + Volume Up)
// Bit 4 (1 << 4 = 0x10): Mask during ALL Screen Recordings (ReplayKit, Control Center)
// ----------------------------------------------------------------------------
static void ApplyStreamProofToLayer(CALayer *layer) {
    if (!layer) return;
    
    // Hard guard: NEVER apply StreamProof mask to UIWindow or main game layers!
    if ([layer.delegate isKindOfClass:[UIWindow class]] || 
        [NSStringFromClass([layer class]) containsString:@"Window"]) {
        return;
    }
    
    const unsigned int mask = 0x12; // (1 << 1) | (1 << 4) -> 0x02 (Screenshots) | 0x10 (Screen Recordings)
    
    SEL setMaskSel = sel_registerName("setDisableUpdateMask:");
    if ([layer respondsToSelector:setMaskSel]) {
        typedef void (*SetMaskFunc)(id, SEL, unsigned int);
        ((SetMaskFunc)objc_msgSend)(layer, setMaskSel, mask);
    }
    @try {
        [layer setValue:@(mask) forKey:@"disableUpdateMask"];
    } @catch (id ex) {}
    
    for (CALayer *sub in layer.sublayers) {
        ApplyStreamProofToLayer(sub);
    }
}

// ----------------------------------------------------------------------------
// Hooked methods on RyomenXOverlayView
// ----------------------------------------------------------------------------

// drawInMTKView: Render loop callback (Metal 60/120 FPS)
static void hooked_drawInMTKView(id self, SEL _cmd, MTKView *view) {
    if (!g_ryomenOverlayView && [self isKindOfClass:[UIView class]]) {
        g_ryomenOverlayView = (UIView *)self;
    }
    
    // Refresh StreamProof hardware mask ONLY on the cheat's CAMetalLayer & overlay sublayers
    if (view && view.layer) {
        ApplyStreamProofToLayer(view.layer);
    }
    if (g_ryomenOverlayView && g_ryomenOverlayView != (UIView *)view && g_ryomenOverlayView.layer) {
        ApplyStreamProofToLayer(g_ryomenOverlayView.layer);
    }
    
    // Hardware StreamProof (disableUpdateMask 0x12) masks the overlay at the
    // display compositor level for video recordings and screenshots automatically.
    // The view MUST remain visible on the physical display for real-time play!
    if (view.hidden) {
        view.hidden = NO;
    }
    
    if (orig_drawInMTKView) {
        orig_drawInMTKView(self, _cmd, view);
    }
}

// ----------------------------------------------------------------------------
// Hooked methods on UIView (addSubview:)
// ----------------------------------------------------------------------------

static void hooked_addSubview(id self, SEL _cmd, UIView *subview) {
    if (orig_addSubview) {
        orig_addSubview(self, _cmd, subview);
    }
    
    if (subview) {
        NSString *cls = NSStringFromClass([subview class]);
        if ([cls containsString:@"RyomenXOverlayView"] || 
            (g_overlayClass && [subview isKindOfClass:g_overlayClass])) {
            NSLog(@"[RosCambo] Intercepted RyomenXOverlayView added to window (%@)", [self class]);
            g_ryomenOverlayView = subview;
            ApplyStreamProofToLayer(subview.layer);
        } else if (g_ryomenOverlayView && self == g_ryomenOverlayView) {
            // Subviews added inside the cheat overlay
            ApplyStreamProofToLayer(subview.layer);
        }
    }
}

// ----------------------------------------------------------------------------
// In-Game Anti-Cheat Screenshot Protection
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

static void hooked_renderInContext(id self, SEL _cmd, CGContextRef ctx) {
    if (g_ryomenOverlayView) {
        CALayer *targetLayer = g_ryomenOverlayView.layer;
        for (CALayer *l = (CALayer *)self; l != nil; l = l.superlayer) {
            if (l == targetLayer) {
                return; // Suppress rendering cheat layer into graphics context
            }
        }
    }
    
    if (orig_renderInContext) {
        orig_renderInContext(self, _cmd, ctx);
    }
}

// ----------------------------------------------------------------------------
// Swizzle helper
// ----------------------------------------------------------------------------
static void SwizzleMethod(Class cls, SEL origSel, IMP newImp, IMP *origImp) {
    if (!cls || !origSel || !newImp) return;
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
    NSLog(@"[RosCambo] Initializing Clean RyomenX StreamProof & Anti-Record Wrapper...");
    
    // 1. Hook In-game Screenshot APIs on UIView & CALayer
    SwizzleMethod([UIView class], @selector(drawViewHierarchyInRect:afterScreenUpdates:), 
                  (IMP)hooked_drawViewHierarchyInRect, (IMP*)&orig_drawViewHierarchyInRect);
    SwizzleMethod([UIView class], @selector(snapshotViewAfterScreenUpdates:), 
                  (IMP)hooked_snapshotViewAfterScreenUpdates, (IMP*)&orig_snapshotViewAfterScreenUpdates);
    SwizzleMethod([CALayer class], @selector(renderInContext:), 
                  (IMP)hooked_renderInContext, (IMP*)&orig_renderInContext);
    
    // 2. Hook addSubview: on UIView to detect and mask RyomenXOverlayView
    SwizzleMethod([UIView class], @selector(addSubview:), 
                  (IMP)hooked_addSubview, (IMP*)&orig_addSubview);
    
    // 3. Register screen capture state listener (Control Center, ReplayKit, AirPlay)
    if (@available(iOS 11.0, *)) {
        [[NSNotificationCenter defaultCenter] addObserverForName:UIScreenCapturedDidChangeNotification 
                                                          object:nil 
                                                           queue:[NSOperationQueue mainQueue] 
                                                      usingBlock:^(NSNotification *note) {
            BOOL captured = [UIScreen mainScreen].isCaptured;
            NSLog(@"[RosCambo] UIScreen captured state changed: %d (keeping real-time display visible, hardware mask active)", captured);
            if (g_ryomenOverlayView) {
                g_ryomenOverlayView.hidden = NO;
                ApplyStreamProofToLayer(g_ryomenOverlayView.layer);
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
            NSLog(@"[RosCambo] RyomenXOverlayView drawInMTKView: swizzled successfully!");
        } else {
            NSLog(@"[RosCambo] Warning: RyomenXOverlayView class not found immediately, retrying...");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                g_overlayClass = objc_getClass("RyomenXOverlayView");
                if (g_overlayClass) {
                    SwizzleMethod(g_overlayClass, sel_registerName("drawInMTKView:"), 
                                  (IMP)hooked_drawInMTKView, (IMP*)&orig_drawInMTKView);
                    NSLog(@"[RosCambo] RyomenXOverlayView drawInMTKView: swizzled on retry!");
                }
            });
        }
    } else {
        NSLog(@"[RosCambo] Failed to load RyomenX.dylib: %s", dlerror());
    }
}

// ============================================================================
// RosCambo - RyomenX Anti-Record & Hardware StreamProof Stealth Wrapper
// Target: Rules of Survival (ROS Hariki) iOS arm64
// Features: Hardware Screen Recording Masking + Hardware Screenshot Masking +
//           CoreAnimation disableUpdateMask (0x12) + Secure Canvas Extraction +
//           In-Game Anti-Cheat Screenshot Hooking + Capture State Fallback
// ============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

// Forward function pointers
static void (*orig_drawInMTKView)(id self, SEL _cmd, MTKView *view) = NULL;
static UIView* (*orig_superview)(id self, SEL _cmd) = NULL;
static void (*orig_setFrame)(id self, SEL _cmd, CGRect frame) = NULL;
static void (*orig_addSubview)(id self, SEL _cmd, UIView *subview) = NULL;
static void (*orig_bringSubviewToFront)(id self, SEL _cmd, UIView *subview) = NULL;
static BOOL (*orig_drawViewHierarchyInRect)(id self, SEL _cmd, CGRect rect, BOOL afterUpdates) = NULL;
static UIView* (*orig_snapshotViewAfterScreenUpdates)(id self, SEL _cmd, BOOL afterUpdates) = NULL;
static void (*orig_renderInContext)(id self, SEL _cmd, CGContextRef ctx) = NULL;

// Global references (MRC - non-ARC)
static Class g_overlayClass = Nil;
static UIView *g_targetWindow = nil;
static UIView *g_ryomenOverlayView = nil;
static UIView *g_secureCanvas = nil;
static UITextField *g_seedTextField = nil;

// ----------------------------------------------------------------------------
// CoreAnimation Hardware DRM Masking (disableUpdateMask = 0x12)
// Bit 1 (1 << 1 = 0x2): Mask during ALL Screenshots (Power + Volume Up, SpringBoard)
// Bit 4 (1 << 4 = 0x10): Mask during ALL Screen Recordings (ReplayKit, Control Center)
// ----------------------------------------------------------------------------
static void ApplyStreamProofToLayer(CALayer *layer) {
    if (!layer) return;
    
    const unsigned int mask = 0x12; // (1 << 1) | (1 << 4)
    
    SEL setMaskSel = sel_registerName("setDisableUpdateMask:");
    if ([layer respondsToSelector:setMaskSel]) {
        ((void(*)(id, SEL, unsigned int))objc_msgSend)(layer, setMaskSel, mask);
    }
    
    @try {
        [layer setValue:@(mask) forKey:@"disableUpdateMask"];
    } @catch (id ex) {}
    
    @try {
        [layer setValue:@YES forKey:@"disableProcessAssertion"];
    } @catch (id ex) {}

    @try {
        [layer setValue:@YES forKey:@"disableScreenRecording"];
    } @catch (id ex) {}
    
    for (CALayer *sub in layer.sublayers) {
        ApplyStreamProofToLayer(sub);
    }
}

// ----------------------------------------------------------------------------
// Hardware Secure Canvas Extraction (_UITextLayoutCanvasView)
// ----------------------------------------------------------------------------
static UIView* GetOrCreateSecureCanvas(UIView *targetWindow) {
    if (!targetWindow) return nil;
    if (g_secureCanvas && g_secureCanvas.superview == targetWindow) {
        return g_secureCanvas;
    }
    
    if (!g_seedTextField) {
        g_seedTextField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
        g_seedTextField.backgroundColor = [UIColor clearColor];
        g_seedTextField.secureTextEntry = YES;
        g_seedTextField.userInteractionEnabled = NO;
        g_seedTextField.text = @"\u200B"; // zero-width space forces UIKit canvas creation
        
        if (orig_addSubview) {
            orig_addSubview(targetWindow, @selector(addSubview:), g_seedTextField);
        } else {
            [targetWindow addSubview:g_seedTextField];
        }
        [g_seedTextField setNeedsLayout];
        [g_seedTextField layoutIfNeeded];
    }
    
    UIView *extracted = nil;
    for (UIView *sub in g_seedTextField.subviews) {
        NSString *cls = NSStringFromClass([sub class]);
        if ([cls containsString:@"Canvas"] || [cls containsString:@"Content"]) {
            extracted = sub;
            break;
        }
    }
    if (!extracted && g_seedTextField.subviews.count > 0) {
        extracted = g_seedTextField.subviews.firstObject;
    }
    
    if (extracted) {
        [extracted removeFromSuperview];
        extracted.frame = targetWindow.bounds;
        extracted.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        extracted.userInteractionEnabled = YES;
        
        // Swizzle hitTest on extracted canvas class dynamically so touches pass through background
        Class canvasCls = [extracted class];
        static Class s_swizzledCanvasCls = Nil;
        if (canvasCls != s_swizzledCanvasCls) {
            s_swizzledCanvasCls = canvasCls;
            Method m = class_getInstanceMethod(canvasCls, @selector(hitTest:withEvent:));
            if (m) {
                IMP origHit = method_getImplementation(m);
                IMP newHit = imp_implementationWithBlock(^UIView*(UIView *selfView, CGPoint pt, UIEvent *ev) {
                    UIView *hit = ((UIView*(*)(id, SEL, CGPoint, UIEvent*))origHit)(selfView, @selector(hitTest:withEvent:), pt, ev);
                    if (hit == selfView) {
                        return nil; // Pass touches through to game underneath
                    }
                    return hit;
                });
                method_setImplementation(m, newHit);
            }
        }
        
        if (orig_addSubview) {
            orig_addSubview(targetWindow, @selector(addSubview:), extracted);
        } else {
            [targetWindow addSubview:extracted];
        }
        g_secureCanvas = extracted;
        NSLog(@"[RosCambo] Secure canvas (%@) attached to targetWindow!", [extracted class]);
        return extracted;
    }
    
    return nil;
}

// ----------------------------------------------------------------------------
// Attach RyomenXOverlayView to the Hardware Secure Container
// ----------------------------------------------------------------------------
static void AttachOverlayToSecureContainer(UIView *targetWindow, UIView *overlayView) {
    if (!targetWindow || !overlayView) return;
    
    UIView *canvas = GetOrCreateSecureCanvas(targetWindow);
    UIView *mountTarget = canvas ? canvas : targetWindow;
    
    if (overlayView.superview != mountTarget) {
        [overlayView removeFromSuperview];
        overlayView.frame = mountTarget.bounds;
        overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        if (orig_addSubview) {
            orig_addSubview(mountTarget, @selector(addSubview:), overlayView);
        } else {
            [mountTarget addSubview:overlayView];
        }
        NSLog(@"[RosCambo] Overlay mounted inside (%@)!", [mountTarget class]);
    }
    
    // Apply CoreAnimation streamproof mask to overlay view & canvas
    ApplyStreamProofToLayer(overlayView.layer);
    if (canvas) {
        ApplyStreamProofToLayer(canvas.layer);
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

// 2. setFrame: Keep secureCanvas matching window bounds
static void hooked_setFrame(id self, SEL _cmd, CGRect frame) {
    if (g_secureCanvas && g_targetWindow) {
        g_secureCanvas.frame = g_targetWindow.bounds;
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
    
    // Ensure streamproof mask is continuously refreshed on CAMetalLayer and all sublayers
    if (view && view.layer) {
        ApplyStreamProofToLayer(view.layer);
    }
    
    // Ensure overlay remains anchored inside the secure container
    if (g_targetWindow && view) {
        UIView *canvas = GetOrCreateSecureCanvas(g_targetWindow);
        UIView *mountTarget = canvas ? canvas : g_targetWindow;
        if (view.superview != mountTarget) {
            AttachOverlayToSecureContainer(g_targetWindow, (UIView *)view);
        }
    }
    
    // Active Screen Recording Check (Control Center / ReplayKit / AirPlay / QuickTime)
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
        if (g_secureCanvas) {
            orig_bringSubviewToFront(self, @selector(bringSubviewToFront:), g_secureCanvas);
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
    if (g_secureCanvas) {
        wasHidden = g_secureCanvas.hidden;
        g_secureCanvas.hidden = YES;
    }
    if (g_ryomenOverlayView) {
        g_ryomenOverlayView.hidden = YES;
    }
    
    BOOL result = NO;
    if (orig_drawViewHierarchyInRect) {
        result = orig_drawViewHierarchyInRect(self, _cmd, rect, afterUpdates);
    }
    
    if (g_secureCanvas) {
        g_secureCanvas.hidden = wasHidden;
    }
    if (g_ryomenOverlayView) {
        g_ryomenOverlayView.hidden = wasHidden;
    }
    return result;
}

static UIView* hooked_snapshotViewAfterScreenUpdates(id self, SEL _cmd, BOOL afterUpdates) {
    BOOL wasHidden = NO;
    if (g_secureCanvas) {
        wasHidden = g_secureCanvas.hidden;
        g_secureCanvas.hidden = YES;
    }
    if (g_ryomenOverlayView) {
        g_ryomenOverlayView.hidden = YES;
    }
    
    UIView *result = nil;
    if (orig_snapshotViewAfterScreenUpdates) {
        result = orig_snapshotViewAfterScreenUpdates(self, _cmd, afterUpdates);
    }
    
    if (g_secureCanvas) {
        g_secureCanvas.hidden = wasHidden;
    }
    if (g_ryomenOverlayView) {
        g_ryomenOverlayView.hidden = wasHidden;
    }
    return result;
}

static void hooked_renderInContext(id self, SEL _cmd, CGContextRef ctx) {
    CALayer *l = (CALayer *)self;
    id val = nil;
    @try { val = [l valueForKey:@"disableUpdateMask"]; } @catch (id ex) {}
    if (val && [val intValue] != 0) {
        return; // Suppressed by streamproof mask!
    }
    if (g_ryomenOverlayView && self == g_ryomenOverlayView.layer) {
        return;
    }
    if (g_secureCanvas && self == g_secureCanvas.layer) {
        return;
    }
    if (orig_renderInContext) {
        orig_renderInContext(self, _cmd, ctx);
    }
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
    NSLog(@"[RosCambo] Initializing RyomenX Hardware StreamProof & Anti-Record Wrapper v2...");
    
    // 1. Hook In-game Screenshot APIs on UIView & CALayer
    SwizzleMethod([UIView class], @selector(drawViewHierarchyInRect:afterScreenUpdates:), 
                  (IMP)hooked_drawViewHierarchyInRect, (IMP*)&orig_drawViewHierarchyInRect);
    SwizzleMethod([UIView class], @selector(snapshotViewAfterScreenUpdates:), 
                  (IMP)hooked_snapshotViewAfterScreenUpdates, (IMP*)&orig_snapshotViewAfterScreenUpdates);
    SwizzleMethod([CALayer class], @selector(renderInContext:), 
                  (IMP)hooked_renderInContext, (IMP*)&orig_renderInContext);
    
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
            if (g_secureCanvas) {
                g_secureCanvas.hidden = captured;
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

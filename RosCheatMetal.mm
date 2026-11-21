// =============================================================================
// Project: RosCambo - Rules of Survival Fan-Made Private Server
// Module: Metal ImGui Hook + Circular Draggable Avatar + Touch Safe + Advanced ESP + 50/50 Aimbot
// Target: arm64 / iOS 14.0+
// =============================================================================

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>

#include <vector>
#include <string>
#include <cmath>
#include <unordered_map>
#include <unordered_set>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <pthread.h>
#include <mutex>
#include <atomic>

#include "imgui.h"
#include "imgui_impl_metal.h"
#include "NeoXEngine.h"
#include "ImGuiTheme.h"
#include "AvatarData.h"
#include "Menu.h"

enum AimTriggerMode : int {
    TRIGGER_ALWAYS = 0,
    TRIGGER_SCOPE_ONLY = 1,
    TRIGGER_FIRING_ONLY = 2,
    TRIGGER_SCOPE_AND_FIRING = 3
};

struct RosCheatConfig {
    // Menu defaults to CLOSED. Tapped via Circular Avatar or 3-Finger Tap Gesture.
    bool menu_open = false;
    Vector2 floating_btn_pos = Vector2(40, 70);
    int active_nav_tab = 0; // 0=Visuals, 1=Aim Menu, 2=Settings
    int active_visual_subtab = 0; // 0=Player ESP, 1=Skeletons, 2=Radar 360

    // Rules of Survival ESP Features
    bool esp_enabled = true;
    bool esp_box = true;
    int esp_box_type = 1; // 0=2D Box, 1=Corner Box, 2=Filled Box
    bool esp_snaplines = true;
    int snapline_pos = 0; // 0=Bottom, 1=Crosshair, 2=Top
    bool esp_skeleton = true;
    bool esp_health = true;
    bool esp_distance = true;
    bool esp_name = true;
    bool esp_bot_indicator = true;
    bool esp_offscreen_360 = true;
    bool esp_crosshair = true;

    float box_thickness = 1.8f;
    float line_transparency = 100.0f;
    float line_thickness = 1.5f;
    float skeleton_thickness = 1.5f;
    float max_esp_distance = 600.0f; // Ghillie map battle range

    // Rules of Survival Aimbot Features
    bool aimbot_enabled = true;
    int aim_target_bone = BONE_HEAD; // 0=Head, 1=Neck, 2=Chest, 3=Pelvis
    int aim_trigger_mode = TRIGGER_ALWAYS; // 0=Always, 1=Scope Only, 2=Firing Only, 3=Scope & Firing
    bool aim_silent = false;
    bool aim_360 = false;
    int aim_snap_mode = 1; // 0=Custom Smooth, 1=Aim 50% (+50% Player Skill), 2=Aim 100% (Instant Rage)
    float aim_skill_ratio = 0.50f; // 50% Magnetic pull + 50% Player Touch Skill
    float aim_fov = 140.0f;
    float aim_smooth = 6.0f;
    bool draw_fov_circle = true;

    // Ranked Match / Anti-Cheat Safe Guards
    bool ghillie_terrain_filter = true;
    bool team_check = true;
};

static RosCheatConfig g_Cheat;

// Dynamic touch inputs
static bool g_IsTouchingFire = false;
static bool g_IsTouchingScope = false;
static CGPoint g_LastTouchPos = { 0.0f, 0.0f };
static CGPoint g_TouchDelta = { 0.0f, 0.0f };

// Avatar Texture Cache
static id<MTLTexture> s_AvatarTexture = nil;

static void LoadAvatarTexture(id<MTLDevice> device) {
    if (s_AvatarTexture != nil || !device) return;

    UIImage* uiImage = nil;

    // 1. Try to load from application bundle
    NSString* appPath = [[NSBundle mainBundle] bundlePath];
    NSArray<NSString*>* searchPaths = @[
        [appPath stringByAppendingPathComponent:@"asset/avartar.jpg"],
        [appPath stringByAppendingPathComponent:@"asset/avartar.png"],
        [appPath stringByAppendingPathComponent:@"avartar.jpg"],
        [appPath stringByAppendingPathComponent:@"avartar.png"]
    ];

    for (NSString* path in searchPaths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            uiImage = [UIImage imageWithContentsOfFile:path];
            if (uiImage) break;
        }
    }

    // 2. Fallback: Load directly from embedded binary buffer
    if (!uiImage && kAvatarJpgDataSize > 0) {
        NSData* data = [NSData dataWithBytes:kAvatarJpgData length:kAvatarJpgDataSize];
        uiImage = [UIImage imageWithData:data];
    }

    if (!uiImage) return;

    CGImageRef cgImage = uiImage.CGImage;
    if (!cgImage) return;

    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);

    MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                    width:width
                                                                                   height:height
                                                                                mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead;
    s_AvatarTexture = [device newTextureWithDescriptor:desc];

    NSMutableData* rawData = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(rawData.mutableBytes,
                                             width,
                                             height,
                                             8,
                                             width * 4,
                                             colorSpace,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);

    if (ctx) {
        CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), cgImage);
        CGContextRelease(ctx);
        [s_AvatarTexture replaceRegion:MTLRegionMake2D(0, 0, width, height)
                           mipmapLevel:0
                             withBytes:rawData.bytes
                           bytesPerRow:width * 4];
    }
}

// =============================================================================
// CUSTOM IOS TOGGLE SWITCHES & SLIDERS
// =============================================================================
static bool ToggleSwitch(const char* str_id, bool* v) {
    ImVec2 p = ImGui::GetCursorScreenPos();
    ImDrawList* draw_list = ImGui::GetWindowDrawList();

    float height = 24.0f;
    float width = 44.0f;
    float radius = height * 0.5f;

    ImGui::InvisibleButton(str_id, ImVec2(width, height));
    if (ImGui::IsItemClicked()) {
        *v = !(*v);
    }

    float t = *v ? 1.0f : 0.0f;
    ImU32 col_bg = *v ? IM_COL32(0, 160, 245, 255) : IM_COL32(40, 48, 62, 255);

    draw_list->AddRectFilled(p, ImVec2(p.x + width, p.y + height), col_bg, radius);
    float circle_x = p.x + radius + t * (width - 2.0f * radius);
    draw_list->AddCircleFilled(ImVec2(circle_x, p.y + radius), radius - 2.5f, IM_COL32(255, 255, 255, 255));

    return *v;
}

static void DrawSettingSwitch(const char* label, bool* v) {
    ImGui::AlignTextToFramePadding();
    ImGui::TextUnformatted(label);
    float avail_w = ImGui::GetContentRegionAvail().x;
    float switch_w = 44.0f;
    float target_x = ImGui::GetCursorPosX() + avail_w - switch_w;
    if (target_x > ImGui::GetCursorPosX()) {
        ImGui::SameLine(target_x);
    } else {
        ImGui::SameLine();
    }
    char id_buf[64];
    snprintf(id_buf, sizeof(id_buf), "##sw_%s", label);
    ToggleSwitch(id_buf, v);
    ImGui::Spacing();
}

static void DrawSettingSlider(const char* label, float* v, float min, float max, const char* fmt = "%.2f") {
    char val_buf[32];
    snprintf(val_buf, sizeof(val_buf), fmt, *v);

    ImGui::AlignTextToFramePadding();
    ImGui::TextUnformatted(label);

    float val_w = ImGui::CalcTextSize(val_buf).x;
    float avail_w = ImGui::GetContentRegionAvail().x;
    float target_x = ImGui::GetCursorPosX() + avail_w - val_w;
    if (target_x > ImGui::GetCursorPosX()) {
        ImGui::SameLine(target_x);
    } else {
        ImGui::SameLine();
    }
    ImGui::TextColored(ImVec4(0.00f, 0.75f, 1.00f, 1.0f), "%s", val_buf);

    char id_buf[64];
    snprintf(id_buf, sizeof(id_buf), "##sl_%s", label);
    ImGui::PushItemWidth(-1);
    ImGui::SliderFloat(id_buf, v, min, max, "");
    ImGui::PopItemWidth();
    ImGui::Spacing();
}

// =============================================================================
// MULTI-VTABLE HOOKS & RUNTIME TELEMETRY FOR CLIENTAPP
// VTable Slots in Mach-O __DATA:
// base + 0x33D8D98: ClientApp::onBasePlayerCreate(this, int local_id, ...)
// base + 0x33D8DA8: ClientApp::getEntity(this, int id)
// base + 0x33D8DE8: ClientApp::onEntityMove(this, int id, a3, a4, Vector3* pos)
// base + 0x33D8DF8: ClientApp::spaceData(this, ...)
// =============================================================================
typedef void (*onEntityMove_t)(uintptr_t this_ptr, int entity_id, uintptr_t a3, uintptr_t a4, const Vector3* pos_ptr, uintptr_t a6, uintptr_t a7);
static onEntityMove_t s_OrigOnEntityMove = nullptr;

typedef void (*onBasePlayerCreate_t)(uintptr_t this_ptr, int id, uintptr_t a3, uintptr_t a4);
static onBasePlayerCreate_t s_OrigOnBasePlayerCreate = nullptr;

typedef void (*spaceData_t)(uintptr_t this_ptr, uintptr_t a1, uintptr_t a2, int space_id, uintptr_t a4);
static spaceData_t s_OrigSpaceData = nullptr;

typedef uintptr_t (*getEntity_t)(uintptr_t this_ptr, int id);
static getEntity_t s_OrigGetEntity = nullptr;

static uintptr_t s_CapturedEntityManager = 0;
static uintptr_t s_ActiveCamera = 0;
static Vector2 s_ActiveAimCorrection = { 0.0f, 0.0f };
static int s_CapturedLocalId = -1;
static uint64_t s_MoveHookHits = 0;
static uint64_t s_CreateHookHits = 0;
static uint64_t s_SpaceDataHits = 0;
static uint64_t s_FrameCount = 0;

struct CachedEntityPos {
    Vector3 pos;
    uint64_t tick;
};
static std::unordered_map<int, CachedEntityPos> s_CachedEntityPositions;

static void Hooked_onEntityMove(uintptr_t this_ptr, int entity_id, uintptr_t a3, uintptr_t a4, const Vector3* pos_ptr, uintptr_t a6, uintptr_t a7) {
    s_MoveHookHits++;
    if (this_ptr > 0x100000000ULL) {
        s_CapturedEntityManager = this_ptr;
    }
    if (pos_ptr && MemoryEngine::IsValidAddress((uintptr_t)pos_ptr)) {
        Vector3 p = *pos_ptr; // Zero-overhead direct read in-process
        if (p.Length() > 1.0f && std::abs(p.x) < 20000.0f && std::abs(p.y) < 20000.0f && std::abs(p.z) < 20000.0f) {
            s_CachedEntityPositions[entity_id] = { p, s_FrameCount };
        }
    }
    if (s_OrigOnEntityMove) {
        s_OrigOnEntityMove(this_ptr, entity_id, a3, a4, pos_ptr, a6, a7);
    }
}

static void Hooked_onBasePlayerCreate(uintptr_t this_ptr, int id, uintptr_t a3, uintptr_t a4) {
    s_CreateHookHits++;
    if (this_ptr > 0x100000000ULL) {
        s_CapturedEntityManager = this_ptr;
        s_CapturedLocalId = id;
    }
    if (s_OrigOnBasePlayerCreate) {
        s_OrigOnBasePlayerCreate(this_ptr, id, a3, a4);
    }
}

static void Hooked_spaceData(uintptr_t this_ptr, uintptr_t a1, uintptr_t a2, int space_id, uintptr_t a4) {
    s_SpaceDataHits++;
    if (this_ptr > 0x100000000ULL) {
        s_CapturedEntityManager = this_ptr;
    }
    if (s_OrigSpaceData) {
        s_OrigSpaceData(this_ptr, a1, a2, space_id, a4);
    }
}

static uintptr_t Hooked_getEntity(uintptr_t this_ptr, int id) {
    if (this_ptr > 0x100000000ULL) {
        s_CapturedEntityManager = this_ptr;
    }
    if (s_OrigGetEntity) {
        return s_OrigGetEntity(this_ptr, id);
    }
    return 0;
}

static void InstallVTableHooks() {
    static bool s_Hooked = false;
    if (s_Hooked) return;

    uintptr_t base = MemoryEngine::GetBaseAddress();
    if (!base) return;

    uintptr_t slot_create = base + 0x33D8D98;
    uintptr_t slot_get    = base + 0x33D8DA8;
    uintptr_t slot_move   = base + 0x33D8DE8;
    uintptr_t slot_space  = base + 0x33D8DF8;

    vm_address_t page = slot_create & ~0x3FFFULL;
    vm_protect(mach_task_self(), page, 0x4000, FALSE, VM_PROT_READ | VM_PROT_WRITE);

    // Direct memory read/write for in-process vtable hooking
    uintptr_t fn_move = *(uintptr_t*)slot_move;
    if (fn_move != 0 && fn_move != (uintptr_t)&Hooked_onEntityMove) {
        s_OrigOnEntityMove = (onEntityMove_t)fn_move;
        *(uintptr_t*)slot_move = (uintptr_t)&Hooked_onEntityMove;
    }

    uintptr_t fn_create = *(uintptr_t*)slot_create;
    if (fn_create != 0 && fn_create != (uintptr_t)&Hooked_onBasePlayerCreate) {
        s_OrigOnBasePlayerCreate = (onBasePlayerCreate_t)fn_create;
        *(uintptr_t*)slot_create = (uintptr_t)&Hooked_onBasePlayerCreate;
    }

    uintptr_t fn_space = *(uintptr_t*)slot_space;
    if (fn_space != 0 && fn_space != (uintptr_t)&Hooked_spaceData) {
        s_OrigSpaceData = (spaceData_t)fn_space;
        *(uintptr_t*)slot_space = (uintptr_t)&Hooked_spaceData;
    }

    uintptr_t fn_get = *(uintptr_t*)slot_get;
    if (fn_get != 0 && fn_get != (uintptr_t)&Hooked_getEntity) {
        s_OrigGetEntity = (getEntity_t)fn_get;
        *(uintptr_t*)slot_get = (uintptr_t)&Hooked_getEntity;
    }

    s_Hooked = true;
}

// Direct Heap Scanner for ClientApp instance (matches vtable base + 0x33D8D98 and base + 0x33D8E80)
static uintptr_t ScanHeapForClientApp(uintptr_t base) {
    if (!base) return 0;
    uintptr_t expected_v1 = base + 0x33D8D98;
    uintptr_t expected_v2 = base + 0x33D8E80;

    vm_address_t address = 0;
    vm_size_t size = 0;
    mach_port_t object_name = MACH_PORT_NULL;

    while (true) {
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
        kern_return_t kr = vm_region_64(mach_task_self(), &address, &size,
                                        VM_REGION_BASIC_INFO_64,
                                        (vm_region_info_t)&info, &count, &object_name);
        if (kr != KERN_SUCCESS) break;

        // Search readable & writable regions (heap)
        if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE) && size >= 0x1000) {
            const size_t CHUNK = 0x10000;
            alignas(16) uint8_t buf[CHUNK];
            size_t max_scan = std::min((size_t)size, (size_t)0x2000000);
            for (vm_address_t cur = address; cur < address + max_scan; cur += CHUNK) {
                size_t to_read = std::min((size_t)(address + max_scan - cur), CHUNK);
                vm_size_t bytes_read = 0;
                if (vm_read_overwrite(mach_task_self(), cur, to_read, (vm_address_t)buf, &bytes_read) == KERN_SUCCESS && bytes_read >= 16) {
                    size_t n_ptrs = bytes_read / sizeof(uintptr_t);
                    uintptr_t* ptrs = (uintptr_t*)buf;
                    for (size_t p = 0; p + 1 < n_ptrs; ++p) {
                        if (ptrs[p] == expected_v1 && ptrs[p+1] == expected_v2) {
                            return cur + p * sizeof(uintptr_t);
                        }
                    }
                }
            }
        }
        address += size;
    }
    return 0;
}

// Direct Heap Scanner for NeoX 3D CameraBase (vtable: 0x34609A8) and fallback cocos2d::Camera (0x341BD48)
static uintptr_t ScanHeapForCamera(uintptr_t base) {
    if (!base) return 0;
    uintptr_t neox_camerabase_vt = base + NeoXOffsets::NEOX_CAMERABASE_VTABLE;
    uintptr_t neox_worldcam_vt = base + NeoXOffsets::NEOX_WORLDCAMERA_VTABLE;
    uintptr_t cocos_camera_vt = base + NeoXOffsets::CAMERA_VTABLE;

    vm_address_t address = 0;
    vm_size_t size = 0;
    mach_port_t object_name = MACH_PORT_NULL;
    uintptr_t fallback_cam = 0;

    while (true) {
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
        kern_return_t kr = vm_region_64(mach_task_self(), &address, &size,
                                        VM_REGION_BASIC_INFO_64,
                                        (vm_region_info_t)&info, &count, &object_name);
        if (kr != KERN_SUCCESS) break;

        // Search readable & writable heap regions
        if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_WRITE) && size >= 0x1000) {
            const size_t CHUNK = 0x10000;
            alignas(16) uint8_t buf[CHUNK];
            size_t max_scan = std::min((size_t)size, (size_t)0x2000000);
            for (vm_address_t cur = address; cur < address + max_scan; cur += CHUNK) {
                size_t to_read = std::min((size_t)(address + max_scan - cur), CHUNK);
                vm_size_t bytes_read = 0;
                if (vm_read_overwrite(mach_task_self(), cur, to_read, (vm_address_t)buf, &bytes_read) == KERN_SUCCESS && bytes_read >= 8) {
                    size_t n_ptrs = bytes_read / sizeof(uintptr_t);
                    uintptr_t* ptrs = (uintptr_t*)buf;
                    for (size_t p = 0; p < n_ptrs; ++p) {
                        uintptr_t vt = ptrs[p];
                        if (vt == neox_camerabase_vt) {
                            uintptr_t cam = cur + p * sizeof(uintptr_t);
                            if (ProjectionEngine::IsValidCameraBase(cam)) {
                                return cam; // Exact 3D Gameplay Camera!
                            }
                        } else if (vt == neox_worldcam_vt) {
                            uintptr_t wcam = cur + p * sizeof(uintptr_t);
                            uintptr_t base_cam = MemoryEngine::Read<uintptr_t>(wcam + 0x70);
                            if (!MemoryEngine::IsValidAddress(base_cam)) {
                                base_cam = MemoryEngine::Read<uintptr_t>(wcam + 0x40);
                            }
                            if (MemoryEngine::IsValidAddress(base_cam) && MemoryEngine::Read<uintptr_t>(base_cam) == neox_camerabase_vt) {
                                if (ProjectionEngine::IsValidCameraBase(base_cam)) {
                                    return base_cam;
                                }
                            }
                        } else if (vt == cocos_camera_vt && fallback_cam == 0) {
                            uintptr_t ccam = cur + p * sizeof(uintptr_t);
                            Matrix4x4 cam_vp = MemoryEngine::Read<Matrix4x4>(ccam + NeoXOffsets::CAMERA_VIEW_PROJ);
                            if (ProjectionEngine::IsValidViewProjMatrix(cam_vp)) {
                                fallback_cam = ccam;
                            }
                        }
                    }
                }
            }
        }
        address += size;
    }
    return fallback_cam;
}

// =============================================================================
// DYNAMIC GAME STATE AND MATRIX SCANNER
// =============================================================================
class RosGameScanner {
public:
    static bool FetchState(std::vector<RosPlayer>& out_players,
                           Vector3& out_local_pos,
                           int& out_local_team,
                           Matrix4x4& out_vp,
                           float& out_camera_yaw,
                           bool& out_is_firing,
                           bool& out_is_scoped) {
        s_FrameCount++;
        out_players.clear();
        out_is_firing = g_IsTouchingFire;
        out_is_scoped = g_IsTouchingScope;

        uintptr_t base = MemoryEngine::GetBaseAddress();
        if (!base) return false;

        InstallVTableHooks();

        // 1. Resolve ViewProjection Matrix:
        // Priority 1: Check existing cached camera
        if (s_ActiveCamera && MemoryEngine::IsValidAddress(s_ActiveCamera)) {
            uintptr_t vt = MemoryEngine::Read<uintptr_t>(s_ActiveCamera);
            if (vt == base + NeoXOffsets::NEOX_CAMERABASE_VTABLE) {
                if (ProjectionEngine::IsValidCameraBase(s_ActiveCamera)) {
                    ProjectionEngine::s_ActiveCameraPtr = s_ActiveCamera;
                    Matrix4x4 cam_vp = MemoryEngine::Read<Matrix4x4>(s_ActiveCamera + NeoXOffsets::NEOX_CAMERA_VIEW_PROJ);
                    if (ProjectionEngine::IsValidViewProjMatrix(cam_vp)) {
                        out_vp = cam_vp;
                    } else {
                        out_vp = MemoryEngine::Read<Matrix4x4>(s_ActiveCamera + NeoXOffsets::NEOX_CAMERA_RAW_PROJ);
                    }
                    float m20 = MemoryEngine::Read<float>(s_ActiveCamera + 0x60);
                    float m22 = MemoryEngine::Read<float>(s_ActiveCamera + 0x68);
                    if (std::abs(m20) > 0.0001f || std::abs(m22) > 0.0001f) {
                        out_camera_yaw = atan2f(m20, m22);
                    }
                } else {
                    s_ActiveCamera = 0;
                    ProjectionEngine::s_ActiveCameraPtr = 0;
                }
            } else if (vt == base + NeoXOffsets::CAMERA_VTABLE) {
                Matrix4x4 cam_vp = MemoryEngine::Read<Matrix4x4>(s_ActiveCamera + NeoXOffsets::CAMERA_VIEW_PROJ);
                if (ProjectionEngine::IsValidViewProjMatrix(cam_vp)) {
                    out_vp = cam_vp;
                    Matrix4x4 view_mat = MemoryEngine::Read<Matrix4x4>(s_ActiveCamera + NeoXOffsets::CAMERA_VIEW);
                    if (std::abs(view_mat.m[0][0]) > 0.0001f || std::abs(view_mat.m[2][0]) > 0.0001f) {
                        out_camera_yaw = atan2f(view_mat.m[0][2], view_mat.m[2][2]);
                    }
                } else {
                    s_ActiveCamera = 0;
                }
            } else {
                s_ActiveCamera = 0;
            }
        }

        // Priority 2: Direct static pointers in __DATA
        if (!ProjectionEngine::IsValidViewProjMatrix(out_vp)) {
            uintptr_t static_cam_ptrs[] = {
                base + NeoXOffsets::NEOX_CAMERA_GLOBAL_1,
                base + NeoXOffsets::NEOX_CAMERA_GLOBAL_2,
                base + NeoXOffsets::CAMERA_GLOBAL_POOL
            };
            for (uintptr_t ptr_addr : static_cam_ptrs) {
                uintptr_t candidate = MemoryEngine::Read<uintptr_t>(ptr_addr);
                if (MemoryEngine::IsValidAddress(candidate)) {
                    uintptr_t vt = MemoryEngine::Read<uintptr_t>(candidate);
                    if (vt == base + NeoXOffsets::NEOX_CAMERABASE_VTABLE) {
                        if (ProjectionEngine::IsValidCameraBase(candidate)) {
                            s_ActiveCamera = candidate;
                            ProjectionEngine::s_ActiveCameraPtr = candidate;
                            Matrix4x4 cam_vp = MemoryEngine::Read<Matrix4x4>(candidate + NeoXOffsets::NEOX_CAMERA_VIEW_PROJ);
                            out_vp = ProjectionEngine::IsValidViewProjMatrix(cam_vp) ? cam_vp : MemoryEngine::Read<Matrix4x4>(candidate + NeoXOffsets::NEOX_CAMERA_RAW_PROJ);
                            break;
                        }
                    } else if (vt == base + NeoXOffsets::NEOX_WORLDCAMERA_VTABLE) {
                        uintptr_t base_cam = MemoryEngine::Read<uintptr_t>(candidate + 0x70);
                        if (!MemoryEngine::IsValidAddress(base_cam)) {
                            base_cam = MemoryEngine::Read<uintptr_t>(candidate + 0x40);
                        }
                        if (MemoryEngine::IsValidAddress(base_cam) && MemoryEngine::Read<uintptr_t>(base_cam) == base + NeoXOffsets::NEOX_CAMERABASE_VTABLE) {
                            if (ProjectionEngine::IsValidCameraBase(base_cam)) {
                                s_ActiveCamera = base_cam;
                                ProjectionEngine::s_ActiveCameraPtr = base_cam;
                                Matrix4x4 cam_vp = MemoryEngine::Read<Matrix4x4>(base_cam + NeoXOffsets::NEOX_CAMERA_VIEW_PROJ);
                                out_vp = ProjectionEngine::IsValidViewProjMatrix(cam_vp) ? cam_vp : MemoryEngine::Read<Matrix4x4>(base_cam + NeoXOffsets::NEOX_CAMERA_RAW_PROJ);
                                break;
                            }
                        }
                    }
                }
            }
        }

        // Priority 3: cocos2d::Director -> Scene -> Cameras fallback
        if (!ProjectionEngine::IsValidViewProjMatrix(out_vp)) {
            uintptr_t director_ptr = MemoryEngine::Read<uintptr_t>(base + NeoXOffsets::DIRECTOR_GLOBAL_PTR);
            if (MemoryEngine::IsValidAddress(director_ptr)) {
                uintptr_t scene_ptr = MemoryEngine::Read<uintptr_t>(director_ptr + NeoXOffsets::DIRECTOR_RUNNING_SCENE);
                if (!MemoryEngine::IsValidAddress(scene_ptr)) {
                    scene_ptr = MemoryEngine::Read<uintptr_t>(director_ptr + 0x1A0); // fallback offset
                }
                if (MemoryEngine::IsValidAddress(scene_ptr)) {
                    uintptr_t sc_cam = MemoryEngine::Read<uintptr_t>(scene_ptr + NeoXOffsets::SCENE_DEFAULT_CAMERA);
                    if (MemoryEngine::IsValidAddress(sc_cam) && MemoryEngine::Read<uintptr_t>(sc_cam) == base + NeoXOffsets::CAMERA_VTABLE) {
                        Matrix4x4 cam_vp = MemoryEngine::Read<Matrix4x4>(sc_cam + NeoXOffsets::CAMERA_VIEW_PROJ);
                        if (ProjectionEngine::IsValidViewProjMatrix(cam_vp)) {
                            s_ActiveCamera = sc_cam;
                            out_vp = cam_vp;
                        }
                    }
                }
            }
        }

        // Priority 4: Background asynchronous heap scanner (NEVER blocks render loop!)
        static std::atomic<bool> s_IsScanningCamera{false};
        if (!s_ActiveCamera && !s_IsScanningCamera.load()) {
            s_IsScanningCamera.store(true);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                uintptr_t found_cam = ScanHeapForCamera(base);
                if (found_cam) {
                    s_ActiveCamera = found_cam;
                    NSLog(@"[RosCambo] Background scan resolved 3D CameraBase at 0x%lx", found_cam);
                }
                s_IsScanningCamera.store(false);
            });
        }

        // 2. Resolve ClientApp:
        // Priority 1: Verified static pointer at base + 0x37819F0 (0x100883c48: ldr x0, [base + 0x37819F0])
        if (!MemoryEngine::IsValidAddress(s_CapturedEntityManager)) {
            uintptr_t global_app = MemoryEngine::Read<uintptr_t>(base + NeoXOffsets::CLIENTAPP_GLOBAL_PTR);
            if (MemoryEngine::IsValidAddress(global_app)) {
                uintptr_t v1 = MemoryEngine::Read<uintptr_t>(global_app);
                if (v1 >= base && v1 < base + 0x5000000) {
                    s_CapturedEntityManager = global_app;
                }
            }
            // Heap scan for ClientApp is only done once on initialization or on-demand
        }

        uintptr_t client_app = s_CapturedEntityManager;

        // Camera Yaw extraction from active camera view matrix
        if (s_ActiveCamera && MemoryEngine::IsValidAddress(s_ActiveCamera)) {
            uintptr_t vt = MemoryEngine::Read<uintptr_t>(s_ActiveCamera);
            if (vt == base + NeoXOffsets::NEOX_CAMERABASE_VTABLE) {
                float m20 = MemoryEngine::Read<float>(s_ActiveCamera + 0x60);
                float m22 = MemoryEngine::Read<float>(s_ActiveCamera + 0x68);
                if (std::abs(m20) > 0.0001f || std::abs(m22) > 0.0001f) {
                    out_camera_yaw = atan2f(m20, m22);
                }
            } else {
                Matrix4x4 view_mat = MemoryEngine::Read<Matrix4x4>(s_ActiveCamera + NeoXOffsets::CAMERA_VIEW);
                if (std::abs(view_mat.m[0][0]) > 0.0001f || std::abs(view_mat.m[2][0]) > 0.0001f) {
                    out_camera_yaw = atan2f(view_mat.m[0][2], view_mat.m[2][2]);
                }
            }
        }

        // 3. Resolve Local Player via PlayerManager singleton (0x10089a794 / base + 0x39AB428)
        uintptr_t local_mgr = MemoryEngine::Read<uintptr_t>(base + NeoXOffsets::LOCAL_PLAYER_MGR_PTR);
        uintptr_t local_player_entity = 0;
        int local_id = s_CapturedLocalId;

        if (MemoryEngine::IsValidAddress(local_mgr)) {
            local_player_entity = MemoryEngine::Read<uintptr_t>(local_mgr + 0x00);
            if (MemoryEngine::IsValidAddress(local_player_entity)) {
                Vector3 lp = MemoryEngine::Read<Vector3>(local_player_entity + NeoXOffsets::ENTITY_COORDS);
                if (lp.Length() > 0.1f && std::abs(lp.x) < 20000.0f) {
                    out_local_pos = lp;
                }
                out_local_team = MemoryEngine::Read<int>(local_player_entity + NeoXOffsets::ENTITY_TEAM);
                if (local_id <= 0) {
                    local_id = MemoryEngine::Read<int>(local_player_entity + NeoXOffsets::ENTITY_ID);
                }
            }
        }

        if (local_id <= 0 && MemoryEngine::IsValidAddress(client_app)) {
            local_id = MemoryEngine::Read<int>(client_app + NeoXOffsets::CLIENTAPP_LOCAL_PLAYER_ID);
        }

        if (out_local_pos.Length() < 0.1f && local_id > 0 && s_CachedEntityPositions.count(local_id)) {
            out_local_pos = s_CachedEntityPositions[local_id].pos;
        }

        // 4. Extract Entities from ClientApp (All 3 Hash Tables: 0xF80, 0xFA8, 0xFD0)
        if (MemoryEngine::IsValidAddress(client_app)) {
            uintptr_t heads[] = {
                MemoryEngine::Read<uintptr_t>(client_app + NeoXOffsets::CLIENTAPP_FIRST_NODE),
                MemoryEngine::Read<uintptr_t>(client_app + NeoXOffsets::CLIENTAPP_SECOND_NODE),
                MemoryEngine::Read<uintptr_t>(client_app + NeoXOffsets::CLIENTAPP_THIRD_NODE)
            };
            std::unordered_set<uintptr_t> visited_entities;

            auto process_entity_fn = [&](uintptr_t entity, int ent_id) {
                if (!MemoryEngine::IsValidAddress(entity) || visited_entities.count(entity)) return;
                visited_entities.insert(entity);

                int read_id = MemoryEngine::Read<int>(entity + NeoXOffsets::ENTITY_ID);
                if (read_id > 0) ent_id = read_id;

                uint8_t self_ctrl = MemoryEngine::Read<uint8_t>(entity + NeoXOffsets::ENTITY_SELF_CONTROLLED);
                if (self_ctrl != 0 || entity == local_player_entity || (local_id > 0 && ent_id == local_id)) {
                    Vector3 lp = MemoryEngine::Read<Vector3>(entity + NeoXOffsets::ENTITY_COORDS);
                    if (lp.Length() > 0.1f && std::abs(lp.x) < 20000.0f) {
                        out_local_pos = lp;
                    }
                    local_player_entity = entity;
                    local_id = ent_id;
                    return;
                }

                Vector3 pos = MemoryEngine::Read<Vector3>(entity + NeoXOffsets::ENTITY_COORDS);
                if (s_CachedEntityPositions.count(ent_id)) {
                    pos = s_CachedEntityPositions[ent_id].pos;
                }

                if (pos.Length() >= 1.0f && std::abs(pos.x) < 25000.0f && std::abs(pos.z) < 25000.0f) {
                    if (ent_id <= 0) return;
                    int raw_hp = MemoryEngine::Read<int>(entity + NeoXOffsets::ENTITY_HP);
                    int raw_max_hp = MemoryEngine::Read<int>(entity + NeoXOffsets::ENTITY_MAX_HP);

                    RosPlayer p{};
                    p.instance = entity;
                    p.id = ent_id;
                    p.position = pos;
                    p.health = (raw_hp > 0 && raw_hp <= 500) ? raw_hp : 100;
                    p.max_health = (raw_max_hp > 0 && raw_max_hp <= 500) ? raw_max_hp : 100;
                    p.team_id = MemoryEngine::Read<int>(entity + NeoXOffsets::ENTITY_TEAM);
                    p.stance = MemoryEngine::Read<int>(entity + NeoXOffsets::ENTITY_STANCE);
                    p.is_bot = ((uint32_t)ent_id <= 0x40000000);

                    float dist = (out_local_pos.Length() > 0.1f) ? (p.position - out_local_pos).Length() : 0.0f;
                    p.distance = dist;

                    if (dist <= g_Cheat.max_esp_distance || g_Cheat.max_esp_distance <= 0.0f) {
                        snprintf(p.name, sizeof(p.name), "%s", p.is_bot ? "[BOT] Patrol" : "Survivor");

                        // Build procedural humanoid skeleton based on position & stance
                        p.has_bones = true;
                        float h = (p.stance == 1) ? 1.30f : ((p.stance == 2) ? 0.60f : 1.75f);
                        Vector3 head = p.position + Vector3(0, h, 0);
                        p.head_pos = head;
                        p.bones[BONE_HEAD]       = head;
                        p.bones[BONE_NECK]       = p.position + Vector3(0, h * 0.88f, 0);
                        p.bones[BONE_CHEST]      = p.position + Vector3(0, h * 0.72f, 0);
                        p.bones[BONE_PELVIS]     = p.position + Vector3(0, h * 0.48f, 0);
                        p.bones[BONE_L_SHOULDER] = p.bones[BONE_NECK] + Vector3(-0.25f, -0.05f, 0);
                        p.bones[BONE_L_ELBOW]    = p.bones[BONE_L_SHOULDER] + Vector3(-0.15f, -0.22f, 0);
                        p.bones[BONE_L_HAND]     = p.bones[BONE_L_ELBOW] + Vector3(0, -0.20f, 0);
                        p.bones[BONE_R_SHOULDER] = p.bones[BONE_NECK] + Vector3(0.25f, -0.05f, 0);
                        p.bones[BONE_R_ELBOW]    = p.bones[BONE_R_SHOULDER] + Vector3(0.15f, -0.22f, 0);
                        p.bones[BONE_R_HAND]     = p.bones[BONE_R_ELBOW] + Vector3(0, -0.20f, 0);
                        p.bones[BONE_L_HIP]      = p.bones[BONE_PELVIS] + Vector3(-0.16f, -0.06f, 0);
                        p.bones[BONE_L_KNEE]     = p.bones[BONE_L_HIP] + Vector3(0, -0.22f, 0);
                        p.bones[BONE_L_FOOT]     = p.bones[BONE_L_KNEE] + Vector3(0, -0.20f, 0);
                        p.bones[BONE_R_HIP]      = p.bones[BONE_PELVIS] + Vector3(0.16f, -0.06f, 0);
                        p.bones[BONE_R_KNEE]     = p.bones[BONE_R_HIP] + Vector3(0, -0.22f, 0);
                        p.bones[BONE_R_FOOT]     = p.bones[BONE_R_KNEE] + Vector3(0, -0.20f, 0);

                        out_players.push_back(p);
                    }
                }
            };

            // 1. Traverse linked list heads (Contains all active entities with 0-overhead)
            for (uintptr_t head : heads) {
                uintptr_t node = head;
                int safety = 0;
                while (MemoryEngine::IsValidAddress(node) && ++safety < 500) {
                    int ent_id = MemoryEngine::Read<int>(node + NeoXOffsets::HASH_NODE_KEY);
                    uintptr_t entity = MemoryEngine::Read<uintptr_t>(node + NeoXOffsets::HASH_NODE_VALUE);
                    process_entity_fn(entity, ent_id);
                    node = MemoryEngine::Read<uintptr_t>(node + NeoXOffsets::HASH_NODE_NEXT);
                }
            }
        }

        // 5. Fallback: If hash table was empty, use live cached positions from onEntityMove
        if (out_players.empty() && !s_CachedEntityPositions.empty()) {
            for (const auto& kv : s_CachedEntityPositions) {
                if (kv.first == local_id) continue;
                if (kv.second.pos.Length() < 1.0f) continue;

                RosPlayer p{};
                p.instance = (uintptr_t)kv.first;
                p.id = kv.first;
                p.position = kv.second.pos;
                p.health = 100;
                p.max_health = 100;
                p.team_id = 999;
                p.stance = 0;
                p.is_bot = ((uint32_t)kv.first <= 0x40000000);
                float h = 1.75f;
                Vector3 head = p.position + Vector3(0, h, 0);
                p.head_pos = head;
                p.has_bones = true;
                p.bones[BONE_HEAD]       = head;
                p.bones[BONE_NECK]       = p.position + Vector3(0, h * 0.88f, 0);
                p.bones[BONE_CHEST]      = p.position + Vector3(0, h * 0.72f, 0);
                p.bones[BONE_PELVIS]     = p.position + Vector3(0, h * 0.48f, 0);
                p.bones[BONE_L_SHOULDER] = p.bones[BONE_NECK] + Vector3(-0.25f, -0.05f, 0);
                p.bones[BONE_L_ELBOW]    = p.bones[BONE_L_SHOULDER] + Vector3(-0.15f, -0.22f, 0);
                p.bones[BONE_L_HAND]     = p.bones[BONE_L_ELBOW] + Vector3(0, -0.20f, 0);
                p.bones[BONE_R_SHOULDER] = p.bones[BONE_NECK] + Vector3(0.25f, -0.05f, 0);
                p.bones[BONE_R_ELBOW]    = p.bones[BONE_R_SHOULDER] + Vector3(0.15f, -0.22f, 0);
                p.bones[BONE_R_HAND]     = p.bones[BONE_R_ELBOW] + Vector3(0, -0.20f, 0);
                p.bones[BONE_L_HIP]      = p.bones[BONE_PELVIS] + Vector3(-0.16f, -0.06f, 0);
                p.bones[BONE_L_KNEE]     = p.bones[BONE_L_HIP] + Vector3(0, -0.22f, 0);
                p.bones[BONE_L_FOOT]     = p.bones[BONE_L_KNEE] + Vector3(0, -0.20f, 0);
                p.bones[BONE_R_HIP]      = p.bones[BONE_PELVIS] + Vector3(0.16f, -0.06f, 0);
                p.bones[BONE_R_KNEE]     = p.bones[BONE_R_HIP] + Vector3(0, -0.22f, 0);
                p.bones[BONE_R_FOOT]     = p.bones[BONE_R_KNEE] + Vector3(0, -0.20f, 0);

                p.distance = (out_local_pos.Length() > 0.1f) ? (p.position - out_local_pos).Length() : 0.0f;
                snprintf(p.name, sizeof(p.name), "%s #%d", p.is_bot ? "[BOT]" : "Survivor", kv.first);
                out_players.push_back(p);
            }
        }

        return true;
    }
};

// =============================================================================
// GAMEPLAY DEBUG SCANNER & USB LOGGER (Writes to Documents/debug.txt & NSLog)
// =============================================================================
static std::string s_LatestDebugReport = "";
static std::mutex s_DebugReportMutex;

static void DumpGameplayDebugToFile(const std::vector<RosPlayer>& in_players, const Vector3& in_local_pos, int in_local_team, const Matrix4x4& in_vp, float in_camera_yaw, CGSize in_screenSize, bool is_manual_dump = false) {
    // Make deep copies of stack variables BEFORE GCD async dispatch!
    std::vector<RosPlayer> players = in_players;
    Vector3 local_pos = in_local_pos;
    int local_team = in_local_team;
    Matrix4x4 vp = in_vp;
    float camera_yaw = in_camera_yaw;
    CGSize screenSize = in_screenSize;

    // Copy data to background worker queue so Metal rendering never drops a single frame
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        @autoreleasepool {
            NSMutableString* log = [NSMutableString string];
            NSDateFormatter* df = [[NSDateFormatter alloc] init];
            [df setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
            NSString* timeStr = [df stringFromDate:[NSDate date]];

            [log appendFormat:@"==================================================\n"];
            [log appendFormat:@"[ROSCAMBO ECLIPSE DEBUG SCAN REPORT]\n"];
            [log appendFormat:@"Timestamp: %@\n", timeStr];
            [log appendFormat:@"Frame: %llu\n", s_FrameCount];
            [log appendFormat:@"Screen: %.0f x %.0f (Center: %.1f, %.1f)\n", screenSize.width, screenSize.height, screenSize.width * 0.5f, screenSize.height * 0.5f];
            
            uintptr_t base = MemoryEngine::GetBaseAddress();
            [log appendFormat:@"\n--- MEMORY & BASE ---\n"];
            [log appendFormat:@"Mach-O Base: 0x%lx\n", base];
            [log appendFormat:@"ClientApp Ptr: 0x%lx (Valid: %d)\n", s_CapturedEntityManager, MemoryEngine::IsValidAddress(s_CapturedEntityManager) ? 1 : 0];
            
            if (MemoryEngine::IsValidAddress(s_CapturedEntityManager)) {
                uintptr_t vtable = MemoryEngine::Read<uintptr_t>(s_CapturedEntityManager);
                [log appendFormat:@"ClientApp VTable: 0x%lx\n", vtable];
                
                // Map 1 (0xF70)
                size_t map1_cnt = MemoryEngine::Read<size_t>(s_CapturedEntityManager + 0xF78);
                uintptr_t map1_head = MemoryEngine::Read<uintptr_t>(s_CapturedEntityManager + 0xF80);
                [log appendFormat:@"Table 1 (0xF70): cnt=%zu, head=0x%lx\n", map1_cnt, map1_head];
                
                // Map 2 (0xF98) - Avatars
                size_t map2_cnt = MemoryEngine::Read<size_t>(s_CapturedEntityManager + 0xFA0);
                uintptr_t map2_head = MemoryEngine::Read<uintptr_t>(s_CapturedEntityManager + 0xFA8);
                [log appendFormat:@"Table 2 [Players] (0xF98): cnt=%zu, head=0x%lx\n", map2_cnt, map2_head];
                
                // Map 3 (0xFC0) - Props/Vehicles
                size_t map3_cnt = MemoryEngine::Read<size_t>(s_CapturedEntityManager + 0xFC8);
                uintptr_t map3_head = MemoryEngine::Read<uintptr_t>(s_CapturedEntityManager + 0xFD0);
                [log appendFormat:@"Table 3 (0xFC0): cnt=%zu, head=0x%lx\n", map3_cnt, map3_head];
            }

            [log appendFormat:@"\n--- CAMERA & PROJECTION ---\n"];
            uintptr_t cam_vt = s_ActiveCamera ? MemoryEngine::Read<uintptr_t>(s_ActiveCamera) : 0;
            const char* cam_desc = "None";
            uint16_t cam_flag = 0;
            if (cam_vt == base + NeoXOffsets::NEOX_CAMERABASE_VTABLE) {
                cam_desc = "NeoX::CameraBase (3D)";
                float proj_y = MemoryEngine::Read<float>(s_ActiveCamera + 0xD4);
                float aspect = MemoryEngine::Read<float>(s_ActiveCamera + 0x398);
                uint8_t is_ortho = MemoryEngine::Read<uint8_t>(s_ActiveCamera + 0x380);
                [log appendFormat:@"Camera NeoX: ProjY=%.4f, Aspect=%.4f, Ortho=%u\n", proj_y, aspect, (unsigned)is_ortho];
            } else if (cam_vt == base + NeoXOffsets::NEOX_WORLDCAMERA_VTABLE) {
                cam_desc = "NeoX::WorldCamera";
            } else if (cam_vt == base + NeoXOffsets::CAMERA_VTABLE) {
                cam_desc = "Cocos2d::Camera (2D)";
                cam_flag = MemoryEngine::Read<uint16_t>(s_ActiveCamera + NeoXOffsets::CAMERA_FLAG);
            }
            [log appendFormat:@"Active Camera: 0x%lx (%s, Flag: %u, VTable: 0x%lx)\n", s_ActiveCamera, cam_desc, cam_flag, cam_vt];
            [log appendFormat:@"Camera Yaw: %.4f rad (%.1f deg)\n", camera_yaw, camera_yaw * 57.2958f];
            bool vp_valid = ProjectionEngine::IsValidViewProjMatrix(vp);
            [log appendFormat:@"VP Valid: %d\n", vp_valid ? 1 : 0];
            [log appendFormat:@"VP Matrix:\n"];
            [log appendFormat:@"  [ %8.4f, %8.4f, %8.4f, %8.4f ]\n", vp.m[0][0], vp.m[0][1], vp.m[0][2], vp.m[0][3]];
            [log appendFormat:@"  [ %8.4f, %8.4f, %8.4f, %8.4f ]\n", vp.m[1][0], vp.m[1][1], vp.m[1][2], vp.m[1][3]];
            [log appendFormat:@"  [ %8.4f, %8.4f, %8.4f, %8.4f ]\n", vp.m[2][0], vp.m[2][1], vp.m[2][2], vp.m[2][3]];
            [log appendFormat:@"  [ %8.4f, %8.4f, %8.4f, %8.4f ]\n", vp.m[3][0], vp.m[3][1], vp.m[3][2], vp.m[3][3]];

            [log appendFormat:@"\n--- LOCAL PLAYER ---\n"];
            [log appendFormat:@"Local ID: %d | Team: %d\n", s_CapturedLocalId, local_team];
            [log appendFormat:@"Local Pos: X=%.2f, Y=%.2f, Z=%.2f (Len=%.2f)\n", local_pos.x, local_pos.y, local_pos.z, local_pos.Length()];

            [log appendFormat:@"\n--- HOOKS & TELEMETRY ---\n"];
            [log appendFormat:@"onEntityMove Hits: %llu\n", s_MoveHookHits];
            [log appendFormat:@"onBasePlayerCreate Hits: %llu\n", s_CreateHookHits];
            [log appendFormat:@"spaceData Hits: %llu\n", s_SpaceDataHits];
            [log appendFormat:@"Cached Positions Count: %zu\n", s_CachedEntityPositions.size()];

            [log appendFormat:@"\n--- PLAYERS / ENTITIES DETECTED (%zu) ---\n", players.size()];
            size_t idx = 0;
            for (const auto& p : players) {
                Vector2 screen_head, screen_feet;
                bool w2s_head = ProjectionEngine::WorldToScreen(p.head_pos, screen_head, vp, screenSize.width, screenSize.height, s_ActiveCamera);
                bool w2s_feet = ProjectionEngine::WorldToScreen(p.position, screen_feet, vp, screenSize.width, screenSize.height, s_ActiveCamera);

                [log appendFormat:@"[%02zu] ID:%d | Inst:0x%lx | Bot:%d | HP:%d/%d | Dist:%.1fm\n",
                 idx++, p.id, p.instance, p.is_bot ? 1 : 0, p.health, p.max_health, p.distance];
                [log appendFormat:@"     World Pos: (%.2f, %.2f, %.2f) | Head: (%.2f, %.2f, %.2f)\n",
                 p.position.x, p.position.y, p.position.z, p.head_pos.x, p.head_pos.y, p.head_pos.z];
                [log appendFormat:@"     W2S Head: vis=%d, pos=(%.1f, %.1f) | Feet: vis=%d, pos=(%.1f, %.1f)\n",
                 w2s_head ? 1 : 0, screen_head.x, screen_head.y, w2s_feet ? 1 : 0, screen_feet.x, screen_feet.y];
                if (idx >= 60) {
                    [log appendFormat:@"     ... and %zu more entities truncated\n", players.size() - idx];
                    break;
                }
            }
            [log appendFormat:@"==================================================\n\n"];

            // 1. Write to Documents/debug.txt only on manual snapshot to prevent iOS flash I/O lag
            if (is_manual_dump) {
                NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                if (paths.count > 0) {
                    NSString* docDir = [paths firstObject];
                    NSString* filePath = [docDir stringByAppendingPathComponent:@"debug.txt"];
                    NSError* err = nil;
                    [log writeToFile:filePath atomically:NO encoding:NSUTF8StringEncoding error:&err];
                    if (err) {
                        NSLog(@"[RosCambo-DEBUG] Failed to write debug.txt: %@", err);
                    }
                }
            }

            // 2. Copy to iOS System Clipboard (only on manual dump to prevent UI freeze)
            if (is_manual_dump) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [UIPasteboard generalPasteboard].string = log;
                });
            }

            // 3. Stream compact summary to USB syslog (NSLog)
            NSLog(@"[RosCambo-DEBUG] F:%llu | App:0x%lx | Cam:0x%lx | VP_Valid:%d | LP:(%.1f,%.1f,%.1f) | Ents:%zu | MoveHits:%llu",
                  s_FrameCount, s_CapturedEntityManager, s_ActiveCamera, vp_valid ? 1 : 0,
                  local_pos.x, local_pos.y, local_pos.z, players.size(), s_MoveHookHits);

            // 4. Auto-Push to PC Debug Server over Wi-Fi
            Menu::Config& cfg = Menu::Cfg();
            if (cfg.autoSendToPc && cfg.serverIp[0] != '\0') {
                NSString* hostStr = [NSString stringWithUTF8String:cfg.serverIp];
                NSString* urlStr = [NSString stringWithFormat:@"http://%@/debug", hostStr];
                NSURL* targetUrl = [NSURL URLWithString:urlStr];
                if (targetUrl) {
                    NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:targetUrl
                                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                                   timeoutInterval:2.0];
                    [req setHTTPMethod:@"POST"];
                    [req setValue:@"text/plain; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
                    [req setHTTPBody:[log dataUsingEncoding:NSUTF8StringEncoding]];

                    NSURLSessionDataTask* task = [[NSURLSession sharedSession] dataTaskWithRequest:req
                        completionHandler:^(NSData* _Nullable d, NSURLResponse* _Nullable r, NSError* _Nullable err) {
                            if (!err) {
                                NSLog(@"[RosCambo-DEBUG] Successfully pushed report to PC (%@)", hostStr);
                            } else {
                                NSLog(@"[RosCambo-DEBUG] Push to PC error: %@", err.localizedDescription);
                            }
                        }];
                    [task resume];
                }
            }

            // 5. Update USB Live Debugger stream buffer (Port 1337)
            {
                std::lock_guard<std::mutex> lock(s_DebugReportMutex);
                s_LatestDebugReport = [log UTF8String];
            }
        }
    });
}

// =============================================================================
// USB LIVE DEBUGGER TCP SERVER (Port 1337 via USBMUX)
// =============================================================================
static int s_UsbDebugServerFd = -1;
static std::atomic<int> s_UsbClientFd{-1};

static void* UsbDebugServerThread(void* arg) {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) {
        NSLog(@"[RosCambo-USB] socket() error: %s", strerror(errno));
        return NULL;
    }
    
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(1337);
    
    if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        NSLog(@"[RosCambo-USB] bind() failed on port 1337: %s", strerror(errno));
        close(server_fd);
        return NULL;
    }
    
    if (listen(server_fd, 4) < 0) {
        NSLog(@"[RosCambo-USB] listen() failed: %s", strerror(errno));
        close(server_fd);
        return NULL;
    }
    
    s_UsbDebugServerFd = server_fd;
    NSLog(@"[RosCambo-USB] USB Live Debugger listening on port 1337 over usbmuxd.");
    
    while (true) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        int client_fd = accept(server_fd, (struct sockaddr*)&client_addr, &client_len);
        if (client_fd < 0) {
            usleep(100000);
            continue;
        }
        
        int set_nosigpipe = 1;
        setsockopt(client_fd, SOL_SOCKET, SO_NOSIGPIPE, (void*)&set_nosigpipe, sizeof(int));
        
        struct timeval tv;
        tv.tv_sec = 0;
        tv.tv_usec = 50000; // 50ms
        setsockopt(client_fd, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof(tv));
        
        NSLog(@"[RosCambo-USB] PC connected to Live USB Debugger (fd=%d)!", client_fd);
        s_UsbClientFd.store(client_fd);
        
        const char* banner = "=== ROSCAMBO ECLIPSE USB LIVE DEBUGGER CONNECTED ===\n";
        send(client_fd, banner, strlen(banner), 0);
        
        char rx_buf[256];
        while (s_UsbClientFd.load() == client_fd) {
            ssize_t n = recv(client_fd, rx_buf, sizeof(rx_buf) - 1, 0);
            if (n > 0) {
                rx_buf[n] = '\0';
                std::string cmd(rx_buf);
                while (!cmd.empty() && (cmd.back() == '\r' || cmd.back() == '\n' || cmd.back() == ' ')) {
                    cmd.pop_back();
                }
                NSLog(@"[RosCambo-USB] PC command: %s", cmd.c_str());
                if (cmd == "SCAN" || cmd == "CAM") {
                    uintptr_t base = MemoryEngine::GetBaseAddress();
                    uintptr_t found = ScanHeapForCamera(base);
                    if (found) s_ActiveCamera = found;
                    const char* res = found ? "[OK] Camera scanned and found!\n" : "[INFO] Camera scan complete.\n";
                    send(client_fd, res, strlen(res), 0);
                } else if (cmd == "DUMP") {
                    g_TriggerDebugDump = true;
                    const char* res = "[OK] Dump triggered.\n";
                    send(client_fd, res, strlen(res), 0);
                } else if (cmd == "ESP") {
                    Menu::Cfg().espEnabled = !Menu::Cfg().espEnabled;
                    const char* res = Menu::Cfg().espEnabled ? "[OK] ESP Enabled\n" : "[OK] ESP Disabled\n";
                    send(client_fd, res, strlen(res), 0);
                } else if (cmd == "PING") {
                    send(client_fd, "PONG\n", 5, 0);
                }
            } else if (n == 0) {
                break;
            } else {
                if (errno != EAGAIN && errno != EWOULDBLOCK) {
                    break;
                }
            }
            
            std::string to_send;
            {
                std::lock_guard<std::mutex> lock(s_DebugReportMutex);
                if (!s_LatestDebugReport.empty()) {
                    to_send = std::move(s_LatestDebugReport);
                    s_LatestDebugReport.clear();
                }
            }
            if (!to_send.empty()) {
                std::string packet = to_send + "\n<<<ROSCAMBO_EOF>>>\n";
                ssize_t sent = send(client_fd, packet.c_str(), packet.length(), 0);
                if (sent < 0) {
                    break;
                }
            }
            
            usleep(50000); // 50ms poll
        }
        
        close(client_fd);
        s_UsbClientFd.store(-1);
        NSLog(@"[RosCambo-USB] PC disconnected from Live USB Debugger.");
    }
    return NULL;
}

static void StartUsbDebugServer() {
    pthread_t thread;
    pthread_create(&thread, NULL, UsbDebugServerThread, NULL);
    pthread_detach(thread);
}

// =============================================================================
// METAL OVERLAY LIFECYCLE
// =============================================================================
static id<MTLDevice> s_MetalDevice = nil;
static bool s_ImGuiReady = false;

static void InitializeMetalOverlay(id<MTLDevice> device) {
    if (s_ImGuiReady || !device) return;

    s_MetalDevice = device;
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();

    ImGuiIO& io = ImGui::GetIO();
    io.IniFilename = nullptr; // Stateless configuration
    io.MouseDrawCursor = false;

    Menu::ApplyWhiteTheme(1.0f, ImVec4(0.20f, 0.45f, 1.0f, 1.0f));
    ImGui_ImplMetal_Init(device);
    LoadAvatarTexture(device);
    g_MenuAvatarTexture = (__bridge void*)s_AvatarTexture;

    s_ImGuiReady = true;
}

// Visual helpers
static void DrawCornerBox(ImDrawList* draw, float x, float y, float w, float h, ImU32 col, float thickness) {
    float line_w = w * 0.28f;
    float line_h = h * 0.22f;

    draw->AddLine(ImVec2(x, y), ImVec2(x + line_w, y), col, thickness);
    draw->AddLine(ImVec2(x, y), ImVec2(x, y + line_h), col, thickness);

    draw->AddLine(ImVec2(x + w, y), ImVec2(x + w - line_w, y), col, thickness);
    draw->AddLine(ImVec2(x + w, y), ImVec2(x + w, y + line_h), col, thickness);

    draw->AddLine(ImVec2(x, y + h), ImVec2(x + line_w, y + h), col, thickness);
    draw->AddLine(ImVec2(x, y + h), ImVec2(x, y + h - line_h), col, thickness);

    draw->AddLine(ImVec2(x + w, y + h), ImVec2(x + w - line_w, y + h), col, thickness);
    draw->AddLine(ImVec2(x + w, y + h), ImVec2(x + w, y + h - line_h), col, thickness);
}

static void RenderOffscreenRadarArrow(ImDrawList* draw, const Vector3& target_pos, const Vector3& local_pos, float camera_yaw, const Vector2& screen_center, float radius, ImU32 col) {
    Vector3 diff = target_pos - local_pos;
    float target_angle = atan2f(diff.x, diff.z);
    float rel_angle = target_angle - camera_yaw;

    float arrow_x = screen_center.x + sinf(rel_angle) * radius;
    float arrow_y = screen_center.y - cosf(rel_angle) * radius;

    float tip_len = 14.0f;
    float wing_w = 7.0f;

    Vector2 tip(arrow_x + sinf(rel_angle) * tip_len, arrow_y - cosf(rel_angle) * tip_len);
    Vector2 left(arrow_x - cosf(rel_angle) * wing_w, arrow_y - sinf(rel_angle) * wing_w);
    Vector2 right(arrow_x + cosf(rel_angle) * wing_w, arrow_y + sinf(rel_angle) * wing_w);

    draw->AddTriangleFilled(ImVec2(tip.x, tip.y), ImVec2(left.x, left.y), ImVec2(right.x, right.y), col);
}

static void Apply5050SkillBlendAimbot(const Vector2& target_screen, const Vector2& screen_center) {
    Vector2 aim_error = target_screen - screen_center;
    Vector2 magnetic_pull = aim_error * (1.0f / (g_Cheat.aim_smooth + 0.01f));
    Vector2 final_correction = magnetic_pull;

    if (g_Cheat.aim_snap_mode == 1) { // 50/50 Skill Blend
        Vector2 player_touch_influence = Vector2(g_TouchDelta.x, g_TouchDelta.y);
        final_correction = (magnetic_pull * g_Cheat.aim_skill_ratio) + (player_touch_influence * (1.0f - g_Cheat.aim_skill_ratio));
    } else if (g_Cheat.aim_snap_mode == 2) { // 100% Rage Snap
        final_correction = aim_error;
    }

    s_ActiveAimCorrection = final_correction;

    if (fabsf(final_correction.x) > 0.05f || fabsf(final_correction.y) > 0.05f) {
        float sens = 0.0020f;
        if (s_ActiveCamera && MemoryEngine::IsValidAddress(s_ActiveCamera)) {
            float cur_pitch = MemoryEngine::Read<float>(s_ActiveCamera + 0x20C);
            float cur_yaw   = MemoryEngine::Read<float>(s_ActiveCamera + 0x210);

            if (std::abs(cur_pitch) < 3.2f && std::abs(cur_yaw) < 100.0f) {
                cur_yaw   += final_correction.x * sens;
                cur_pitch -= final_correction.y * sens;
                if (cur_pitch > 1.55f) cur_pitch = 1.55f;
                if (cur_pitch < -1.55f) cur_pitch = -1.55f;
                MemoryEngine::Write<float>(s_ActiveCamera + 0x20C, cur_pitch);
                MemoryEngine::Write<float>(s_ActiveCamera + 0x210, cur_yaw);
            }
        } else {
            uintptr_t client_app = s_CapturedEntityManager;
            if (!MemoryEngine::IsValidAddress(client_app)) {
                uintptr_t base = MemoryEngine::GetBaseAddress();
                client_app = MemoryEngine::Read<uintptr_t>(base + NeoXOffsets::CLIENTAPP_GLOBAL_PTR);
            }
            if (MemoryEngine::IsValidAddress(client_app)) {
                uintptr_t camera_obj = MemoryEngine::Read<uintptr_t>(client_app + 0x2A0);
                if (MemoryEngine::IsValidAddress(camera_obj)) {
                    float cur_pitch = MemoryEngine::Read<float>(camera_obj + 0x20C);
                    float cur_yaw   = MemoryEngine::Read<float>(camera_obj + 0x210);
                    cur_yaw   += final_correction.x * sens;
                    cur_pitch -= final_correction.y * sens;
                    if (cur_pitch > 1.55f) cur_pitch = 1.55f;
                    if (cur_pitch < -1.55f) cur_pitch = -1.55f;
                    MemoryEngine::Write<float>(camera_obj + 0x20C, cur_pitch);
                    MemoryEngine::Write<float>(camera_obj + 0x210, cur_yaw);
                }
            }
        }
    }
}

static bool IsAimbotTriggerConditionMet(bool is_firing, bool is_scoped) {
    switch (g_Cheat.aim_trigger_mode) {
        case TRIGGER_ALWAYS:
            return true;
        case TRIGGER_SCOPE_ONLY:
            return is_scoped;
        case TRIGGER_FIRING_ONLY:
            return is_firing;
        case TRIGGER_SCOPE_AND_FIRING:
            return (is_scoped || is_firing);
        default:
            return true;
    }
}

// =============================================================================
// DEBOUNCED MENU STATE CONTROLLER
// =============================================================================
static double s_LastMenuToggleTime = 0.0;
static void SetMenuOpen(bool open) {
    double now = [NSDate date].timeIntervalSince1970;
    if (now - s_LastMenuToggleTime < 0.20) {
        return; // 200ms debounce
    }
    s_LastMenuToggleTime = now;
    g_Cheat.menu_open = open;

    // Reset touch down states immediately to prevent click bleed-through
    ImGuiIO& io = ImGui::GetIO();
    io.MouseDown[0] = false;
    io.MouseClicked[0] = false;
    io.MouseReleased[0] = false;
}

// =============================================================================
// MAIN OVERLAY RENDER LOOP (Encoded into the Game's Command Buffer)
// =============================================================================
static void RenderRosCamboOverlay(id<MTLCommandBuffer> commandBuffer, id<CAMetalDrawable> drawable) {
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    if (screenSize.width < screenSize.height) {
        CGFloat tmp = screenSize.width;
        screenSize.width = screenSize.height;
        screenSize.height = tmp;
    }
    float scale = [UIScreen mainScreen].scale;

    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2(screenSize.width, screenSize.height);
    io.DisplayFramebufferScale = ImVec2(scale, scale);

    static double s_LastRenderTime = 0.0;
    double cur_time = [NSDate date].timeIntervalSince1970;
    if (s_LastRenderTime > 0.0) {
        io.DeltaTime = (float)(cur_time - s_LastRenderTime);
        if (io.DeltaTime <= 0.001f || io.DeltaTime > 0.1f) io.DeltaTime = 1.0f / 60.0f;
    } else {
        io.DeltaTime = 1.0f / 60.0f;
    }
    s_LastRenderTime = cur_time;

    MTLRenderPassDescriptor* passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    passDesc.colorAttachments[0].texture = drawable.texture;
    // MTLLoadActionLoad preserves the game's already-rendered 3D world underneath
    passDesc.colorAttachments[0].loadAction = MTLLoadActionLoad;
    passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDesc];
    if (!encoder) return;

    ImGui_ImplMetal_NewFrame(passDesc);
    ImGui::NewFrame();

    // Sync Cheat Configurations with ECLIPSE Menu
    Menu::Config& cfg = Menu::Cfg();
    g_Cheat.esp_enabled = cfg.espEnabled;
    g_Cheat.esp_box = cfg.espBox;
    g_Cheat.esp_box_type = cfg.espBoxStyle;
    g_Cheat.esp_skeleton = cfg.espSkeleton;
    g_Cheat.esp_snaplines = cfg.espSnaplines;
    g_Cheat.esp_name = cfg.espName;
    g_Cheat.esp_health = cfg.espHealth;
    g_Cheat.esp_distance = cfg.espDistance;
    g_Cheat.esp_crosshair = cfg.espCrosshair;
    g_Cheat.esp_offscreen_360 = cfg.espOffscreen360;
    g_Cheat.max_esp_distance = cfg.espMaxDistance;
    g_Cheat.box_thickness = cfg.boxThickness;
    g_Cheat.line_thickness = cfg.lineThickness;
    g_Cheat.skeleton_thickness = cfg.skeletonThickness;
    g_Cheat.team_check = cfg.teamCheck;
    g_Cheat.aimbot_enabled = cfg.aimEnabled;
    g_Cheat.aim_silent = cfg.silentAim;
    g_Cheat.aim_360 = cfg.aim360;
    g_Cheat.aim_target_bone = cfg.aimBone;
    g_Cheat.aim_trigger_mode = cfg.aimActivation;
    g_Cheat.aim_snap_mode = cfg.aimSnapMode;
    g_Cheat.aim_skill_ratio = cfg.aimSkillRatio;
    g_Cheat.aim_fov = cfg.aimFov;
    g_Cheat.aim_smooth = cfg.aimSmooth;
    g_Cheat.draw_fov_circle = cfg.aimDrawFov;
    g_Cheat.ghillie_terrain_filter = cfg.ghillieSpaceData;

    // Update runtime telemetry exports
    g_TelemetryClientApp = (unsigned long long)s_CapturedEntityManager;
    g_TelemetryActiveCamera = (unsigned long long)s_ActiveCamera;
    g_TelemetryCameraFlag = s_ActiveCamera ? MemoryEngine::Read<uint16_t>(s_ActiveCamera + NeoXOffsets::CAMERA_FLAG) : 0;
    g_TelemetryMoveHits = s_MoveHookHits;
    g_TelemetryCreateHits = s_CreateHookHits;
    g_TelemetryCachedPositions = s_CachedEntityPositions.size();
    g_TelemetryEntitiesLoaded = 0; // populated below

    ImDrawList* draw = ImGui::GetBackgroundDrawList();

    Vector3 local_pos;
    int local_team = 0;
    Matrix4x4 vp_matrix{};
    float camera_yaw = 0.0f;
    bool is_firing = false;
    bool is_scoped = false;
    std::vector<RosPlayer> players;

    RosGameScanner::FetchState(players, local_pos, local_team, vp_matrix, camera_yaw, is_firing, is_scoped);
    g_TelemetryEntitiesLoaded = players.size();
    g_TelemetryVpValid = ProjectionEngine::IsValidViewProjMatrix(vp_matrix);

    // Periodic & On-Demand Debug State Dump (to Documents/debug.txt, USB Debugger & NSLog)
    static uint64_t s_LastDebugDumpFrame = 0;
    bool usb_connected = (s_UsbClientFd.load() > 0);
    uint64_t interval = usb_connected ? 30 : 300;
    if (g_TriggerDebugDump || (cfg.debugScanToFile && (s_FrameCount - s_LastDebugDumpFrame >= interval)) || (usb_connected && (s_FrameCount - s_LastDebugDumpFrame >= interval))) {
        s_LastDebugDumpFrame = s_FrameCount;
        bool is_manual = g_TriggerDebugDump;
        g_TriggerDebugDump = false;
        DumpGameplayDebugToFile(players, local_pos, local_team, vp_matrix, camera_yaw, screenSize, is_manual);
    }

    Vector2 center(screenSize.width * 0.5f, screenSize.height * 0.5f);
    float closest_aim_dist = g_Cheat.aim_360 ? 99999.0f : g_Cheat.aim_fov;
    const RosPlayer* aim_target = nullptr;
    Vector2 aim_target_screen{};

    // Precision Crosshair
    if (g_Cheat.esp_crosshair) {
        float ch_len = 8.0f;
        float ch_gap = 3.0f;
        ImU32 ch_col = IM_COL32(0, 255, 200, 220);
        draw->AddLine(ImVec2(center.x - ch_len - ch_gap, center.y), ImVec2(center.x - ch_gap, center.y), ch_col, 1.5f);
        draw->AddLine(ImVec2(center.x + ch_gap, center.y), ImVec2(center.x + ch_len + ch_gap, center.y), ch_col, 1.5f);
        draw->AddLine(ImVec2(center.x, center.y - ch_len - ch_gap), ImVec2(center.x, center.y - ch_gap), ch_col, 1.5f);
        draw->AddLine(ImVec2(center.x, center.y + ch_gap), ImVec2(center.x, center.y + ch_len + ch_gap), ch_col, 1.5f);
        draw->AddCircleFilled(ImVec2(center.x, center.y), 1.5f, IM_COL32(255, 50, 50, 255));
    }

    // Top-Right Radar Disc
    if (g_Cheat.esp_offscreen_360) {
        ImVec2 radar_center = ImVec2(screenSize.width - 55.0f, 55.0f);
        float radar_radius = 42.0f;
        draw->AddCircleFilled(radar_center, radar_radius, IM_COL32(12, 16, 24, 210), 32);
        draw->AddCircle(radar_center, radar_radius, IM_COL32(0, 200, 255, 180), 32, 1.5f);
        draw->AddLine(ImVec2(radar_center.x - radar_radius, radar_center.y), ImVec2(radar_center.x + radar_radius, radar_center.y), IM_COL32(0, 200, 255, 60), 1.0f);
        draw->AddLine(ImVec2(radar_center.x, radar_center.y - radar_radius), ImVec2(radar_center.x, radar_center.y + radar_radius), IM_COL32(0, 200, 255, 60), 1.0f);
        draw->AddCircleFilled(radar_center, 2.5f, IM_COL32(0, 255, 120, 255)); // Self
    }

    if (g_Cheat.esp_enabled) {
        for (const auto& player : players) {
            if (g_Cheat.team_check && player.team_id == local_team) continue;

            Vector2 head_screen, feet_screen;
            Vector3 head_3d = player.position + Vector3(0, 1.80f, 0);
            if (player.has_bones && player.bones[BONE_HEAD].Length() > 1.0f) {
                head_3d = player.bones[BONE_HEAD];
            }

            bool head_w2s = ProjectionEngine::WorldToScreen(head_3d, head_screen, vp_matrix, screenSize.width, screenSize.height, s_ActiveCamera);
            bool feet_w2s = ProjectionEngine::WorldToScreen(player.position, feet_screen, vp_matrix, screenSize.width, screenSize.height, s_ActiveCamera);

            if (&player == &players[0]) {
                g_TelemetryW2S_X = head_screen.x;
                g_TelemetryW2S_Y = head_screen.y;
            }

            if (!head_w2s && !feet_w2s) {
                if (g_Cheat.esp_offscreen_360) {
                    ImU32 off_col = player.is_bot ? IM_COL32(255, 180, 0, 220) : IM_COL32(255, 45, 45, 230);
                    RenderOffscreenRadarArrow(draw, player.position, local_pos, camera_yaw, center, 140.0f, off_col);
                }
                continue;
            }

            float box_h = fabsf(feet_screen.y - head_screen.y);
            if (box_h < 10.0f) box_h = 10.0f;
            float box_w = box_h * 0.52f;
            float box_x = head_screen.x - (box_w * 0.5f);
            float box_y = std::min(head_screen.y, feet_screen.y);

            ImU32 box_color = player.is_bot ? IM_COL32(255, 180, 0, 255) : IM_COL32(255, 40, 40, 255);

            if (g_Cheat.esp_box) {
                if (g_Cheat.esp_box_type == 0) {
                    draw->AddRect(ImVec2(box_x, box_y), ImVec2(box_x + box_w, box_y + box_h), box_color, 0.0f, 0, g_Cheat.box_thickness);
                } else if (g_Cheat.esp_box_type == 1) {
                    DrawCornerBox(draw, box_x, box_y, box_w, box_h, box_color, g_Cheat.box_thickness);
                } else {
                    draw->AddRectFilled(ImVec2(box_x, box_y), ImVec2(box_x + box_w, box_y + box_h), IM_COL32(255, 40, 40, 35));
                    draw->AddRect(ImVec2(box_x, box_y), ImVec2(box_x + box_w, box_y + box_h), box_color, 0.0f, 0, g_Cheat.box_thickness);
                }
            }

            if (g_Cheat.esp_snaplines) {
                ImVec2 snap_origin(center.x, screenSize.height);
                if (g_Cheat.snapline_pos == 1) snap_origin = ImVec2(center.x, center.y);
                if (g_Cheat.snapline_pos == 2) snap_origin = ImVec2(center.x, 0);
                draw->AddLine(snap_origin, ImVec2(head_screen.x, head_screen.y), box_color, g_Cheat.line_thickness);
            }

            if (g_Cheat.esp_health) {
                float hp_ratio = (float)player.health / (float)player.max_health;
                if (hp_ratio > 1.0f) hp_ratio = 1.0f;
                if (hp_ratio < 0.0f) hp_ratio = 0.0f;

                float bar_x = box_x - 6.0f;
                float bar_h = box_h * hp_ratio;
                draw->AddRectFilled(ImVec2(bar_x - 1, box_y - 1), ImVec2(bar_x + 3, box_y + box_h + 1), IM_COL32(0, 0, 0, 180));
                ImU32 hp_color = hp_ratio > 0.5f ? IM_COL32(0, 255, 120, 255) : (hp_ratio > 0.25f ? IM_COL32(255, 200, 0, 255) : IM_COL32(255, 30, 30, 255));
                draw->AddRectFilled(ImVec2(bar_x, box_y + (box_h - bar_h)), ImVec2(bar_x + 2, box_y + box_h), hp_color);
            }

            if (g_Cheat.esp_name || g_Cheat.esp_distance) {
                char info_buf[128];
                if (g_Cheat.esp_name && g_Cheat.esp_distance) {
                    snprintf(info_buf, sizeof(info_buf), "%s [%.0fm]", player.name, player.distance);
                } else if (g_Cheat.esp_name) {
                    snprintf(info_buf, sizeof(info_buf), "%s", player.name);
                } else {
                    snprintf(info_buf, sizeof(info_buf), "[%.0fm]", player.distance);
                }
                ImVec2 txt_sz = ImGui::CalcTextSize(info_buf);
                draw->AddText(ImVec2(head_screen.x - (txt_sz.x * 0.5f), box_y - 16.0f), IM_COL32(255, 255, 255, 255), info_buf);
            }

            if (g_Cheat.esp_skeleton && player.has_bones) {
                ImU32 skel_col = IM_COL32(0, 220, 255, 230);
                for (int i = 0; i < kSkeletonJointCount; ++i) {
                    Vector2 s1, s2;
                    if (ProjectionEngine::WorldToScreen(player.bones[kSkeletonJoints[i].from], s1, vp_matrix, screenSize.width, screenSize.height, s_ActiveCamera) &&
                        ProjectionEngine::WorldToScreen(player.bones[kSkeletonJoints[i].to], s2, vp_matrix, screenSize.width, screenSize.height, s_ActiveCamera)) {
                        draw->AddLine(ImVec2(s1.x, s1.y), ImVec2(s2.x, s2.y), skel_col, g_Cheat.skeleton_thickness);
                    }
                }
            }

            if (g_Cheat.aimbot_enabled) {
                Vector3 target_3d = head_3d;
                if (player.has_bones) {
                    if (g_Cheat.aim_target_bone == BONE_NECK && player.bones[BONE_NECK].Length() > 1.0f) target_3d = player.bones[BONE_NECK];
                    if (g_Cheat.aim_target_bone == BONE_CHEST && player.bones[BONE_CHEST].Length() > 1.0f) target_3d = player.bones[BONE_CHEST];
                    if (g_Cheat.aim_target_bone == BONE_PELVIS && player.bones[BONE_PELVIS].Length() > 1.0f) target_3d = player.bones[BONE_PELVIS];
                }

                Vector2 target_2d;
                if (ProjectionEngine::WorldToScreen(target_3d, target_2d, vp_matrix, screenSize.width, screenSize.height, s_ActiveCamera)) {
                    float dist_center = (target_2d - center).Length();
                    if (dist_center < closest_aim_dist) {
                        closest_aim_dist = dist_center;
                        aim_target = &player;
                        aim_target_screen = target_2d;
                    }
                }
            }
        }
    }

    if (g_Cheat.aimbot_enabled && g_Cheat.draw_fov_circle && !g_Cheat.aim_360) {
        draw->AddCircle(ImVec2(center.x, center.y), g_Cheat.aim_fov, IM_COL32(0, 200, 255, 140), 64, 1.2f);
    }

    if (aim_target && IsAimbotTriggerConditionMet(is_firing, is_scoped)) {
        draw->AddLine(ImVec2(center.x, center.y), ImVec2(aim_target_screen.x, aim_target_screen.y), IM_COL32(255, 50, 50, 200), 1.0f);
        Apply5050SkillBlendAimbot(aim_target_screen, center);
    }

    // =========================================================================
    // DRAGGABLE CIRCULAR FLOATING AVATAR LAUNCHER
    // =========================================================================
    {
        ImGui::SetNextWindowPos(ImVec2(g_Cheat.floating_btn_pos.x, g_Cheat.floating_btn_pos.y), ImGuiCond_FirstUseEver);
        ImGui::SetNextWindowSize(ImVec2(68, 68));
        ImGui::Begin("##FloatAvatarBtn", nullptr,
                     ImGuiWindowFlags_NoDecoration |
                     ImGuiWindowFlags_NoBackground |
                     ImGuiWindowFlags_NoSavedSettings);

        ImVec2 p = ImGui::GetCursorScreenPos();
        ImDrawList* fg_draw = ImGui::GetForegroundDrawList();
        float radius = 27.0f;
        ImVec2 circle_center = ImVec2(p.x + radius + 7.0f, p.y + radius + 7.0f);

        // Invisible button for dragging and tapping
        ImGui::InvisibleButton("##AvatarHit", ImVec2(60, 60));
        static bool s_IsDraggingAvatar = false;
        if (ImGui::IsItemActive()) {
            if (ImGui::IsMouseDragging(0, 2.0f)) {
                s_IsDraggingAvatar = true;
                ImVec2 delta = ImGui::GetIO().MouseDelta;
                g_Cheat.floating_btn_pos.x += delta.x;
                g_Cheat.floating_btn_pos.y += delta.y;
                ImGui::SetWindowPos("##FloatAvatarBtn", ImVec2(g_Cheat.floating_btn_pos.x, g_Cheat.floating_btn_pos.y));
            }
        }
        if (ImGui::IsItemDeactivated()) {
            if (!s_IsDraggingAvatar) {
                // Clean tap -> Toggle Menu
                SetMenuOpen(!g_Cheat.menu_open);
            }
            s_IsDraggingAvatar = false;
        }

        // Outer Glowing Accent Ring
        Menu::Config& cur_cfg = Menu::Cfg();
        ImVec4 acc_col = ImVec4(cur_cfg.accent[0], cur_cfg.accent[1], cur_cfg.accent[2], 1.0f);
        ImU32 ringCol = g_Cheat.menu_open ? IM_COL32(255, 60, 80, 255) : ImGui::ColorConvertFloat4ToU32(acc_col);
        fg_draw->AddCircle(circle_center, radius + 2.5f, ringCol, 36, 3.0f);
        fg_draw->AddCircle(circle_center, radius + 4.5f, ringCol & 0x40FFFFFF, 36, 1.5f);

        // Render Circular Avatar Image
        if (s_AvatarTexture) {
            fg_draw->AddImageRounded(
                (ImTextureID)(__bridge void*)s_AvatarTexture,
                ImVec2(circle_center.x - radius, circle_center.y - radius),
                ImVec2(circle_center.x + radius, circle_center.y + radius),
                ImVec2(0, 0), ImVec2(1, 1),
                IM_COL32(255, 255, 255, 255),
                radius
            );
        } else {
            fg_draw->AddCircleFilled(circle_center, radius, IM_COL32(20, 24, 32, 255), 36);
            fg_draw->AddText(ImVec2(circle_center.x - 14, circle_center.y - 7), IM_COL32(0, 240, 255, 255), "ROS");
        }

        // Active indicator badge
        fg_draw->AddCircleFilled(ImVec2(circle_center.x + radius - 4, circle_center.y + radius - 4), 5.5f, IM_COL32(0, 255, 120, 255));
        fg_draw->AddCircle(ImVec2(circle_center.x + radius - 4, circle_center.y + radius - 4), 5.5f, IM_COL32(0, 0, 0, 200), 16, 1.5f);

        ImGui::End();
    }

    // =========================================================================
    // ECLIPSE IMGUI DESIGN DASHBOARD (White Modern Theme)
    // =========================================================================
    char hud_title[96];
    std::snprintf(hud_title, sizeof(hud_title), "ECLIPSE · RosCambo | E:%llu", (unsigned long long)g_TelemetryEntitiesLoaded);
    Menu::RenderHud(hud_title);
    Menu::Render(&g_Cheat.menu_open);

    ImGui::Render();
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, encoder);
    [encoder endEncoding];
}

// =============================================================================
// NATIVE GESTURE RECOGNIZER & TOUCH EVENT HOOK
// =============================================================================
@interface RosGestureManager : NSObject
+ (void)attachToWindow:(UIWindow*)window;
@end

@implementation RosGestureManager
+ (void)attachToWindow:(UIWindow*)window {
    if (!window) return;
    static char kGestureAssociatedKey;
    if (objc_getAssociatedObject(window, &kGestureAssociatedKey)) return;
    objc_setAssociatedObject(window, &kGestureAssociatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UITapGestureRecognizer* tripleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTripleTap:)];
    tripleTap.numberOfTouchesRequired = 3;
    tripleTap.cancelsTouchesInView = NO;
    [window addGestureRecognizer:tripleTap];
}

+ (void)onTripleTap:(UITapGestureRecognizer*)sender {
    if (sender.state == UIGestureRecognizerStateEnded) {
        SetMenuOpen(!g_Cheat.menu_open);
    }
}
@end

@interface UIWindow (RosTouchHook)
@end

static __unsafe_unretained UITouch* s_ActiveImGuiTouch = nil;

@implementation UIWindow (RosTouchHook)
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method orig = class_getInstanceMethod(self, @selector(sendEvent:));
        Method swiz = class_getInstanceMethod(self, @selector(ros_sendEvent:));
        method_exchangeImplementations(orig, swiz);
    });
}

- (void)ros_sendEvent:(UIEvent *)event {
    [RosGestureManager attachToWindow:self];

    if (event.type == UIEventTypeTouches) {
        CGSize screenSize = [UIScreen mainScreen].bounds.size;
        if (screenSize.width < screenSize.height) {
            CGFloat t = screenSize.width;
            screenSize.width = screenSize.height;
            screenSize.height = t;
        }

        NSSet<UITouch*>* touches = [event allTouches];
        bool touchOverMenu = false;
        bool touchOverAvatar = false;

        for (UITouch* touch in touches) {
            // Obtain landscape-aligned coordinate
            CGPoint loc;
            UIViewController* rootVC = self.rootViewController;
            if (rootVC && rootVC.view) {
                loc = [touch locationInView:rootVC.view];
            } else {
                loc = [touch locationInView:self];
                CGSize curWinSz = [UIScreen mainScreen].bounds.size;
                if (curWinSz.width < curWinSz.height) {
                    CGFloat rawX = loc.x;
                    loc.x = loc.y;
                    loc.y = curWinSz.width - rawX;
                }
            }

            // Aim/Scope touch zones for mobile gameplay
            if (touch.phase == UITouchPhaseBegan || touch.phase == UITouchPhaseMoved) {
                g_TouchDelta = CGPointMake(loc.x - g_LastTouchPos.x, loc.y - g_LastTouchPos.y);
                g_LastTouchPos = loc;

                if (loc.x > screenSize.width * 0.70f && loc.y < screenSize.height * 0.50f) {
                    g_IsTouchingScope = true;
                }
                if ((loc.x > screenSize.width * 0.70f && loc.y > screenSize.height * 0.50f) ||
                    (loc.x < screenSize.width * 0.35f && loc.y > screenSize.height * 0.40f)) {
                    g_IsTouchingFire = true;
                }
            } else if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
                g_IsTouchingFire = false;
                g_IsTouchingScope = false;
                g_TouchDelta = (CGPoint){ 0.0f, 0.0f };
            }

            // Hit test circular floating avatar
            float dx = loc.x - (g_Cheat.floating_btn_pos.x + 34.0f);
            float dy = loc.y - (g_Cheat.floating_btn_pos.y + 34.0f);
            if ((dx * dx + dy * dy) <= (38.0f * 38.0f)) {
                touchOverAvatar = true;
            }

            // Hit test dashboard when open (size 560x370)
            if (g_Cheat.menu_open) {
                ImVec2 menuMin = ImVec2((screenSize.width - 560) * 0.5f, (screenSize.height - 370) * 0.5f);
                if (loc.x >= menuMin.x && loc.x <= menuMin.x + 560 &&
                    loc.y >= menuMin.y && loc.y <= menuMin.y + 370) {
                    touchOverMenu = true;
                }
            }

            // Forward touch coordinates to ImGui
            if (s_ImGuiReady) {
                ImGuiIO& io = ImGui::GetIO();
                if (touch.phase == UITouchPhaseBegan) {
                    s_ActiveImGuiTouch = touch;
                    io.MousePos = ImVec2(loc.x, loc.y);
                    io.MouseDown[0] = true;
                } else if (touch.phase == UITouchPhaseMoved) {
                    if (s_ActiveImGuiTouch == touch) {
                        io.MousePos = ImVec2(loc.x, loc.y);
                    }
                } else if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
                    if (s_ActiveImGuiTouch == touch) {
                        io.MousePos = ImVec2(loc.x, loc.y);
                        io.MouseDown[0] = false;
                        s_ActiveImGuiTouch = nil;
                    }
                }
            }
        }

        // SWALLOW TOUCHES ONLY IF TOUCHING IMGUI INTERACTIVE REGIONS
        // All other gameplay touches (movement, camera aim, weapon firing) pass cleanly to the game
        if (s_ImGuiReady && (touchOverMenu || touchOverAvatar)) {
            return;
        }
    }

    [self ros_sendEvent:event];
}
@end

// =============================================================================
// METAL PRESENT HOOK
// =============================================================================
@interface RosMetalHookHelper : NSObject
- (void)ros_presentDrawable:(id<MTLDrawable>)drawable;
- (void)ros_presentDrawable:(id<MTLDrawable>)drawable atTime:(CFTimeInterval)presentationTime;
- (void)ros_presentDrawable:(id<MTLDrawable>)drawable afterMinimumDuration:(CFTimeInterval)duration;
@end

@implementation RosMetalHookHelper
- (void)ros_presentDrawable:(id<MTLDrawable>)drawable {
    if (drawable && [drawable conformsToProtocol:@protocol(CAMetalDrawable)]) {
        id<CAMetalDrawable> metalDrawable = (id<CAMetalDrawable>)drawable;
        id<MTLCommandBuffer> cmdBuffer = (id<MTLCommandBuffer>)self;
        if (cmdBuffer.device) {
            InitializeMetalOverlay(cmdBuffer.device);
            RenderRosCamboOverlay(cmdBuffer, metalDrawable);
        }
    }
    [self ros_presentDrawable:drawable];
}

- (void)ros_presentDrawable:(id<MTLDrawable>)drawable atTime:(CFTimeInterval)presentationTime {
    if (drawable && [drawable conformsToProtocol:@protocol(CAMetalDrawable)]) {
        id<CAMetalDrawable> metalDrawable = (id<CAMetalDrawable>)drawable;
        id<MTLCommandBuffer> cmdBuffer = (id<MTLCommandBuffer>)self;
        if (cmdBuffer.device) {
            InitializeMetalOverlay(cmdBuffer.device);
            RenderRosCamboOverlay(cmdBuffer, metalDrawable);
        }
    }
    [self ros_presentDrawable:drawable atTime:presentationTime];
}

- (void)ros_presentDrawable:(id<MTLDrawable>)drawable afterMinimumDuration:(CFTimeInterval)duration {
    if (drawable && [drawable conformsToProtocol:@protocol(CAMetalDrawable)]) {
        id<CAMetalDrawable> metalDrawable = (id<CAMetalDrawable>)drawable;
        id<MTLCommandBuffer> cmdBuffer = (id<MTLCommandBuffer>)self;
        if (cmdBuffer.device) {
            InitializeMetalOverlay(cmdBuffer.device);
            RenderRosCamboOverlay(cmdBuffer, metalDrawable);
        }
    }
    // Uncap 30 FPS: If game passes duration > 0.0166667 (30 FPS cap), clamp to 0.0 so iOS display link runs at full 60/120 FPS
    CFTimeInterval uncap_duration = (duration > 0.0166667) ? 0.0 : duration;
    [self ros_presentDrawable:drawable afterMinimumDuration:uncap_duration];
}
@end

static void SwizzlePresentMethod(Class targetClass, SEL origSel, SEL swizSel, Method swizMethod) {
    if (!targetClass || !swizMethod) return;

    class_addMethod(targetClass,
                    swizSel,
                    method_getImplementation(swizMethod),
                    method_getTypeEncoding(swizMethod));

    Method mOrig = class_getInstanceMethod(targetClass, origSel);
    Method mSwiz = class_getInstanceMethod(targetClass, swizSel);
    if (mOrig && mSwiz) {
        method_exchangeImplementations(mOrig, mSwiz);
    }
}

static void InstallMetalPresentHooks() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cmdBufClass = NSClassFromString(@"_MTLCommandBuffer");
        if (!cmdBufClass) {
            id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
            if (dev) {
                id<MTLCommandQueue> q = [dev newCommandQueue];
                if (q) {
                    id<MTLCommandBuffer> cb = [q commandBuffer];
                    if (cb) {
                        Class c = [cb class];
                        while (c && c != [NSObject class]) {
                            if (class_getInstanceMethod(c, @selector(presentDrawable:))) {
                                cmdBufClass = c;
                                break;
                            }
                            c = [c superclass];
                        }
                    }
                }
            }
        }

        if (cmdBufClass) {
            Class helperClass = [RosMetalHookHelper class];
            Method m1 = class_getInstanceMethod(helperClass, @selector(ros_presentDrawable:));
            SwizzlePresentMethod(cmdBufClass, @selector(presentDrawable:), @selector(ros_presentDrawable:), m1);

            Method m2 = class_getInstanceMethod(helperClass, @selector(ros_presentDrawable:atTime:));
            SwizzlePresentMethod(cmdBufClass, @selector(presentDrawable:atTime:), @selector(ros_presentDrawable:atTime:), m2);

            Method m3 = class_getInstanceMethod(helperClass, @selector(ros_presentDrawable:afterMinimumDuration:));
            SwizzlePresentMethod(cmdBufClass, @selector(presentDrawable:afterMinimumDuration:), @selector(ros_presentDrawable:afterMinimumDuration:), m3);
        }
    });
}

__attribute__((constructor)) static void Entry() {
    InstallMetalPresentHooks();
    InstallVTableHooks();
    StartUsbDebugServer();
    NSLog(@"[RosCamboMod] Loaded with Metal Present Hook, VTable Entity Interceptor, USB Live Debugger (Port 1337).");
}

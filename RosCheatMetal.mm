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

#include "imgui.h"
#include "imgui_impl_metal.h"
#include "NeoXEngine.h"
#include "ImGuiTheme.h"
#include "AvatarData.h"

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
// VTABLE HOOK FOR CLIENTAPP / ENTITYMANAGER
// Verified VTable offset at base + 0x33D8DA8 (slot for getEntity)
// =============================================================================
typedef uintptr_t (*getEntity_t)(uintptr_t this_ptr, int id);
static getEntity_t s_OrigGetEntity = nullptr;
static uintptr_t s_CapturedEntityManager = 0;

static uintptr_t Hooked_getEntity(uintptr_t this_ptr, int id) {
    if (this_ptr > 0x100000000ULL) {
        s_CapturedEntityManager = this_ptr;
    }
    if (s_OrigGetEntity) {
        return s_OrigGetEntity(this_ptr, id);
    }
    return 0;
}

static void InstallVTableHook() {
    uintptr_t base = MemoryEngine::GetBaseAddress();
    if (!base) return;

    uintptr_t slot = base + 0x33D8DA8;
    uintptr_t current_fn = MemoryEngine::Read<uintptr_t>(slot);
    if (current_fn != 0 && current_fn != (uintptr_t)&Hooked_getEntity) {
        s_OrigGetEntity = (getEntity_t)current_fn;

        vm_address_t page = slot & ~0x3FFFULL;
        vm_protect(mach_task_self(), page, 0x4000, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);

        *(uintptr_t*)slot = (uintptr_t)&Hooked_getEntity;
        NSLog(@"[RosCamboMod] Installed VTable hook at 0x%lx -> %p", slot, &Hooked_getEntity);
    }
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
        out_players.clear();
        out_is_firing = g_IsTouchingFire;
        out_is_scoped = g_IsTouchingScope;

        uintptr_t base = MemoryEngine::GetBaseAddress();
        if (!base) return false;

        InstallVTableHook();

        uintptr_t client_app = s_CapturedEntityManager;
        if (!MemoryEngine::IsValidAddress(client_app)) {
            // Check engine singleton at base + 0x339D238 for camera
            uintptr_t eng_global = MemoryEngine::Read<uintptr_t>(base + 0x339D238);
            if (MemoryEngine::IsValidAddress(eng_global)) {
                uintptr_t p1 = MemoryEngine::Read<uintptr_t>(eng_global);
                if (MemoryEngine::IsValidAddress(p1)) {
                    uintptr_t cam = MemoryEngine::Read<uintptr_t>(p1 + 0x3E8);
                    if (MemoryEngine::IsValidAddress(cam)) {
                        out_vp = MemoryEngine::Read<Matrix4x4>(cam + 0x180);
                        out_camera_yaw = MemoryEngine::Read<float>(cam + 0x210);
                        float fov = MemoryEngine::Read<float>(cam + 0x218);
                        if (fov > 0.0f && fov < 55.0f) out_is_scoped = true;
                    }
                }
            }
            return false;
        }

        uintptr_t camera_obj = MemoryEngine::Read<uintptr_t>(client_app + 0x2A0);
        if (MemoryEngine::IsValidAddress(camera_obj)) {
            out_vp = MemoryEngine::Read<Matrix4x4>(camera_obj + 0x180);
            out_camera_yaw = MemoryEngine::Read<float>(camera_obj + 0x210);
            float fov = MemoryEngine::Read<float>(camera_obj + 0x218);
            if (fov > 0.0f && fov < 55.0f) {
                out_is_scoped = true;
            }
        } else {
            uintptr_t eng_global = MemoryEngine::Read<uintptr_t>(base + 0x339D238);
            if (MemoryEngine::IsValidAddress(eng_global)) {
                uintptr_t p1 = MemoryEngine::Read<uintptr_t>(eng_global);
                if (MemoryEngine::IsValidAddress(p1)) {
                    uintptr_t cam = MemoryEngine::Read<uintptr_t>(p1 + 0x3E8);
                    if (MemoryEngine::IsValidAddress(cam)) {
                        out_vp = MemoryEngine::Read<Matrix4x4>(cam + 0x180);
                        out_camera_yaw = MemoryEngine::Read<float>(cam + 0x210);
                        float fov = MemoryEngine::Read<float>(cam + 0x218);
                        if (fov > 0.0f && fov < 55.0f) out_is_scoped = true;
                    }
                }
            }
        }

        uintptr_t local_player = MemoryEngine::Read<uintptr_t>(client_app + 0xF98);
        if (MemoryEngine::IsValidAddress(local_player)) {
            out_local_pos = MemoryEngine::Read<Vector3>(local_player + 0x90);
            out_local_team = MemoryEngine::Read<int>(local_player + 0x1C4);
        }

        uintptr_t entity_buckets = MemoryEngine::Read<uintptr_t>(client_app + 0xF70);
        size_t bucket_count = MemoryEngine::Read<size_t>(client_app + 0xF78);
        if (MemoryEngine::IsValidAddress(entity_buckets) && bucket_count > 0 && bucket_count <= 4096) {
                for (size_t i = 0; i < bucket_count; ++i) {
                    uintptr_t node = MemoryEngine::Read<uintptr_t>(entity_buckets + (i * sizeof(uintptr_t)));
                    while (MemoryEngine::IsValidAddress(node)) {
                        uintptr_t entity = MemoryEngine::Read<uintptr_t>(node + 0x18);
                        if (MemoryEngine::IsValidAddress(entity) && entity != local_player) {
                            RosPlayer p{};
                            p.instance = entity;
                            p.position = MemoryEngine::Read<Vector3>(entity + 0x90);
                            p.health = MemoryEngine::Read<int>(entity + 0x1B8);
                            p.max_health = MemoryEngine::Read<int>(entity + 0x1BC);
                            p.team_id = MemoryEngine::Read<int>(entity + 0x1C4);
                            p.stance = MemoryEngine::Read<int>(entity + 0x1C8);
                            p.is_bot = MemoryEngine::Read<bool>(entity + 0x1D0);

                            if (p.max_health <= 0 || p.max_health > 500) p.max_health = 100;
                            if (p.health > 0 && p.health <= p.max_health) {
                                float dist = (p.position - out_local_pos).Length();
                                p.distance = dist;

                                if (dist <= g_Cheat.max_esp_distance) {
                                    uintptr_t name_ptr = MemoryEngine::Read<uintptr_t>(entity + 0x1E0);
                                    if (MemoryEngine::IsValidAddress(name_ptr)) {
                                        for (int c = 0; c < 63; ++c) {
                                            p.name[c] = MemoryEngine::Read<char>(name_ptr + c);
                                            if (p.name[c] == '\0') break;
                                        }
                                        p.name[63] = '\0';
                                    }
                                    if (p.name[0] == '\0') {
                                        snprintf(p.name, sizeof(p.name), "%s", p.is_bot ? "[BOT] Patrol" : "Survivor");
                                    }

                                    p.has_bones = false;
                                    uintptr_t skeleton = MemoryEngine::Read<uintptr_t>(entity + 0x228);
                                    if (MemoryEngine::IsValidAddress(skeleton)) {
                                        uintptr_t bone_array = MemoryEngine::Read<uintptr_t>(skeleton + 0x48);
                                        if (MemoryEngine::IsValidAddress(bone_array)) {
                                            for (int b = 0; b < BONE_COUNT; ++b) {
                                                p.bones[b] = MemoryEngine::Read<Vector3>(bone_array + (b * sizeof(Vector3)));
                                            }
                                            p.has_bones = true;
                                        }
                                    }
                                    out_players.push_back(p);
                                }
                            }
                        }
                        node = MemoryEngine::Read<uintptr_t>(node + 0x00);
                    }
                }
            }
        return true;
    }
};

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

    ApplyWizardIOSTheme();
    ImGui_ImplMetal_Init(device);
    LoadAvatarTexture(device);

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

    if (fabsf(final_correction.x) > 0.05f || fabsf(final_correction.y) > 0.05f) {
        uintptr_t base = MemoryEngine::GetBaseAddress();
        uintptr_t client_app = MemoryEngine::Read<uintptr_t>(base + 0x3B20000);
        uintptr_t camera_obj = MemoryEngine::Read<uintptr_t>(client_app + 0x2A0);
        if (MemoryEngine::IsValidAddress(camera_obj)) {
            float cur_pitch = MemoryEngine::Read<float>(camera_obj + 0x20C);
            float cur_yaw = MemoryEngine::Read<float>(camera_obj + 0x210);

            float sens = 0.0022f;
            cur_yaw += final_correction.x * sens;
            cur_pitch -= final_correction.y * sens;

            if (cur_pitch > 1.55f) cur_pitch = 1.55f;
            if (cur_pitch < -1.55f) cur_pitch = -1.55f;

            MemoryEngine::Write<float>(camera_obj + 0x20C, cur_pitch);
            MemoryEngine::Write<float>(camera_obj + 0x210, cur_yaw);
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

    ImDrawList* draw = ImGui::GetBackgroundDrawList();

    Vector3 local_pos;
    int local_team = 0;
    Matrix4x4 vp_matrix{};
    float camera_yaw = 0.0f;
    bool is_firing = false;
    bool is_scoped = false;
    std::vector<RosPlayer> players;

    RosGameScanner::FetchState(players, local_pos, local_team, vp_matrix, camera_yaw, is_firing, is_scoped);

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

            bool head_w2s = ProjectionEngine::WorldToScreen(head_3d, head_screen, vp_matrix, screenSize.width, screenSize.height);
            bool feet_w2s = ProjectionEngine::WorldToScreen(player.position, feet_screen, vp_matrix, screenSize.width, screenSize.height);

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
            float box_y = head_screen.y;

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
                    if (ProjectionEngine::WorldToScreen(player.bones[kSkeletonJoints[i].from], s1, vp_matrix, screenSize.width, screenSize.height) &&
                        ProjectionEngine::WorldToScreen(player.bones[kSkeletonJoints[i].to], s2, vp_matrix, screenSize.width, screenSize.height)) {
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
                if (ProjectionEngine::WorldToScreen(target_3d, target_2d, vp_matrix, screenSize.width, screenSize.height)) {
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

        // Outer Glowing Neon Ring
        ImU32 ringCol = g_Cheat.menu_open ? IM_COL32(255, 60, 80, 255) : IM_COL32(0, 240, 255, 240);
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
    // WIZARD IOS DASHBOARD UI LAYOUT (Clean Rules of Survival Content)
    // =========================================================================
    if (g_Cheat.menu_open) {
        ImGui::SetNextWindowSize(ImVec2(560, 370), ImGuiCond_FirstUseEver);
        ImGuiWindowFlags win_flags = ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoTitleBar;

        if (ImGui::Begin("##WizardDashboard", nullptr, win_flags)) {
            // -----------------------------------------------------------------
            // LEFT SIDEBAR (Mascot + Navigation + Close Action)
            // -----------------------------------------------------------------
            ImGui::BeginChild("Sidebar", ImVec2(140, 0), true);

            // Mascot Avatar & Header Title
            ImVec2 badge_p = ImGui::GetCursorScreenPos();
            ImDrawList* sdraw = ImGui::GetWindowDrawList();
            ImVec2 mascot_center = ImVec2(badge_p.x + 60, badge_p.y + 25);
            float mascot_r = 22.0f;

            if (s_AvatarTexture) {
                sdraw->AddImageRounded((ImTextureID)(__bridge void*)s_AvatarTexture,
                                       ImVec2(mascot_center.x - mascot_r, mascot_center.y - mascot_r),
                                       ImVec2(mascot_center.x + mascot_r, mascot_center.y + mascot_r),
                                       ImVec2(0, 0), ImVec2(1, 1),
                                       IM_COL32(255, 255, 255, 255), mascot_r);
                sdraw->AddCircle(mascot_center, mascot_r + 1.5f, IM_COL32(0, 240, 255, 240), 32, 2.0f);
            } else {
                sdraw->AddCircleFilled(mascot_center, mascot_r, IM_COL32(0, 160, 245, 200));
                sdraw->AddCircle(mascot_center, mascot_r + 1.5f, IM_COL32(255, 255, 255, 240), 32, 1.5f);
                sdraw->AddText(ImVec2(badge_p.x + 52, badge_p.y + 16), IM_COL32(255, 255, 255, 255), "ROS");
            }

            ImGui::Dummy(ImVec2(0, 50));

            // Clean Sidebar Header
            ImGui::SetCursorPosX(24);
            ImGui::TextColored(ImVec4(0.85f, 0.92f, 1.0f, 1.0f), "RosCambo");

            ImGui::Spacing();
            ImGui::Separator();
            ImGui::Spacing();

            auto DrawNavBtn = [](const char* label, int index, int& current) {
                bool is_active = (current == index);
                if (is_active) {
                    ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.00f, 0.60f, 0.90f, 0.85f));
                    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 1.0f, 1.0f, 1.0f));
                } else {
                    ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.06f, 0.10f, 0.16f, 0.60f));
                    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.70f, 0.75f, 0.85f, 1.0f));
                }
                if (ImGui::Button(label, ImVec2(118, 36))) {
                    current = index;
                }
                ImGui::PopStyleColor(2);
                ImGui::Spacing();
            };

            DrawNavBtn(" Visuals", 0, g_Cheat.active_nav_tab);
            DrawNavBtn(" Aim Menu", 1, g_Cheat.active_nav_tab);
            DrawNavBtn(" Settings", 2, g_Cheat.active_nav_tab);

            // Close button at bottom of sidebar
            ImGui::SetCursorPosY(ImGui::GetWindowHeight() - 65);
            ImGui::SetCursorPosX(12);
            ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.80f, 0.20f, 0.25f, 0.75f));
            ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.95f, 0.25f, 0.30f, 0.90f));
            ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 1.0f, 1.0f, 1.0f));
            if (ImGui::Button("Close Menu", ImVec2(118, 30))) {
                SetMenuOpen(false);
            }
            ImGui::PopStyleColor(3);

            ImGui::SetCursorPosY(ImGui::GetWindowHeight() - 25);
            ImGui::SetCursorPosX(45);
            ImGui::TextColored(ImVec4(0.5f, 0.55f, 0.65f, 0.8f), "v6.0");

            ImGui::EndChild();

            ImGui::SameLine();

            // -----------------------------------------------------------------
            // RIGHT CONTENT PANEL
            // -----------------------------------------------------------------
            ImGui::BeginChild("ContentArea", ImVec2(0, 0), false);

            // Top-Right [X] Close Button
            float content_avail = ImGui::GetContentRegionAvail().x;
            ImGui::SetCursorPosX(ImGui::GetCursorPosX() + content_avail - 32.0f);
            ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.12f, 0.16f, 0.22f, 0.8f));
            ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.80f, 0.20f, 0.25f, 0.85f));
            ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.95f, 0.95f, 1.0f, 1.0f));
            if (ImGui::Button("X##TopClose", ImVec2(28, 26))) {
                SetMenuOpen(false);
            }
            ImGui::PopStyleColor(3);

            ImGui::SetCursorPosY(10);

            if (g_Cheat.active_nav_tab == 0) {
                // VISUALS TAB
                auto DrawCapsuleTab = [](const char* label, int index, int& active) {
                    bool selected = (active == index);
                    if (selected) {
                        ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.00f, 0.62f, 0.92f, 1.0f));
                        ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 1.0f, 1.0f, 1.0f));
                    } else {
                        ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.08f, 0.13f, 0.20f, 0.60f));
                        ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(0.65f, 0.72f, 0.85f, 1.0f));
                    }
                    float btn_w = ImGui::CalcTextSize(label).x + 24.0f;
                    if (btn_w < 85.0f) btn_w = 85.0f;
                    if (ImGui::Button(label, ImVec2(btn_w, 28))) {
                        active = index;
                    }
                    ImGui::PopStyleColor(2);
                    ImGui::SameLine();
                };

                DrawCapsuleTab("Player ESP", 0, g_Cheat.active_visual_subtab);
                DrawCapsuleTab("Skeletons", 1, g_Cheat.active_visual_subtab);
                DrawCapsuleTab("Radar 360", 2, g_Cheat.active_visual_subtab);
                ImGui::NewLine();
                ImGui::Spacing();

                if (g_Cheat.active_visual_subtab == 0) {
                    // PLAYER ESP SUB-TAB
                    DrawSettingSwitch("Master ESP", &g_Cheat.esp_enabled);
                    DrawSettingSwitch("ESP Box", &g_Cheat.esp_box);
                    DrawSettingSwitch("Precision Crosshair", &g_Cheat.esp_crosshair);
                    DrawSettingSwitch("Health Bar Indicator", &g_Cheat.esp_health);
                    DrawSettingSwitch("Player Distance (m)", &g_Cheat.esp_distance);
                    DrawSettingSwitch("Player / Bot Names", &g_Cheat.esp_name);
                    DrawSettingSwitch("Snaplines", &g_Cheat.esp_snaplines);

                    DrawSettingSlider("Box Border Thickness", &g_Cheat.box_thickness, 0.5f, 5.0f, "%.1f px");
                    DrawSettingSlider("Line Transparency", &g_Cheat.line_transparency, 0.0f, 100.0f, "%.0f %%");
                    DrawSettingSlider("Line Thickness", &g_Cheat.line_thickness, 0.5f, 5.0f, "%.1f px");
                    DrawSettingSlider("Max Render Distance", &g_Cheat.max_esp_distance, 100.0f, 1000.0f, "%.0f m");
                } else if (g_Cheat.active_visual_subtab == 1) {
                    // SKELETON SUB-TAB
                    DrawSettingSwitch("Skeleton / Bone ESP", &g_Cheat.esp_skeleton);
                    DrawSettingSwitch("Team Filter (Ignore Allies)", &g_Cheat.team_check);
                    DrawSettingSlider("Bone Joint Thickness", &g_Cheat.skeleton_thickness, 0.5f, 4.0f, "%.1f px");

                    ImGui::Spacing();
                    ImGui::Separator();
                    ImGui::Spacing();
                    ImGui::TextColored(ImVec4(0.0f, 0.85f, 1.0f, 1.0f), "Rules of Survival Bone Hierarchy:");
                    ImGui::BulletText("Head, Neck, Chest, Pelvis");
                    ImGui::BulletText("Left/Right Shoulders, Elbows, Hands");
                    ImGui::BulletText("Left/Right Hips, Knees, Feet");
                } else {
                    // RADAR 360 SUB-TAB
                    DrawSettingSwitch("360 Offscreen Threat Arrows", &g_Cheat.esp_offscreen_360);
                    DrawSettingSwitch("Ghillie Terrain Z-Filter", &g_Cheat.ghillie_terrain_filter);
                    DrawSettingSwitch("Bot Hunter Tagging", &g_Cheat.esp_bot_indicator);
                    ImGui::Spacing();
                    ImGui::TextColored(ImVec4(0.7f, 0.75f, 0.85f, 1.0f), "Radar displays top-right mini-radar and red perimeter threat arrows.");
                }
            } else if (g_Cheat.active_nav_tab == 1) {
                // AIM MENU TAB
                DrawSettingSwitch("Master Aimbot", &g_Cheat.aimbot_enabled);
                DrawSettingSwitch("Silent Aim", &g_Cheat.aim_silent);
                DrawSettingSwitch("Aim 360 (Unrestricted FOV)", &g_Cheat.aim_360);
                DrawSettingSwitch("Draw FOV Circle", &g_Cheat.draw_fov_circle);

                ImGui::Spacing();
                ImGui::Separator();
                ImGui::Spacing();

                // Target Bone Selection
                const char* bone_names[] = { "Head", "Neck", "Chest", "Pelvis" };
                ImGui::TextUnformatted("Target Bone");
                ImGui::PushItemWidth(-1);
                ImGui::Combo("##TargetBoneCombo", &g_Cheat.aim_target_bone, bone_names, IM_ARRAYSIZE(bone_names));
                ImGui::PopItemWidth();
                ImGui::Spacing();

                // Trigger Conditions
                const char* trigger_modes[] = { "Always", "Scope Only", "Firing Only", "Scope & Firing" };
                ImGui::TextUnformatted("Trigger Condition");
                ImGui::PushItemWidth(-1);
                ImGui::Combo("##TriggerCombo", &g_Cheat.aim_trigger_mode, trigger_modes, IM_ARRAYSIZE(trigger_modes));
                ImGui::PopItemWidth();
                ImGui::Spacing();

                // Speed Mode Preset
                const char* snap_options[] = { "Custom Smooth", "Aim 50% (+50% Player Skill)", "Aim 100% (Instant Rage)" };
                ImGui::TextUnformatted("Aim Speed Mode");
                ImGui::PushItemWidth(-1);
                ImGui::Combo("##SnapCombo", &g_Cheat.aim_snap_mode, snap_options, IM_ARRAYSIZE(snap_options));
                ImGui::PopItemWidth();
                ImGui::Spacing();

                if (g_Cheat.aim_snap_mode == 1) {
                    ImGui::TextColored(ImVec4(0.2f, 1.0f, 0.4f, 1.0f), "%s", "[Skill Blend Mode] 50% Magnetism + 50% Touch Skill");
                    DrawSettingSlider("Assist Magnetism Ratio", &g_Cheat.aim_skill_ratio, 0.10f, 0.90f, "%.2f");
                }

                DrawSettingSlider("Aim FOV Radius", &g_Cheat.aim_fov, 30.0f, 400.0f, "%.0f px");
                DrawSettingSlider("Aim Smooth Factor", &g_Cheat.aim_smooth, 1.0f, 25.0f, "%.1f");
            } else {
                // SETTINGS TAB
                ImGui::TextColored(ImVec4(0.0f, 0.85f, 1.0f, 1.0f), "Rules of Survival - RosCambo Private Server");
                ImGui::Spacing();
                DrawSettingSwitch("Ghillie SpaceData Synced", &g_Cheat.ghillie_terrain_filter);

                ImGui::Spacing();
                ImGui::Separator();
                ImGui::Spacing();
                ImGui::Text("Active Target Bone: %s", (g_Cheat.aim_target_bone == 0 ? "Head" : (g_Cheat.aim_target_bone == 1 ? "Neck" : (g_Cheat.aim_target_bone == 2 ? "Chest" : "Pelvis"))));
                ImGui::Text("Active Trigger State: %s", IsAimbotTriggerConditionMet(is_firing, is_scoped) ? "ARMED" : "IDLE");
                ImGui::Text("Entities Loaded: %lu", players.size());
            }

            ImGui::EndChild();
        }
        ImGui::End();
    }

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
    [self ros_presentDrawable:drawable afterMinimumDuration:duration];
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
    InstallVTableHook();
    NSLog(@"[RosCamboMod] Loaded with Metal Present Hook, VTable Entity Interceptor, Circular Avatar & Gesture Support.");
}

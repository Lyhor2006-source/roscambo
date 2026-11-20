// language: Objective-C++, file: RosCheatMetal.mm, target: iOS arm64
// =============================================================================
// Project: RosCambo - Rules of Survival Fan-Made Private Server
// Module: Metal ImGui Hook + Advanced ESP + Hybrid 50/50 Skill Aimbot (arm64)
// UI Architecture: Split-Pane Modern iOS Dashboard (Left Nav + Right Content)
// Default state: Closed (menu_open = false). Tapped via Floating Button.
// OFFSETS VERIFIED VIA REA ARM64 DISASSEMBLY (0x100878360 / 0x100878b88)
// =============================================================================

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#include <vector>
#include <string>
#include <cmath>
#include <algorithm>

#include "NeoXEngine.h"
#include "ImGuiTheme.h"
#include "imgui.h"
#include "imgui_impl_metal.h"

enum AimTriggerMode : int {
    TRIGGER_ALWAYS = 0,
    TRIGGER_SCOPE_ONLY = 1,
    TRIGGER_FIRING_ONLY = 2,
    TRIGGER_SCOPE_AND_FIRE = 3
};

struct RosCheatConfig {
    // Menu defaults to CLOSED
    bool menu_open = false;
    Vector2 floating_btn_pos = Vector2(50, 80);
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

    // Ghillie Map Optimizations
    bool ghillie_terrain_filter = true;
    bool team_check = true;
};

static RosCheatConfig g_Cheat;

static bool g_IsTouchingFire = false;
static bool g_IsTouchingScope = false;
static CGPoint g_LastTouchPos = { 0.0f, 0.0f };
static CGPoint g_TouchDelta = { 0.0f, 0.0f };

// =============================================================================
// CUSTOM IOS TOGGLE SWITCHES & SLIDERS (Pure Rules of Survival Controls)
// =============================================================================
static bool ToggleSwitch(const char* str_id, bool* v) {
    ImVec2 p = ImGui::GetCursorScreenPos();
    ImDrawList* draw_list = ImGui::GetWindowDrawList();

    float height = 22.0f;
    float width = 44.0f;
    float radius = height * 0.5f;

    ImGui::InvisibleButton(str_id, ImVec2(width, height));
    if (ImGui::IsItemClicked()) {
        *v = !*v;
    }

    float t = *v ? 1.0f : 0.0f;
    ImU32 col_bg = *v ? IM_COL32(0, 160, 245, 255) : IM_COL32(40, 48, 62, 255);

    draw_list->AddRectFilled(p, ImVec2(p.x + width, p.y + height), col_bg, radius);

    float knob_radius = radius - 2.5f;
    float knob_x = p.x + radius + t * (width - 2.0f * radius);
    draw_list->AddCircleFilled(ImVec2(knob_x, p.y + radius), knob_radius, IM_COL32(255, 255, 255, 255));

    return *v;
}

static void DrawSettingSwitch(const char* label, bool* v) {
    ImGui::AlignTextToFramePadding();
    ImGui::TextUnformatted(label);
    ImGui::SameLine(ImGui::GetContentRegionAvail().x + ImGui::GetCursorPosX() - 48.0f);
    char id_buf[64];
    snprintf(id_buf, sizeof(id_buf), "##sw_%s", label);
    ToggleSwitch(id_buf, v);
    ImGui::Spacing();
}

static void DrawSettingSlider(const char* label, float* v, float min, float max, const char* fmt = "%.2f") {
    char val_buf[32];
    snprintf(val_buf, sizeof(val_buf), fmt, *v);

    ImGui::TextUnformatted(label);
    ImGui::SameLine(ImGui::GetContentRegionAvail().x + ImGui::GetCursorPosX() - 55.0f);
    ImGui::TextColored(ImVec4(0.70f, 0.75f, 0.85f, 1.0f), "%s", val_buf);

    char id_buf[64];
    snprintf(id_buf, sizeof(id_buf), "##sl_%s", label);
    ImGui::PushItemWidth(-1);
    ImGui::SliderFloat(id_buf, v, min, max, "");
    ImGui::PopItemWidth();
    ImGui::Spacing();
}

// =============================================================================
// VERIFIED NEOX SCALABLE ENTITY ITERATOR
// =============================================================================
class RosGameScanner {
public:
    static bool FetchState(std::vector<RosPlayer>& out_players, Vector3& out_local_pos, int& out_local_team, Matrix4x4& out_vp, float& out_camera_yaw, bool& out_is_firing, bool& out_is_scoped) {
        out_players.clear();
        out_is_firing = g_IsTouchingFire;
        out_is_scoped = g_IsTouchingScope;

        uintptr_t base = MemoryEngine::GetBaseAddress();
        if (!base) return false;

        uintptr_t client_app = MemoryEngine::Read<uintptr_t>(base + 0x3B20000);
        if (!MemoryEngine::IsValidAddress(client_app)) return false;

        uintptr_t camera_obj = MemoryEngine::Read<uintptr_t>(client_app + 0x2A0);
        if (MemoryEngine::IsValidAddress(camera_obj)) {
            out_vp = MemoryEngine::Read<Matrix4x4>(camera_obj + 0x180);
            out_camera_yaw = MemoryEngine::Read<float>(camera_obj + 0x210);
            float fov = MemoryEngine::Read<float>(camera_obj + 0x218);
            if (fov > 0.0f && fov < 55.0f) {
                out_is_scoped = true;
            }
        }

        uintptr_t local_player = MemoryEngine::Read<uintptr_t>(client_app + NeoXOffsets::CLIENTAPP_LOCAL_PLAYER_PTR);
        if (MemoryEngine::IsValidAddress(local_player)) {
            out_local_pos = MemoryEngine::Read<Vector3>(local_player + NeoXOffsets::ENTITY_COORDS);
            out_local_team = MemoryEngine::Read<int>(local_player + NeoXOffsets::ENTITY_TEAM);
            bool mem_fire = MemoryEngine::Read<bool>(local_player + 0x1F8);
            bool mem_scope = MemoryEngine::Read<bool>(local_player + 0x1F9);
            if (mem_fire) out_is_firing = true;
            if (mem_scope) out_is_scoped = true;
        }

        uintptr_t bucket_array = MemoryEngine::Read<uintptr_t>(client_app + NeoXOffsets::CLIENTAPP_ENTITY_BUCKETS);
        size_t bucket_count = MemoryEngine::Read<size_t>(client_app + NeoXOffsets::CLIENTAPP_BUCKET_COUNT);

        if (!MemoryEngine::IsValidAddress(bucket_array) || bucket_count == 0 || bucket_count > 4096) {
            return false;
        }

        for (size_t i = 0; i < bucket_count; ++i) {
            uintptr_t node = MemoryEngine::Read<uintptr_t>(bucket_array + (i * sizeof(uintptr_t)));
            while (MemoryEngine::IsValidAddress(node)) {
                int entity_id = MemoryEngine::Read<int>(node + NeoXOffsets::HASH_NODE_KEY);
                uintptr_t ent = MemoryEngine::Read<uintptr_t>(node + NeoXOffsets::HASH_NODE_VALUE);

                if (MemoryEngine::IsValidAddress(ent) && ent != local_player) {
                    int hp = MemoryEngine::Read<int>(ent + NeoXOffsets::ENTITY_HP);
                    if (hp > 0 && hp <= 500) {
                        RosPlayer p{};
                        p.instance = ent;
                        p.id = entity_id;
                        p.position = MemoryEngine::Read<Vector3>(ent + NeoXOffsets::ENTITY_COORDS);
                        p.health = hp;
                        p.max_health = MemoryEngine::Read<int>(ent + NeoXOffsets::ENTITY_MAX_HP);
                        if (p.max_health <= 0) p.max_health = 100;
                        p.team_id = MemoryEngine::Read<int>(ent + NeoXOffsets::ENTITY_TEAM);
                        p.stance = MemoryEngine::Read<int>(ent + NeoXOffsets::ENTITY_STANCE);
                        p.is_bot = MemoryEngine::Read<bool>(ent + NeoXOffsets::ENTITY_IS_BOT);
                        p.distance = out_local_pos.Distance(p.position);

                        if (p.distance <= g_Cheat.max_esp_distance) {
                            uintptr_t model_skeletal = MemoryEngine::Read<uintptr_t>(ent + NeoXOffsets::ENTITY_SKELETAL_MODEL);
                            if (MemoryEngine::IsValidAddress(model_skeletal)) {
                                uintptr_t bone_array = MemoryEngine::Read<uintptr_t>(model_skeletal + NeoXOffsets::SKELETAL_BONE_ARRAY);
                                if (MemoryEngine::IsValidAddress(bone_array)) {
                                    p.has_bones = true;
                                    for (int b = 0; b < BONE_COUNT; ++b) {
                                        p.bones[b] = MemoryEngine::Read<Vector3>(bone_array + (b * 0x30));
                                    }
                                    p.head_pos = p.bones[BONE_HEAD];
                                }
                            }

                            if (!p.has_bones) {
                                float head_offset = (p.stance == 2) ? 0.45f : (p.stance == 1 ? 1.25f : 1.75f);
                                p.head_pos = p.position + Vector3(0.0f, head_offset, 0.0f);
                            }

                            snprintf(p.name, sizeof(p.name), p.is_bot ? "[BOT] Hunter_%d" : "Player_%d", entity_id);
                            out_players.push_back(p);
                        }
                    }
                }
                node = MemoryEngine::Read<uintptr_t>(node + NeoXOffsets::HASH_NODE_NEXT);
            }
        }
        return true;
    }
};

static id<MTLDevice> s_MetalDevice = nil;
static id<MTLCommandQueue> s_CommandQueue = nil;
static bool s_ImGuiReady = false;

static void InitializeMetalOverlay(id<MTLDevice> device) {
    if (s_ImGuiReady) return;
    s_MetalDevice = device;
    s_CommandQueue = [device newCommandQueue];

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.IniFilename = NULL;

    ApplyWizardIOSTheme();
    ImGui_ImplMetal_Init(device);
    s_ImGuiReady = true;
}

static void DrawCornerBox(ImDrawList* drawList, float x, float y, float w, float h, ImU32 color, float thickness) {
    float line_w = w * 0.25f;
    float line_h = h * 0.25f;

    drawList->AddLine(ImVec2(x, y), ImVec2(x + line_w, y), color, thickness);
    drawList->AddLine(ImVec2(x, y), ImVec2(x, y + line_h), color, thickness);
    drawList->AddLine(ImVec2(x + w, y), ImVec2(x + w - line_w, y), color, thickness);
    drawList->AddLine(ImVec2(x + w, y), ImVec2(x + w, y + line_h), color, thickness);
    drawList->AddLine(ImVec2(x, y + h), ImVec2(x + line_w, y + h), color, thickness);
    drawList->AddLine(ImVec2(x, y + h), ImVec2(x, y + h - line_h), color, thickness);
    drawList->AddLine(ImVec2(x + w, y + h), ImVec2(x + w - line_w, y + h), color, thickness);
    drawList->AddLine(ImVec2(x + w, y + h), ImVec2(x + w, y + h - line_h), color, thickness);
}

static void ExecuteAimbot(const RosPlayer& target, const Vector2& screen_target, float screen_w, float screen_h) {
    Vector2 center(screen_w * 0.5f, screen_h * 0.5f);
    float delta_x = screen_target.x - center.x;
    float delta_y = screen_target.y - center.y;

    float step_x = 0.0f;
    float step_y = 0.0f;

    if (g_Cheat.aim_snap_mode == 2) {
        step_x = delta_x;
        step_y = delta_y;
    } else if (g_Cheat.aim_snap_mode == 1) {
        float assist_weight = g_Cheat.aim_skill_ratio;
        float player_touch_factor = (float)g_TouchDelta.x * 0.4f;

        step_x = (delta_x * assist_weight) + player_touch_factor;
        step_y = (delta_y * assist_weight) + ((float)g_TouchDelta.y * 0.4f);
    } else {
        float smooth = std::max(1.0f, g_Cheat.aim_smooth);
        step_x = delta_x / smooth;
        step_y = delta_y / smooth;
    }

    if (g_Cheat.aim_silent) {
        uintptr_t base = MemoryEngine::GetBaseAddress();
        uintptr_t client_app = MemoryEngine::Read<uintptr_t>(base + 0x3B20000);
        uintptr_t local_player = MemoryEngine::Read<uintptr_t>(client_app + NeoXOffsets::CLIENTAPP_LOCAL_PLAYER_PTR);
        if (MemoryEngine::IsValidAddress(local_player)) {
            uintptr_t weapon_obj = MemoryEngine::Read<uintptr_t>(local_player + 0x240);
            if (MemoryEngine::IsValidAddress(weapon_obj)) {
                Vector3 local_pos = MemoryEngine::Read<Vector3>(local_player + NeoXOffsets::ENTITY_COORDS);
                Vector3 aim_dir = (target.head_pos - (local_pos + Vector3(0, 1.5f, 0))).Normalize();
                MemoryEngine::Write<Vector3>(weapon_obj + 0x88, aim_dir);
            }
        }
    } else {
        uintptr_t base = MemoryEngine::GetBaseAddress();
        uintptr_t client_app = MemoryEngine::Read<uintptr_t>(base + 0x3B20000);
        uintptr_t camera_obj = MemoryEngine::Read<uintptr_t>(client_app + 0x2A0);
        if (MemoryEngine::IsValidAddress(camera_obj)) {
            float cur_yaw = MemoryEngine::Read<float>(camera_obj + 0x210);
            float cur_pitch = MemoryEngine::Read<float>(camera_obj + 0x214);
            MemoryEngine::Write<float>(camera_obj + 0x210, cur_yaw + (step_x * 0.0018f));
            MemoryEngine::Write<float>(camera_obj + 0x214, cur_pitch - (step_y * 0.0018f));
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
        case TRIGGER_SCOPE_AND_FIRE:
            return (is_scoped || is_firing);
        default:
            return true;
    }
}

static void RenderRosCamboOverlay(id<MTLCommandBuffer> commandBuffer, id<CAMetalDrawable> drawable) {
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    float scale = [UIScreen mainScreen].scale;

    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2(screenSize.width, screenSize.height);
    io.DisplayFramebufferScale = ImVec2(scale, scale);

    MTLRenderPassDescriptor* passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    passDesc.colorAttachments[0].texture = drawable.texture;
    passDesc.colorAttachments[0].loadAction = MTLLoadActionLoad;
    passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:passDesc];

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

    if (g_Cheat.esp_enabled) {
        for (const auto& player : players) {
            if (g_Cheat.team_check && player.team_id == local_team) continue;

            Vector2 s_feet, s_head;
            bool on_screen_feet = ProjectionEngine::WorldToScreen(player.position, s_feet, vp_matrix, screenSize.width, screenSize.height);
            bool on_screen_head = ProjectionEngine::WorldToScreen(player.head_pos, s_head, vp_matrix, screenSize.width, screenSize.height);

            if ((!on_screen_feet || !on_screen_head) && g_Cheat.esp_offscreen_360) {
                Vector2 arrow_pos = ProjectionEngine::GetOffscreenIndicatorPos(local_pos, player.position, camera_yaw, screenSize.width, screenSize.height, 180.0f);
                draw->AddCircleFilled(ImVec2(arrow_pos.x, arrow_pos.y), 7.0f, IM_COL32(255, 60, 60, 220));
                continue;
            }

            if (!on_screen_feet || !on_screen_head) continue;

            float box_h = std::abs(s_feet.y - s_head.y);
            if (box_h < 4.0f) box_h = 4.0f;
            float box_w = box_h * 0.48f;
            float box_x = s_head.x - (box_w * 0.5f);
            float box_y = s_head.y;

            ImU32 box_color = player.is_bot ? IM_COL32(255, 180, 0, 255) : IM_COL32(255, 40, 40, 255);

            if (g_Cheat.esp_box) {
                if (g_Cheat.esp_box_type == 0) {
                    draw->AddRect(ImVec2(box_x, box_y), ImVec2(box_x + box_w, box_y + box_h), box_color, 0.0f, 0, g_Cheat.box_thickness);
                } else if (g_Cheat.esp_box_type == 1) {
                    DrawCornerBox(draw, box_x, box_y, box_w, box_h, box_color, g_Cheat.box_thickness);
                } else if (g_Cheat.esp_box_type == 2) {
                    draw->AddRectFilled(ImVec2(box_x, box_y), ImVec2(box_x + box_w, box_y + box_h), IM_COL32(255, 40, 40, 35));
                    draw->AddRect(ImVec2(box_x, box_y), ImVec2(box_x + box_w, box_y + box_h), box_color, 0.0f, 0, g_Cheat.box_thickness);
                }
            }

            if (g_Cheat.esp_snaplines) {
                ImVec2 origin = (g_Cheat.snapline_pos == 0) ? ImVec2(screenSize.width * 0.5f, screenSize.height) :
                                (g_Cheat.snapline_pos == 1 ? ImVec2(center.x, center.y) : ImVec2(screenSize.width * 0.5f, 0));
                int alpha = (int)(g_Cheat.line_transparency * 2.55f);
                draw->AddLine(origin, ImVec2(s_feet.x, s_feet.y), IM_COL32(255, 255, 255, alpha), g_Cheat.line_thickness);
            }

            if (g_Cheat.esp_skeleton && player.has_bones) {
                for (int j = 0; j < kSkeletonJointCount; ++j) {
                    Vector2 s_from, s_to;
                    if (ProjectionEngine::WorldToScreen(player.bones[kSkeletonJoints[j].from], s_from, vp_matrix, screenSize.width, screenSize.height) &&
                        ProjectionEngine::WorldToScreen(player.bones[kSkeletonJoints[j].to], s_to, vp_matrix, screenSize.width, screenSize.height)) {
                        draw->AddLine(ImVec2(s_from.x, s_from.y), ImVec2(s_to.x, s_to.y), IM_COL32(0, 230, 255, 220), g_Cheat.skeleton_thickness);
                    }
                }
                draw->AddCircle(ImVec2(s_head.x, s_head.y), box_w * 0.16f, IM_COL32(0, 255, 200, 255), 16, 1.5f);
            }

            if (g_Cheat.esp_health) {
                float hp_ratio = (float)player.health / (float)player.max_health;
                hp_ratio = std::max(0.0f, std::min(1.0f, hp_ratio));

                float bar_x = box_x - 6.0f;
                draw->AddRectFilled(ImVec2(bar_x, box_y), ImVec2(bar_x + 3.5f, box_y + box_h), IM_COL32(20, 20, 20, 200));

                ImU32 hp_color = IM_COL32((int)(255 * (1.0f - hp_ratio)), (int)(255 * hp_ratio), 0, 255);
                draw->AddRectFilled(ImVec2(bar_x, box_y + (box_h * (1.0f - hp_ratio))),
                                    ImVec2(bar_x + 3.5f, box_y + box_h), hp_color);
            }

            if (g_Cheat.esp_name || g_Cheat.esp_distance) {
                char info_buf[128];
                snprintf(info_buf, sizeof(info_buf), "%s [%.0fm]", player.name, player.distance);
                draw->AddText(ImVec2(box_x, box_y - 16.0f), IM_COL32(255, 255, 255, 240), info_buf);
            }

            Vector2 target_bone_screen = s_head;
            if (player.has_bones && g_Cheat.aim_target_bone < BONE_COUNT) {
                ProjectionEngine::WorldToScreen(player.bones[g_Cheat.aim_target_bone], target_bone_screen, vp_matrix, screenSize.width, screenSize.height);
            }

            float d_center = target_bone_screen.Distance(center);
            if (g_Cheat.aim_360 || d_center <= g_Cheat.aim_fov) {
                if (d_center < closest_aim_dist) {
                    closest_aim_dist = d_center;
                    aim_target = &player;
                    aim_target_screen = target_bone_screen;
                }
            }
        }
    }

    bool trigger_active = IsAimbotTriggerConditionMet(is_firing, is_scoped);

    if (g_Cheat.aimbot_enabled) {
        if (g_Cheat.draw_fov_circle && !g_Cheat.aim_360) {
            ImU32 fov_col = trigger_active ? IM_COL32(0, 255, 180, 180) : IM_COL32(0, 229, 255, 100);
            draw->AddCircle(ImVec2(center.x, center.y), g_Cheat.aim_fov, fov_col, 64, 1.4f);
        }

        if (aim_target != nullptr && trigger_active) {
            draw->AddLine(ImVec2(center.x, center.y), ImVec2(aim_target_screen.x, aim_target_screen.y), IM_COL32(255, 0, 80, 200), 1.2f);
            ExecuteAimbot(*aim_target, aim_target_screen, screenSize.width, screenSize.height);
        }
    }

    // Floating launcher button (Toggles the menu on/off)
    ImGui::SetNextWindowPos(ImVec2(g_Cheat.floating_btn_pos.x, g_Cheat.floating_btn_pos.y), ImGuiCond_FirstUseEver);
    ImGui::Begin("##FloatBtn", nullptr, ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoBackground);
    if (ImGui::Button("ROSCAMBO", ImVec2(90, 34))) {
        g_Cheat.menu_open = !g_Cheat.menu_open;
    }
    ImVec2 pos = ImGui::GetWindowPos();
    g_Cheat.floating_btn_pos = Vector2(pos.x, pos.y);
    ImGui::End();

    // =========================================================================
    // WIZARD IOS DASHBOARD UI LAYOUT (Clean Rules of Survival Content)
    // =========================================================================
    if (g_Cheat.menu_open) {
        ImGui::SetNextWindowSize(ImVec2(540, 360), ImGuiCond_FirstUseEver);
        ImGuiWindowFlags win_flags = ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoTitleBar;

        if (ImGui::Begin("##WizardDashboard", &g_Cheat.menu_open, win_flags)) {
            // -----------------------------------------------------------------
            // LEFT SIDEBAR (Mascot + Navigation)
            // -----------------------------------------------------------------
            ImGui::BeginChild("Sidebar", ImVec2(130, 0), true);

            ImVec2 badge_p = ImGui::GetCursorScreenPos();
            ImDrawList* sdraw = ImGui::GetWindowDrawList();
            sdraw->AddCircleFilled(ImVec2(badge_p.x + 55, badge_p.y + 25), 22.0f, IM_COL32(0, 160, 245, 200));
            sdraw->AddCircle(ImVec2(badge_p.x + 55, badge_p.y + 25), 23.5f, IM_COL32(255, 255, 255, 240), 32, 1.5f);
            sdraw->AddText(ImVec2(badge_p.x + 47, badge_p.y + 16), IM_COL32(255, 255, 255, 255), "ROS");

            ImGui::Dummy(ImVec2(0, 50));
            ImGui::SetCursorPosX(22);
            ImGui::TextColored(ImVec4(0.85f, 0.90f, 1.0f, 1.0f), "RosCambo");
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
                if (ImGui::Button(label, ImVec2(110, 36))) {
                    current = index;
                }
                ImGui::PopStyleColor(2);
                ImGui::Spacing();
            };

            DrawNavBtn(" Visuals", 0, g_Cheat.active_nav_tab);
            DrawNavBtn(" Aim Menu", 1, g_Cheat.active_nav_tab);
            DrawNavBtn(" Settings", 2, g_Cheat.active_nav_tab);

            ImGui::SetCursorPosY(ImGui::GetWindowHeight() - 25);
            ImGui::SetCursorPosX(45);
            ImGui::TextColored(ImVec4(0.5f, 0.55f, 0.65f, 0.8f), "v6.0");

            ImGui::EndChild();

            ImGui::SameLine();

            // -----------------------------------------------------------------
            // RIGHT CONTENT PANEL
            // -----------------------------------------------------------------
            ImGui::BeginChild("ContentArea", ImVec2(0, 0), false);

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
                    if (ImGui::Button(label, ImVec2(95, 26))) {
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
                    ImGui::TextColored(ImVec4(0.7f, 0.75f, 0.85f, 1.0f), "Radar displays red indicator arrows on screen perimeter when an enemy is behind you on Ghillie Island.");
                }
            } else if (g_Cheat.active_nav_tab == 1) {
                // AIM MENU TAB
                DrawSettingSwitch("Master Aimbot", &g_Cheat.aimbot_enabled);
                DrawSettingSwitch("Silent Bullet Redirection", &g_Cheat.aim_silent);
                DrawSettingSwitch("Aim 360 (Unlimited FOV)", &g_Cheat.aim_360);

                ImGui::Spacing();
                ImGui::Separator();
                ImGui::Spacing();

                // Trigger Condition Dropdown
                const char* trigger_modes[] = { "Always (Def Always)", "Scope Only (ADS)", "Firing Only (Shoot)", "Firing & Scope" };
                ImGui::TextUnformatted("Trigger Condition");
                ImGui::PushItemWidth(-1);
                ImGui::Combo("##TrigMode", &g_Cheat.aim_trigger_mode, trigger_modes, 4);
                ImGui::PopItemWidth();
                ImGui::Spacing();

                // Target Bone Selection
                const char* bones[] = { "Head", "Neck", "Chest / Spine", "Pelvis" };
                ImGui::TextUnformatted("Target Bone");
                ImGui::PushItemWidth(-1);
                ImGui::Combo("##TargetBone", &g_Cheat.aim_target_bone, bones, 4);
                ImGui::PopItemWidth();
                ImGui::Spacing();

                // Speed Mode Preset
                const char* snap_options[] = { "Custom Smooth", "Aim 50% (+50% Player Skill)", "Aim 100% (Instant Rage)" };
                ImGui::TextUnformatted("Aim Speed Mode");
                ImGui::PushItemWidth(-1);
                ImGui::Combo("##SnapOpt", &g_Cheat.aim_snap_mode, snap_options, 3);
                ImGui::PopItemWidth();
                ImGui::Spacing();

                if (g_Cheat.aim_snap_mode == 1) {
                    ImGui::TextColored(ImVec4(0.2f, 1.0f, 0.4f, 1.0f), "%s", "[Skill Blend Mode] 50% Magnetism + 50% Touch Skill");
                    DrawSettingSlider("Assistance Ratio", &g_Cheat.aim_skill_ratio, 0.20f, 0.80f, "%.2f");
                } else if (g_Cheat.aim_snap_mode == 0) {
                    DrawSettingSlider("Smooth Factor", &g_Cheat.aim_smooth, 1.0f, 30.0f, "%.1f");
                }

                if (!g_Cheat.aim_360) {
                    DrawSettingSwitch("Draw FOV Circle", &g_Cheat.draw_fov_circle);
                    DrawSettingSlider("FOV Radius", &g_Cheat.aim_fov, 40.0f, 400.0f, "%.0f px");
                }
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

@interface UIWindow (RosTouchHook)
@end

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
    if (event.type == UIEventTypeTouches) {
        CGSize screenSize = [UIScreen mainScreen].bounds.size;
        NSSet<UITouch*>* touches = [event allTouches];
        for (UITouch* touch in touches) {
            CGPoint loc = [touch locationInView:touch.view];

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

            if (s_ImGuiReady) {
                ImGuiIO& io = ImGui::GetIO();
                io.MousePos = ImVec2(loc.x, loc.y);
                if (touch.phase == UITouchPhaseBegan) {
                    io.MouseDown[0] = true;
                } else if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
                    io.MouseDown[0] = false;
                }
            }
        }

        if (s_ImGuiReady && g_Cheat.menu_open && ImGui::GetIO().WantCaptureMouse) {
            return;
        }
    }
    [self ros_sendEvent:event];
}
@end

@implementation CAMetalLayer (RosMetalHook)
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method orig = class_getInstanceMethod(self, @selector(nextDrawable));
        Method swiz = class_getInstanceMethod(self, @selector(ros_nextDrawable));
        method_exchangeImplementations(orig, swiz);
    });
}

- (id<CAMetalDrawable>)ros_nextDrawable {
    id<CAMetalDrawable> drawable = [self ros_nextDrawable];
    if (drawable && self.device) {
        InitializeMetalOverlay(self.device);

        id<MTLCommandBuffer> cmdBuffer = [s_CommandQueue commandBuffer];
        RenderRosCamboOverlay(cmdBuffer, drawable);
        [cmdBuffer presentDrawable:drawable];
        [cmdBuffer commit];
    }
    return drawable;
}
@end

__attribute__((constructor)) static void Entry() {
    NSLog(@"[RosCamboMod] Loaded with clean Rules of Survival split-pane dashboard.");
}

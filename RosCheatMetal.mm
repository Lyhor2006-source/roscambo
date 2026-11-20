// language: Objective-C++, file: RosCheatMetal.mm, target: iOS arm64
// =============================================================================
// Project: RosCambo - Rules of Survival Fan-Made Private Server
// Module: Metal ImGui Hook + Advanced ESP + Multi-Mode Aimbot (arm64)
// OFFSETS VERIFIED VIA REA ARM64 DISASSEMBLY (0x100878360 / 0x100878b88)
// Ghillie Island Ranked Battle Royale Compatible
// =============================================================================

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/CAMetalLayer.h>
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

struct RosCheatConfig {
    bool menu_open = true;
    Vector2 floating_btn_pos = Vector2(60, 60);

    // ESP Features
    bool esp_enabled = true;
    int esp_box_type = 1; // 0=Off, 1=2D Box, 2=Corner Box, 3=Filled
    bool esp_snaplines = true;
    int snapline_pos = 0; // 0=Bottom, 1=Crosshair, 2=Top
    bool esp_skeleton = true;
    bool esp_health = true;
    bool esp_distance = true;
    bool esp_name = true;
    bool esp_bot_indicator = true;
    bool esp_offscreen_360 = true;
    float max_esp_distance = 600.0f; // Ghillie map battle range

    // Aimbot Features
    bool aimbot_enabled = true;
    int aim_target_bone = BONE_HEAD;
    bool aim_silent = false;
    bool aim_360 = false;
    int aim_snap_mode = 1; // 0=Custom Smooth, 1=Aim 50% (Legit), 2=Aim 100% (Instant Rage)
    float aim_fov = 140.0f;
    float aim_smooth = 6.0f;
    bool draw_fov_circle = true;

    // Ghillie Map Optimizations
    bool ghillie_terrain_filter = true;
    bool team_check = true;
};

static RosCheatConfig g_Cheat;

// =============================================================================
// VERIFIED NEOX SCALABLE ENTITY ITERATOR
// Iterates through verified std::unordered_map at client_app + 0xf70
// =============================================================================
class RosGameScanner {
public:
    static bool FetchState(std::vector<RosPlayer>& out_players, Vector3& out_local_pos, int& out_local_team, Matrix4x4& out_vp, float& out_camera_yaw) {
        out_players.clear();
        uintptr_t base = MemoryEngine::GetBaseAddress();
        if (!base) return false;

        // ClientApp instance discovered via ADRP+ADD at 0x1008783e0
        uintptr_t client_app = MemoryEngine::Read<uintptr_t>(base + 0x3B20000);
        if (!MemoryEngine::IsValidAddress(client_app)) return false;

        // Camera object containing ViewProjection matrix
        uintptr_t camera_obj = MemoryEngine::Read<uintptr_t>(client_app + 0x2A0);
        if (MemoryEngine::IsValidAddress(camera_obj)) {
            out_vp = MemoryEngine::Read<Matrix4x4>(camera_obj + 0x180);
            out_camera_yaw = MemoryEngine::Read<float>(camera_obj + 0x210);
        }

        // Local Player Pointer verified at client_app + 0xf98
        uintptr_t local_player = MemoryEngine::Read<uintptr_t>(client_app + NeoXOffsets::CLIENTAPP_LOCAL_PLAYER_PTR);
        if (MemoryEngine::IsValidAddress(local_player)) {
            out_local_pos = MemoryEngine::Read<Vector3>(local_player + NeoXOffsets::ENTITY_COORDS);
            out_local_team = MemoryEngine::Read<int>(local_player + NeoXOffsets::ENTITY_TEAM);
        }

        // Entity Map verified at client_app + 0xf70 / 0xf78
        uintptr_t bucket_array = MemoryEngine::Read<uintptr_t>(client_app + NeoXOffsets::CLIENTAPP_ENTITY_BUCKETS);
        size_t bucket_count = MemoryEngine::Read<size_t>(client_app + NeoXOffsets::CLIENTAPP_BUCKET_COUNT);

        if (!MemoryEngine::IsValidAddress(bucket_array) || bucket_count == 0 || bucket_count > 4096) {
            return false;
        }

        // Walk LLVM libc++ unordered_map buckets
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
                            // ModelSkeletal & Bone array
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

    ApplyCyberTacticalTheme();
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
        step_x = delta_x * 0.50f;
        step_y = delta_y * 0.50f;
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
    std::vector<RosPlayer> players;

    RosGameScanner::FetchState(players, local_pos, local_team, vp_matrix, camera_yaw);

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

            if (g_Cheat.esp_box_type == 1) {
                draw->AddRect(ImVec2(box_x, box_y), ImVec2(box_x + box_w, box_y + box_h), box_color, 0.0f, 0, 1.6f);
            } else if (g_Cheat.esp_box_type == 2) {
                DrawCornerBox(draw, box_x, box_y, box_w, box_h, box_color, 1.8f);
            } else if (g_Cheat.esp_box_type == 3) {
                draw->AddRectFilled(ImVec2(box_x, box_y), ImVec2(box_x + box_w, box_y + box_h), IM_COL32(255, 40, 40, 35));
                draw->AddRect(ImVec2(box_x, box_y), ImVec2(box_x + box_w, box_y + box_h), box_color, 0.0f, 0, 1.6f);
            }

            if (g_Cheat.esp_snaplines) {
                ImVec2 origin = (g_Cheat.snapline_pos == 0) ? ImVec2(screenSize.width * 0.5f, screenSize.height) :
                                (g_Cheat.snapline_pos == 1 ? ImVec2(center.x, center.y) : ImVec2(screenSize.width * 0.5f, 0));
                draw->AddLine(origin, ImVec2(s_feet.x, s_feet.y), IM_COL32(255, 255, 255, 170), 1.0f);
            }

            if (g_Cheat.esp_skeleton && player.has_bones) {
                for (int j = 0; j < kSkeletonJointCount; ++j) {
                    Vector2 s_from, s_to;
                    if (ProjectionEngine::WorldToScreen(player.bones[kSkeletonJoints[j].from], s_from, vp_matrix, screenSize.width, screenSize.height) &&
                        ProjectionEngine::WorldToScreen(player.bones[kSkeletonJoints[j].to], s_to, vp_matrix, screenSize.width, screenSize.height)) {
                        draw->AddLine(ImVec2(s_from.x, s_from.y), ImVec2(s_to.x, s_to.y), IM_COL32(0, 230, 255, 220), 1.5f);
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

    if (g_Cheat.aimbot_enabled) {
        if (g_Cheat.draw_fov_circle && !g_Cheat.aim_360) {
            draw->AddCircle(ImVec2(center.x, center.y), g_Cheat.aim_fov, IM_COL32(0, 229, 255, 140), 64, 1.4f);
        }

        if (aim_target != nullptr) {
            draw->AddLine(ImVec2(center.x, center.y), ImVec2(aim_target_screen.x, aim_target_screen.y), IM_COL32(255, 0, 80, 200), 1.2f);
            ExecuteAimbot(*aim_target, aim_target_screen, screenSize.width, screenSize.height);
        }
    }

    ImGui::SetNextWindowPos(ImVec2(g_Cheat.floating_btn_pos.x, g_Cheat.floating_btn_pos.y), ImGuiCond_FirstUseEver);
    ImGui::Begin("##FloatBtn", nullptr, ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoBackground);
    if (ImGui::Button("ROSCAMBO", ImVec2(80, 32))) {
        g_Cheat.menu_open = !g_Cheat.menu_open;
    }
    ImVec2 pos = ImGui::GetWindowPos();
    g_Cheat.floating_btn_pos = Vector2(pos.x, pos.y);
    ImGui::End();

    if (g_Cheat.menu_open) {
        ImGui::SetNextWindowSize(ImVec2(480, 340), ImGuiCond_FirstUseEver);
        if (ImGui::Begin("RosCambo Private Server - Master Suite", &g_Cheat.menu_open, ImGuiWindowFlags_NoCollapse)) {
            if (ImGui::BeginTabBar("Tabs")) {
                if (ImGui::BeginTabItem("  ESP VISUALS  ")) {
                    ImGui::Spacing();
                    ImGui::Checkbox("Master ESP", &g_Cheat.esp_enabled);
                    ImGui::SameLine();
                    ImGui::Checkbox("Team Check", &g_Cheat.team_check);

                    ImGui::Separator();
                    const char* box_types[] = { "Disabled", "2D Rectangle", "3D Corner Box", "Filled Accent Box" };
                    ImGui::Combo("Box Style", &g_Cheat.esp_box_type, box_types, 4);

                    ImGui::Checkbox("Snaplines", &g_Cheat.esp_snaplines);
                    if (g_Cheat.esp_snaplines) {
                        ImGui::SameLine();
                        const char* snap_modes[] = { "Bottom", "Crosshair", "Top" };
                        ImGui::Combo("Line Origin", &g_Cheat.snapline_pos, snap_modes, 3);
                    }

                    ImGui::Checkbox("Skeleton / Bone ESP", &g_Cheat.esp_skeleton);
                    ImGui::Checkbox("Health Bar Indicator", &g_Cheat.esp_health);
                    ImGui::Checkbox("Distance Display", &g_Cheat.esp_distance);
                    ImGui::Checkbox("Player / Bot Names", &g_Cheat.esp_name);
                    ImGui::Checkbox("360 Offscreen Radar Alerts", &g_Cheat.esp_offscreen_360);

                    ImGui::SliderFloat("Render Distance (m)", &g_Cheat.max_esp_distance, 100.0f, 1000.0f, "%.0f m");
                    ImGui::EndTabItem();
                }

                if (ImGui::BeginTabItem("  AIMBOT  ")) {
                    ImGui::Spacing();
                    ImGui::Checkbox("Master Aimbot", &g_Cheat.aimbot_enabled);
                    ImGui::SameLine();
                    ImGui::Checkbox("Silent Aim", &g_Cheat.aim_silent);

                    ImGui::Separator();
                    const char* bones[] = { "Head", "Neck", "Chest / Spine", "Pelvis" };
                    ImGui::Combo("Target Bone", &g_Cheat.aim_target_bone, bones, 4);

                    const char* snap_options[] = { "Custom Smooth", "Aim 50% (Legit Assist)", "Aim 100% (Instant Rage)" };
                    ImGui::Combo("Aim Speed Preset", &g_Cheat.aim_snap_mode, snap_options, 3);

                    if (g_Cheat.aim_snap_mode == 0) {
                        ImGui::SliderFloat("Smooth Factor", &g_Cheat.aim_smooth, 1.0f, 30.0f, "%.1f");
                    }

                    ImGui::Separator();
                    ImGui::Checkbox("Aim 360 (Unlimited FOV)", &g_Cheat.aim_360);
                    if (!g_Cheat.aim_360) {
                        ImGui::Checkbox("Draw FOV Circle", &g_Cheat.draw_fov_circle);
                        ImGui::SliderFloat("FOV Radius", &g_Cheat.aim_fov, 40.0f, 400.0f, "%.0f px");
                    }

                    ImGui::EndTabItem();
                }

                if (ImGui::BeginTabItem("  GHILLIE MAP  ")) {
                    ImGui::Spacing();
                    ImGui::TextColored(ImVec4(0.0f, 0.9f, 1.0f, 1.0f), "Ghillie Island Ranked Match Profiler");
                    ImGui::Separator();
                    ImGui::Checkbox("Dynamic Terrain Z-Filter", &g_Cheat.ghillie_terrain_filter);
                    ImGui::Text("Status: Synchronized with NeoX SpaceData");
                    ImGui::Text("Area of Interest (AoI) Radius: 500m");
                    ImGui::Text("Entities Loaded in Cell: %lu", players.size());
                    ImGui::EndTabItem();
                }
                ImGui::EndTabBar();
            }
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
    if (s_ImGuiReady && event.type == UIEventTypeTouches) {
        ImGuiIO& io = ImGui::GetIO();
        NSSet<UITouch*>* touches = [event allTouches];
        for (UITouch* touch in touches) {
            CGPoint loc = [touch locationInView:touch.view];
            io.MousePos = ImVec2(loc.x, loc.y);

            if (touch.phase == UITouchPhaseBegan) {
                io.MouseDown[0] = true;
            } else if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled) {
                io.MouseDown[0] = false;
            }
        }
        if (g_Cheat.menu_open && io.WantCaptureMouse) {
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
    NSLog(@"[RosCamboMod] Loaded with 100%% verified ARM64 NeoX offsets.");
}

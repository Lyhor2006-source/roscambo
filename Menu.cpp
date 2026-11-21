#include "Menu.h"
#include <cstdio>
#include <cmath>
#include <algorithm>
#include <cstring>

// Global Telemetry Definitions
void*               g_MenuAvatarTexture = nullptr;
unsigned long long  g_TelemetryClientApp = 0;
unsigned long long  g_TelemetryActiveCamera = 0;
unsigned int        g_TelemetryCameraFlag = 0;
bool                g_TelemetryVpValid = false;
float               g_TelemetryW2S_X = 0.0f;
float               g_TelemetryW2S_Y = 0.0f;
unsigned long long  g_TelemetryMoveHits = 0;
unsigned long long  g_TelemetryCreateHits = 0;
unsigned long long  g_TelemetryCachedPositions = 0;
unsigned long long  g_TelemetryEntitiesLoaded = 0;
bool                g_TriggerDebugDump = false;

namespace Menu
{
    static float g_scale = 1.0f;
    static int   g_active_tab = 0;

    Config& Cfg()
    {
        static Config cfg;
        return cfg;
    }

    void ApplyRyomenVipTheme(float scale)
    {
        g_scale = scale;
        ImGuiStyle& style = ImGui::GetStyle();

        style.WindowRounding    = 12.0f * scale;
        style.ChildRounding     = 10.0f * scale;
        style.FrameRounding     = 8.0f * scale;
        style.PopupRounding     = 10.0f * scale;
        style.ScrollbarRounding = 8.0f * scale;
        style.GrabRounding      = 6.0f * scale;
        style.TabRounding       = 8.0f * scale;

        style.WindowBorderSize  = 1.0f;
        style.ChildBorderSize   = 1.0f;
        style.PopupBorderSize   = 1.0f;
        style.FrameBorderSize   = 0.0f;

        style.WindowPadding     = ImVec2(16 * scale, 16 * scale);
        style.FramePadding      = ImVec2(12 * scale, 8 * scale);
        style.ItemSpacing       = ImVec2(10 * scale, 10 * scale);
        style.ItemInnerSpacing  = ImVec2(8 * scale, 6 * scale);

        ImVec4* colors = style.Colors;
        colors[ImGuiCol_Text]                  = ImVec4(0.92f, 0.95f, 0.98f, 1.00f);
        colors[ImGuiCol_TextDisabled]          = ImVec4(0.45f, 0.52f, 0.62f, 1.00f);
        colors[ImGuiCol_WindowBg]              = ImVec4(0.06f, 0.08f, 0.12f, 0.96f);
        colors[ImGuiCol_ChildBg]               = ImVec4(0.09f, 0.12f, 0.18f, 0.90f);
        colors[ImGuiCol_PopupBg]               = ImVec4(0.08f, 0.10f, 0.16f, 0.98f);
        colors[ImGuiCol_Border]                = ImVec4(0.18f, 0.24f, 0.36f, 0.75f);
        colors[ImGuiCol_BorderShadow]          = ImVec4(0.00f, 0.00f, 0.00f, 0.00f);
        colors[ImGuiCol_FrameBg]               = ImVec4(0.12f, 0.16f, 0.24f, 0.80f);
        colors[ImGuiCol_FrameBgHovered]        = ImVec4(0.16f, 0.22f, 0.34f, 1.00f);
        colors[ImGuiCol_FrameBgActive]         = ImVec4(0.20f, 0.28f, 0.42f, 1.00f);
        colors[ImGuiCol_TitleBg]               = ImVec4(0.08f, 0.11f, 0.16f, 1.00f);
        colors[ImGuiCol_TitleBgActive]         = ImVec4(0.09f, 0.13f, 0.20f, 1.00f);
        colors[ImGuiCol_MenuBarBg]             = ImVec4(0.09f, 0.12f, 0.18f, 1.00f);
        colors[ImGuiCol_ScrollbarBg]           = ImVec4(0.06f, 0.08f, 0.12f, 0.50f);
        colors[ImGuiCol_ScrollbarGrab]         = ImVec4(0.20f, 0.28f, 0.40f, 0.80f);
        colors[ImGuiCol_ScrollbarGrabHovered]  = ImVec4(0.00f, 0.65f, 0.95f, 0.85f);
        colors[ImGuiCol_ScrollbarGrabActive]   = ImVec4(0.00f, 0.80f, 1.00f, 1.00f);
        colors[ImGuiCol_CheckMark]             = ImVec4(0.00f, 0.85f, 1.00f, 1.00f);
        colors[ImGuiCol_SliderGrab]            = ImVec4(0.00f, 0.75f, 1.00f, 1.00f);
        colors[ImGuiCol_SliderGrabActive]      = ImVec4(0.25f, 0.90f, 1.00f, 1.00f);
        colors[ImGuiCol_Button]                = ImVec4(0.12f, 0.16f, 0.24f, 0.85f);
        colors[ImGuiCol_ButtonHovered]         = ImVec4(0.00f, 0.55f, 0.85f, 0.80f);
        colors[ImGuiCol_ButtonActive]          = ImVec4(0.00f, 0.70f, 1.00f, 1.00f);
        colors[ImGuiCol_Header]                = ImVec4(0.14f, 0.20f, 0.30f, 0.80f);
        colors[ImGuiCol_HeaderHovered]         = ImVec4(0.00f, 0.55f, 0.85f, 0.65f);
        colors[ImGuiCol_HeaderActive]          = ImVec4(0.00f, 0.70f, 1.00f, 0.85f);
        colors[ImGuiCol_Separator]             = ImVec4(0.18f, 0.24f, 0.36f, 0.60f);
        colors[ImGuiCol_Tab]                   = ImVec4(0.10f, 0.14f, 0.20f, 0.80f);
        colors[ImGuiCol_TabHovered]            = ImVec4(0.00f, 0.60f, 0.90f, 0.75f);
        colors[ImGuiCol_TabSelected]           = ImVec4(0.00f, 0.70f, 1.00f, 1.00f);
    }

    // iOS Style Switch Toggle
    static bool ToggleSwitch(const char* label, bool* v)
    {
        ImGui::PushID(label);

        float avail_w = ImGui::GetContentRegionAvail().x;
        float height = 24.0f * g_scale;
        float width = 46.0f * g_scale;
        float radius = height * 0.5f;
        float switch_x = ImGui::GetCursorPosX() + avail_w - width;

        // Label on left
        ImGui::AlignTextToFramePadding();
        ImGui::TextUnformatted(label);

        // Switch button on far right (placed cleanly on the same line)
        ImGui::SameLine(switch_x);
        bool clicked = ImGui::InvisibleButton("##btn", ImVec2(width, height));
        if (clicked) *v = !(*v);

        ImVec2 btn_pos = ImGui::GetItemRectMin();
        float t = *v ? 1.0f : 0.0f;
        ImU32 col_bg = *v ? IM_COL32(0, 180, 245, 255) : IM_COL32(35, 45, 62, 255);

        ImDrawList* draw = ImGui::GetWindowDrawList();
        draw->AddRectFilled(btn_pos, ImVec2(btn_pos.x + width, btn_pos.y + height), col_bg, radius);
        float circle_x = btn_pos.x + radius + t * (width - 2.0f * radius);
        draw->AddCircleFilled(ImVec2(circle_x, btn_pos.y + radius), radius - 2.5f, IM_COL32(255, 255, 255, 255));

        // Submit spacing item properly to advance layout without triggering IsSetPos boundary error
        ImGui::Dummy(ImVec2(0.0f, 3.0f * g_scale));
        ImGui::PopID();
        return clicked;
    }

    void RenderDynamicIsland(bool* menu_open, int enemy_count, int bot_count, bool is_battle, float fps)
    {
        Config& cfg = Cfg();
        if (!cfg.showDynamicIsland) return;

        ImGuiIO& io = ImGui::GetIO();
        float pill_w = 240.0f * g_scale;
        float pill_h = 36.0f * g_scale;
        float pill_x = (io.DisplaySize.x - pill_w) * 0.5f;
        float pill_y = 12.0f * g_scale;

        ImGui::SetNextWindowPos(ImVec2(pill_x, pill_y), ImGuiCond_Always);
        ImGui::SetNextWindowSize(ImVec2(pill_w, pill_h));

        ImGuiWindowFlags flags = ImGuiWindowFlags_NoDecoration |
                                 ImGuiWindowFlags_NoBackground |
                                 ImGuiWindowFlags_NoSavedSettings |
                                 ImGuiWindowFlags_NoFocusOnAppearing;

        if (ImGui::Begin("##DynamicIslandHUD", nullptr, flags)) {
            ImDrawList* draw = ImGui::GetWindowDrawList();
            ImVec2 p0 = ImVec2(pill_x, pill_y);
            ImVec2 p1 = ImVec2(pill_x + pill_w, pill_y + pill_h);

            // Pill Dark Glass Background
            draw->AddRectFilled(p0, p1, IM_COL32(12, 16, 24, 235), 18.0f * g_scale);
            draw->AddRect(p0, p1, IM_COL32(0, 190, 245, 140), 18.0f * g_scale, 0, 1.2f);

            // Indicator dot
            ImU32 status_col = is_battle ? (enemy_count > 0 ? IM_COL32(255, 45, 65, 255) : IM_COL32(0, 230, 120, 255))
                                         : IM_COL32(0, 180, 245, 255);
            draw->AddCircleFilled(ImVec2(p0.x + 16.0f * g_scale, p0.y + pill_h * 0.5f), 4.5f * g_scale, status_col);

            // Text info
            char hud_txt[96];
            if (is_battle) {
                std::snprintf(hud_txt, sizeof(hud_txt), "RYOMEN VIP | E:%d B:%d | %.0f FPS", enemy_count, bot_count, fps);
            } else {
                std::snprintf(hud_txt, sizeof(hud_txt), "RYOMEN VIP | LOBBY | %.0f FPS", fps);
            }

            ImVec2 txt_sz = ImGui::CalcTextSize(hud_txt);
            draw->AddText(ImVec2(p0.x + 28.0f * g_scale, p0.y + (pill_h - txt_sz.y) * 0.5f),
                          IM_COL32(240, 245, 255, 255), hud_txt);

            // Tapping island toggles menu
            ImGui::SetCursorPos(ImVec2(0, 0));
            if (ImGui::InvisibleButton("##IslandBtn", ImVec2(pill_w, pill_h))) {
                if (menu_open) *menu_open = !(*menu_open);
            }
        }
        ImGui::End();
    }

    void Render(bool* open)
    {
        if (!open || !(*open)) return;

        Config& cfg = Cfg();
        ImGuiIO& io = ImGui::GetIO();

        float win_w = 620.0f * g_scale;
        float win_h = 410.0f * g_scale;
        ImVec2 center((io.DisplaySize.x - win_w) * 0.5f, (io.DisplaySize.y - win_h) * 0.5f);

        ImGui::SetNextWindowPos(center, ImGuiCond_FirstUseEver);
        ImGui::SetNextWindowSize(ImVec2(win_w, win_h), ImGuiCond_Always);

        ImGuiWindowFlags flags = ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoResize;

        if (ImGui::Begin("RYOMENX VIP [iOS] ##MainWindow", open, flags)) {
            // Header Bar
            ImDrawList* draw = ImGui::GetWindowDrawList();
            ImVec2 p = ImGui::GetWindowPos();

            // Accent gradient bar at top
            draw->AddRectFilled(ImVec2(p.x, p.y), ImVec2(p.x + win_w, p.y + 4.0f), IM_COL32(0, 190, 245, 255));

            // Left Navigation Tabs
            ImGui::BeginChild("##NavTabs", ImVec2(145.0f * g_scale, 0), true);
            {
                const char* tab_names[] = { "Visuals (ESP)", "Aimbot Master", "Memory Cheats", "Settings" };
                for (int i = 0; i < 4; ++i) {
                    bool is_active = (g_active_tab == i);
                    if (is_active) {
                        ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.00f, 0.65f, 0.95f, 0.90f));
                        ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 1.0f, 1.0f, 1.0f));
                    }

                    if (ImGui::Button(tab_names[i], ImVec2(-1, 38.0f * g_scale))) {
                        g_active_tab = i;
                    }

                    if (is_active) {
                        ImGui::PopStyleColor(2);
                    }
                }

                // Footer version info
                ImGui::SetCursorPosY(ImGui::GetWindowHeight() - 35.0f * g_scale);
                ImGui::Separator();
                ImGui::TextDisabled("RyomenX v3.6 VIP");
            }
            ImGui::EndChild();

            ImGui::SameLine();

            // Right Content Area
            ImGui::BeginChild("##ContentArea", ImVec2(0, 0), true);
            {
                // =============================================================
                // TAB 0: VISUALS (ESP)
                // =============================================================
                if (g_active_tab == 0) {
                    ImGui::TextColored(ImVec4(0.0f, 0.85f, 1.0f, 1.0f), "MASTER ESP & VISUALS");
                    ImGui::Separator();

                    ToggleSwitch("Master ESP", &cfg.espEnabled);
                    ToggleSwitch("Player Box", &cfg.espBox);

                    if (cfg.espBox) {
                        const char* box_styles[] = { "2D Box (Standard)", "Corner Brackets", "3D Perspective Box" };
                        ImGui::Combo("Box Style", &cfg.espBoxStyle, box_styles, 3);
                    }

                    ToggleSwitch("3D Skeleton Bones", &cfg.espSkeleton);
                    ToggleSwitch("Health Bar", &cfg.espHealth);
                    ToggleSwitch("ESP Snaplines", &cfg.espSnaplines);

                    if (cfg.espSnaplines) {
                        const char* snap_origins[] = { "Screen Bottom", "Crosshair Center", "Screen Top" };
                        ImGui::Combo("Snapline Origin", &cfg.snaplinePos, snap_origins, 3);
                    }

                    ToggleSwitch("Player Nickname", &cfg.espName);
                    ToggleSwitch("Distance Tag", &cfg.espDistance);
                    ToggleSwitch("Offscreen Radar 360", &cfg.espOffscreen360);
                    ToggleSwitch("Precision Crosshair", &cfg.espCrosshair);
                    ToggleSwitch("Filter Out Bots", &cfg.espHideBots);
                    ToggleSwitch("Team Filter", &cfg.teamCheck);

                    ImGui::SliderFloat("Max ESP Distance", &cfg.espMaxDistance, 50.0f, 800.0f, "%.0f m");

                    ImGui::Spacing();
                    ImGui::TextColored(ImVec4(0.0f, 0.85f, 1.0f, 1.0f), "IPAD VIEW (WIDE CAMERA FOV)");
                    ImGui::Separator();
                    ToggleSwitch("Enable iPad View", &cfg.ipadFovEnabled);
                    if (cfg.ipadFovEnabled) {
                        ImGui::SliderFloat("Camera FOV", &cfg.ipadFovDeg, 55.0f, 110.0f, "%.0f deg");
                    }
                }

                // =============================================================
                // TAB 1: AIMBOT MASTER
                // =============================================================
                else if (g_active_tab == 1) {
                    ImGui::TextColored(ImVec4(0.0f, 0.85f, 1.0f, 1.0f), "MASTER AIMBOT ENGINE");
                    ImGui::Separator();

                    ToggleSwitch("Master Aimbot", &cfg.aimEnabled);
                    ToggleSwitch("Silent Aim (Ray Trajectory)", &cfg.silentAim);
                    ToggleSwitch("Native Engine Camera Aim", &cfg.aimNativeEngine);
                    ToggleSwitch("Draw FOV Circle", &cfg.aimDrawFov);

                    const char* bones[] = { "Head Center", "Upper Chest", "Pelvis / Hip" };
                    ImGui::Combo("Target Bone", &cfg.aimBone, bones, 3);

                    const char* activations[] = { "Always Active", "Scope Only", "Scope & Firing", "Firing Only" };
                    ImGui::Combo("Activation Mode", &cfg.aimActivation, activations, 4);

                    ImGui::SliderFloat("FOV Radius", &cfg.aimFov, 20.0f, 360.0f, "%.0f px");
                    ImGui::SliderFloat("Aim Smoothness", &cfg.aimSmooth, 1.0f, 15.0f, "%.1f");
                    ImGui::SliderFloat("Aim Power / Ratio", &cfg.aimPower, 10.0f, 100.0f, "%.0f%%");
                    ImGui::SliderFloat("Aim Max Range", &cfg.aimDistance, 50.0f, 500.0f, "%.0f m");

                    ToggleSwitch("Target Bots", &cfg.aimTargetBots);
                    ToggleSwitch("Ignore Knocked Enemies", &cfg.aimIgnoreKnocked);
                }

                // =============================================================
                // TAB 2: MEMORY CHEATS
                // =============================================================
                else if (g_active_tab == 2) {
                    ImGui::TextColored(ImVec4(0.0f, 0.85f, 1.0f, 1.0f), "MEMORY PATCH SUITE (RYOMENX)");
                    ImGui::Separator();

                    ToggleSwitch("Zero Recoil (No Recoil)", &cfg.memNoRecoil);
                    ToggleSwitch("Speed Hack", &cfg.memSpeedHack);
                    if (cfg.memSpeedHack) {
                        ImGui::SliderFloat("Speed Multiplier", &cfg.memSpeedVal, 1.0f, 8.0f, "%.1fx");
                    }

                    ToggleSwitch("Wallhack (Depth Disable)", &cfg.memWallhack);
                    ToggleSwitch("No Fall Damage", &cfg.memNoFallDamage);
                    ToggleSwitch("Fly Hack / Air Jump", &cfg.memFlyHack);
                    ToggleSwitch("Underground Position", &cfg.memUnderground);
                    ToggleSwitch("Fast Parachute Drop", &cfg.memFastParachute);
                    ToggleSwitch("No Grass (Clear Foliage)", &cfg.memNoGrass);
                    ToggleSwitch("Clear Sky / Fog", &cfg.memClearFog);
                }

                // =============================================================
                // TAB 3: SETTINGS
                // =============================================================
                else if (g_active_tab == 3) {
                    ImGui::TextColored(ImVec4(0.0f, 0.85f, 1.0f, 1.0f), "OVERLAY & SYSTEM SETTINGS");
                    ImGui::Separator();

                    ToggleSwitch("Anti-Record / StreamProof", &cfg.antiRecord);
                    ToggleSwitch("Show Dynamic Island HUD", &cfg.showDynamicIsland);
                    ImGui::SliderFloat("Menu Scale", &cfg.menuScale, 0.8f, 1.4f, "%.2fx");

                    ImGui::Spacing();
                    ImGui::TextColored(ImVec4(0.0f, 0.85f, 1.0f, 1.0f), "LIVE TELEMETRY");
                    ImGui::Separator();
                    ImGui::Text("ClientApp: 0x%llX", g_TelemetryClientApp);
                    ImGui::Text("Active Camera: 0x%llX (%s)", g_TelemetryActiveCamera, g_TelemetryVpValid ? "VALID 3D" : "SCANNING");
                    ImGui::Text("Entities Loaded: %llu", g_TelemetryEntitiesLoaded);
                    ImGui::Text("Engine: NetEase NeoX (arm64 Metal)");
                }
            }
            ImGui::EndChild();
        }
        ImGui::End();
    }
}

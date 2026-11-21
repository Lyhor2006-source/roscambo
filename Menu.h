#pragma once
#include "imgui.h"
#include <cstdint>
#include <cstddef>

namespace Menu
{
    enum AimActivation
    {
        AimAlways = 0,
        AimScopeOnly,
        AimScopeAndFiring,
        AimFiringOnly
    };

    struct Config
    {
        // Visuals
        bool  espEnabled        = false;
        bool  espBox            = true;
        bool  espSkeleton       = true;
        bool  espSnaplines      = false;
        bool  espName           = true;
        bool  espHealth         = true;
        bool  espDistance       = true;
        bool  espCrosshair      = false;
        bool  espOffscreen360   = false;
        int   espBoxStyle       = 0;       // 0 = full, 1 = corners
        float espMaxDistance    = 400.0f;  // meters
        float espBoxColor[4]     = { 0.20f, 0.45f, 1.00f, 1.00f };
        float espTextColor[4]    = { 0.10f, 0.11f, 0.14f, 1.00f };
        float boxThickness      = 1.5f;
        float lineThickness     = 1.2f;
        float skeletonThickness = 1.2f;
        bool  teamCheck         = false;
        bool  radarEnabled      = false;
        float radarRange        = 150.0f;  // meters

        // Aim
        bool  aimEnabled        = false;
        bool  silentAim         = false;
        bool  aim360            = false;
        float aimStrength       = 50.0f;   // percent
        int   aimBone           = 0;       // 0 head, 1 neck, 2 chest, 3 pelvis
        int   aimActivation     = AimAlways;
        int   aimSnapMode       = 1;       // 0 = Custom Smooth, 1 = 50/50 Skill Blend, 2 = Rage Snap
        float aimSkillRatio     = 0.50f;
        float aimFov            = 90.0f;   // pixels
        float aimSmooth         = 6.0f;    // 1 = instant
        float aimDistance       = 300.0f;  // meters
        bool  aimDrawFov        = true;
        bool  aimVisibleOnly    = true;

        // Misc
        bool  recoilAdjust      = false;
        float recoilStrength    = 50.0f;
        bool  showWatermark     = true;
        bool  showFps           = true;
        float menuOpacity       = 1.0f;

        // Settings
        float accent[3]         = { 0.20f, 0.45f, 1.00f };
        bool  ghillieSpaceData  = false;
    };

    Config& Cfg();

    // Call once after ImGui::CreateContext()
    void ApplyWhiteTheme(float scale, const ImVec4& accent);

    // Call every frame
    void Render(bool* open);

    // Optional watermark / FPS pill
    void RenderHud(const char* title);
}

// Runtime Telemetry exports for Menu integration
extern void*               g_MenuAvatarTexture;
extern unsigned long long  g_TelemetryClientApp;
extern unsigned long long  g_TelemetryMoveHits;
extern unsigned long long  g_TelemetryCreateHits;
extern unsigned long long  g_TelemetryCachedPositions;
extern unsigned long long  g_TelemetryEntitiesLoaded;

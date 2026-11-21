#pragma once
// =============================================================================
// Project: RosCambo Mod (Rules of Survival Fan-Made Private Server)
// Module: Menu & VIP Cyber UI (Faithful adaptation of RyomenX VIP)
// =============================================================================

#include "imgui.h"
#include <cstdint>
#include <cstddef>

namespace Menu
{
    enum AimActivation
    {
        AimAlways = 0,
        AimScopeOnly = 1,
        AimScopeAndFiring = 2,
        AimFiringOnly = 3
    };

    enum BoxStyle
    {
        Box2D = 0,
        BoxCorner = 1,
        Box3D = 2
    };

    struct Config
    {
        // Visuals (ESP)
        bool  espEnabled        = true;
        bool  espBox            = true;
        int   espBoxStyle       = 1;       // 0=2D, 1=Corner Brackets, 2=3D Box
        bool  espSkeleton       = true;
        bool  espSnaplines      = false;
        int   snaplinePos       = 0;       // 0=Bottom, 1=Crosshair, 2=Top
        bool  espHideBots       = false;
        bool  espName           = true;
        bool  espHealth         = true;
        bool  espDistance       = true;
        bool  espCrosshair      = false;
        bool  espOffscreen360   = true;
        float espMaxDistance    = 500.0f;  // meters
        float boxThickness      = 1.5f;
        float lineThickness     = 1.2f;
        float skeletonThickness = 1.2f;
        bool  teamCheck         = false;
        bool  antiRecord        = false;

        // Custom Colors
        float colEnemy[4]       = { 1.00f, 0.22f, 0.32f, 1.00f }; // Neon Crimson
        float colBot[4]         = { 1.00f, 0.75f, 0.10f, 1.00f }; // Gold Amber
        float colSkeleton[4]    = { 0.00f, 0.85f, 1.00f, 1.00f }; // Electric Blue
        float colSnapline[4]    = { 0.00f, 0.85f, 1.00f, 0.70f };

        // iPad View / Wide FOV
        bool  ipadFovEnabled    = false;
        float ipadFovDeg        = 95.0f;   // 55° to 110°

        // Aim Master
        bool  aimEnabled        = true;
        bool  silentAim         = false;   // Raycast Trajectory wrap
        bool  aimNativeEngine   = true;    // Use BigWorld camCtrlComp native rotation
        bool  aim360            = false;
        int   aimBone           = 0;       // 0=Head, 1=Chest, 2=Pelvis
        int   aimActivation     = AimScopeAndFiring;
        float aimFov            = 120.0f;  // pixels
        float aimSmooth         = 5.0f;    // 1 to 15
        float aimPower          = 65.0f;   // percentage
        float aimDistance       = 350.0f;  // meters
        bool  aimDrawFov        = true;
        bool  aimVisibleOnly    = false;
        bool  aimTargetBots     = false;
        bool  aimIgnoreKnocked  = true;

        // Memory Cheats (RyomenX Suite)
        bool  memNoRecoil       = false;
        bool  memSpeedHack      = false;
        float memSpeedVal       = 2.5f;    // 1.0x to 8.0x
        bool  memWallhack       = false;
        bool  memNoFallDamage   = false;
        bool  memFlyHack        = false;
        bool  memUnderground    = false;
        bool  memFastParachute  = false;
        bool  memNoGrass        = false;
        bool  memClearFog       = false;

        // HUD / Overlay Settings
        bool  showDynamicIsland = true;
        float menuScale         = 1.0f;
        float menuOpacity       = 0.95f;
        float accent[3]         = { 0.00f, 0.75f, 1.00f }; // Cyber Cyan

        // Aim Snap & Debug Compatibility
        int   aimSnapMode       = 1;
        float aimSkillRatio     = 0.50f;
        bool  ghillieSpaceData  = false;
        bool  debugScanToFile   = true;
        bool  autoSendToPc      = false;
        char  serverIp[64]      = "192.168.7.103:8888";
    };

    Config& Cfg();

    // Call once to apply the sleek dark VIP theme
    void ApplyRyomenVipTheme(float scale);

    // Main VIP Window
    void Render(bool* open);

    // Dynamic Island / Floating pill HUD
    void RenderDynamicIsland(bool* menu_open, int enemy_count, int bot_count, bool is_battle, float fps);
}

// Runtime Telemetry exports
extern void*               g_MenuAvatarTexture;
extern unsigned long long  g_TelemetryClientApp;
extern unsigned long long  g_TelemetryActiveCamera;
extern unsigned int        g_TelemetryCameraFlag;
extern bool                g_TelemetryVpValid;
extern float               g_TelemetryW2S_X;
extern float               g_TelemetryW2S_Y;
extern unsigned long long  g_TelemetryMoveHits;
extern unsigned long long  g_TelemetryCreateHits;
extern unsigned long long  g_TelemetryCachedPositions;
extern unsigned long long  g_TelemetryEntitiesLoaded;
extern bool                g_TriggerDebugDump;

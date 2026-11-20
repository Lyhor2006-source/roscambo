#pragma once
// =============================================================================
// Project: RosCambo iOS Cheat
// File: ImGuiTheme.h
// Description: Cyber-Tactical Dark modern styling for ImGui Metal Menu
// =============================================================================

#include "imgui.h"

inline void ApplyCyberTacticalTheme() {
    ImGuiStyle& style = ImGui::GetStyle();

    style.WindowRounding = 10.0f;
    style.ChildRounding = 8.0f;
    style.FrameRounding = 6.0f;
    style.PopupRounding = 8.0f;
    style.ScrollbarRounding = 9.0f;
    style.GrabRounding = 6.0f;
    style.TabRounding = 7.0f;

    style.WindowPadding = ImVec2(12, 12);
    style.FramePadding = ImVec2(8, 6);
    style.ItemSpacing = ImVec2(8, 8);
    style.ItemInnerSpacing = ImVec2(6, 6);
    style.IndentSpacing = 20.0f;
    style.ScrollbarSize = 14.0f;
    style.GrabMinSize = 12.0f;

    style.WindowBorderSize = 1.0f;
    style.ChildBorderSize = 1.0f;
    style.PopupBorderSize = 1.0f;
    style.FrameBorderSize = 0.0f;
    style.TabBorderSize = 0.0f;

    ImVec4* colors = style.Colors;

    // Palette: Deep Obsidian, Electric Cyan (#00E5FF), Neon Violet (#7C4DFF), Hazard Red
    colors[ImGuiCol_Text]                  = ImVec4(0.92f, 0.95f, 0.98f, 1.00f);
    colors[ImGuiCol_TextDisabled]          = ImVec4(0.50f, 0.55f, 0.60f, 1.00f);
    colors[ImGuiCol_WindowBg]              = ImVec4(0.06f, 0.07f, 0.09f, 0.94f);
    colors[ImGuiCol_ChildBg]               = ImVec4(0.09f, 0.11f, 0.14f, 0.85f);
    colors[ImGuiCol_PopupBg]               = ImVec4(0.08f, 0.09f, 0.12f, 0.96f);
    colors[ImGuiCol_Border]                = ImVec4(0.00f, 0.89f, 1.00f, 0.35f); // Cyan accent border
    colors[ImGuiCol_BorderShadow]          = ImVec4(0.00f, 0.00f, 0.00f, 0.00f);
    colors[ImGuiCol_FrameBg]               = ImVec4(0.12f, 0.15f, 0.19f, 0.80f);
    colors[ImGuiCol_FrameBgHovered]        = ImVec4(0.18f, 0.22f, 0.28f, 0.90f);
    colors[ImGuiCol_FrameBgActive]         = ImVec4(0.00f, 0.70f, 0.85f, 0.40f);
    colors[ImGuiCol_TitleBg]               = ImVec4(0.05f, 0.06f, 0.08f, 1.00f);
    colors[ImGuiCol_TitleBgActive]         = ImVec4(0.08f, 0.10f, 0.14f, 1.00f);
    colors[ImGuiCol_TitleBgCollapsed]      = ImVec4(0.05f, 0.06f, 0.08f, 0.75f);
    colors[ImGuiCol_MenuBarBg]             = ImVec4(0.10f, 0.12f, 0.15f, 1.00f);
    colors[ImGuiCol_ScrollbarBg]           = ImVec4(0.05f, 0.06f, 0.08f, 0.60f);
    colors[ImGuiCol_ScrollbarGrab]         = ImVec4(0.20f, 0.25f, 0.32f, 1.00f);
    colors[ImGuiCol_ScrollbarGrabHovered]  = ImVec4(0.00f, 0.80f, 0.95f, 0.80f);
    colors[ImGuiCol_ScrollbarGrabActive]   = ImVec4(0.00f, 0.90f, 1.00f, 1.00f);
    colors[ImGuiCol_CheckMark]             = ImVec4(0.00f, 0.90f, 1.00f, 1.00f);
    colors[ImGuiCol_SliderGrab]            = ImVec4(0.00f, 0.80f, 0.95f, 1.00f);
    colors[ImGuiCol_SliderGrabActive]      = ImVec4(0.30f, 0.90f, 1.00f, 1.00f);
    colors[ImGuiCol_Button]                = ImVec4(0.14f, 0.18f, 0.23f, 0.85f);
    colors[ImGuiCol_ButtonHovered]         = ImVec4(0.00f, 0.75f, 0.90f, 0.65f);
    colors[ImGuiCol_ButtonActive]          = ImVec4(0.00f, 0.85f, 1.00f, 1.00f);
    colors[ImGuiCol_Header]                = ImVec4(0.16f, 0.20f, 0.26f, 0.70f);
    colors[ImGuiCol_HeaderHovered]         = ImVec4(0.00f, 0.75f, 0.90f, 0.60f);
    colors[ImGuiCol_HeaderActive]          = ImVec4(0.00f, 0.85f, 1.00f, 0.85f);
    colors[ImGuiCol_Separator]             = ImVec4(0.20f, 0.24f, 0.30f, 0.60f);
    colors[ImGuiCol_SeparatorHovered]      = ImVec4(0.00f, 0.80f, 0.95f, 0.78f);
    colors[ImGuiCol_SeparatorActive]       = ImVec4(0.00f, 0.90f, 1.00f, 1.00f);
    colors[ImGuiCol_ResizeGrip]            = ImVec4(0.20f, 0.25f, 0.30f, 0.30f);
    colors[ImGuiCol_ResizeGripHovered]     = ImVec4(0.00f, 0.80f, 0.95f, 0.67f);
    colors[ImGuiCol_ResizeGripActive]      = ImVec4(0.00f, 0.90f, 1.00f, 0.95f);
    colors[ImGuiCol_Tab]                   = ImVec4(0.11f, 0.14f, 0.18f, 0.86f);
    colors[ImGuiCol_TabHovered]            = ImVec4(0.00f, 0.75f, 0.90f, 0.80f);
    colors[ImGuiCol_TabSelected]           = ImVec4(0.00f, 0.60f, 0.80f, 1.00f);
    colors[ImGuiCol_TabDimmed]             = ImVec4(0.08f, 0.10f, 0.13f, 0.97f);
    colors[ImGuiCol_TabDimmedSelected]     = ImVec4(0.12f, 0.16f, 0.20f, 1.00f);
}

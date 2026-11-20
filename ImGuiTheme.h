#pragma once
// =============================================================================
// Project: RosCambo iOS Cheat
// File: ImGuiTheme.h
// Description: Wizard/Predator iOS Style - Deep Blue Glass, Cyan Accent, Capsule Tabs
// =============================================================================

#include "imgui.h"

inline void ApplyWizardIOSTheme() {
    ImGuiStyle& style = ImGui::GetStyle();

    style.WindowRounding = 14.0f;
    style.ChildRounding = 10.0f;
    style.FrameRounding = 8.0f;
    style.PopupRounding = 10.0f;
    style.ScrollbarRounding = 10.0f;
    style.GrabRounding = 10.0f;
    style.TabRounding = 8.0f;

    style.WindowPadding = ImVec2(12, 12);
    style.FramePadding = ImVec2(10, 6);
    style.ItemSpacing = ImVec2(10, 10);
    style.ItemInnerSpacing = ImVec2(8, 8);
    style.ScrollbarSize = 8.0f;
    style.GrabMinSize = 14.0f;

    style.WindowBorderSize = 1.2f;
    style.ChildBorderSize = 1.0f;
    style.PopupBorderSize = 1.0f;
    style.FrameBorderSize = 0.0f;

    ImVec4* colors = style.Colors;

    // Palette extracted from the Wizard iOS reference image:
    // Dark deep navy/black glass with rich electric cyan (#0099FF / #00E5FF)
    colors[ImGuiCol_Text]                  = ImVec4(0.95f, 0.96f, 0.98f, 1.00f);
    colors[ImGuiCol_TextDisabled]          = ImVec4(0.55f, 0.60f, 0.68f, 1.00f);
    colors[ImGuiCol_WindowBg]              = ImVec4(0.04f, 0.07f, 0.12f, 0.92f); // Deep frosted navy glass
    colors[ImGuiCol_ChildBg]               = ImVec4(0.06f, 0.09f, 0.15f, 0.70f);
    colors[ImGuiCol_PopupBg]               = ImVec4(0.05f, 0.08f, 0.14f, 0.96f);
    colors[ImGuiCol_Border]                = ImVec4(0.00f, 0.75f, 1.00f, 0.55f); // Vibrant cyan outline
    colors[ImGuiCol_BorderShadow]          = ImVec4(0.00f, 0.00f, 0.00f, 0.00f);
    colors[ImGuiCol_FrameBg]               = ImVec4(0.10f, 0.15f, 0.22f, 0.85f);
    colors[ImGuiCol_FrameBgHovered]        = ImVec4(0.14f, 0.20f, 0.30f, 0.90f);
    colors[ImGuiCol_FrameBgActive]         = ImVec4(0.00f, 0.60f, 0.85f, 0.50f);
    colors[ImGuiCol_TitleBg]               = ImVec4(0.04f, 0.06f, 0.10f, 1.00f);
    colors[ImGuiCol_TitleBgActive]         = ImVec4(0.05f, 0.08f, 0.14f, 1.00f);
    colors[ImGuiCol_ScrollbarBg]           = ImVec4(0.00f, 0.00f, 0.00f, 0.00f);
    colors[ImGuiCol_ScrollbarGrab]         = ImVec4(0.95f, 0.95f, 0.95f, 0.90f); // White/bright rounded pill
    colors[ImGuiCol_ScrollbarGrabHovered]  = ImVec4(0.00f, 0.80f, 1.00f, 1.00f);
    colors[ImGuiCol_ScrollbarGrabActive]   = ImVec4(0.00f, 0.90f, 1.00f, 1.00f);
    colors[ImGuiCol_CheckMark]             = ImVec4(0.00f, 0.80f, 1.00f, 1.00f);
    colors[ImGuiCol_SliderGrab]            = ImVec4(1.00f, 1.00f, 1.00f, 1.00f); // Crisp white circle knob
    colors[ImGuiCol_SliderGrabActive]      = ImVec4(0.00f, 0.85f, 1.00f, 1.00f);
    colors[ImGuiCol_Button]                = ImVec4(0.08f, 0.13f, 0.20f, 0.90f);
    colors[ImGuiCol_ButtonHovered]         = ImVec4(0.00f, 0.60f, 0.85f, 0.80f);
    colors[ImGuiCol_ButtonActive]          = ImVec4(0.00f, 0.75f, 1.00f, 1.00f);
    colors[ImGuiCol_Header]                = ImVec4(0.00f, 0.55f, 0.80f, 0.50f);
    colors[ImGuiCol_HeaderHovered]         = ImVec4(0.00f, 0.65f, 0.90f, 0.70f);
    colors[ImGuiCol_HeaderActive]          = ImVec4(0.00f, 0.75f, 1.00f, 0.90f);
    colors[ImGuiCol_Separator]             = ImVec4(0.00f, 0.70f, 0.95f, 0.35f);
    colors[ImGuiCol_Tab]                   = ImVec4(0.08f, 0.12f, 0.18f, 0.90f);
    colors[ImGuiCol_TabHovered]            = ImVec4(0.00f, 0.65f, 0.90f, 0.80f);
    colors[ImGuiCol_TabSelected]           = ImVec4(0.00f, 0.60f, 0.88f, 1.00f); // Bright blue pill
    colors[ImGuiCol_TabDimmed]             = ImVec4(0.06f, 0.09f, 0.14f, 0.90f);
    colors[ImGuiCol_TabDimmedSelected]     = ImVec4(0.00f, 0.50f, 0.75f, 1.00f);
}

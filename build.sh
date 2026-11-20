#!/usr/bin/env bash
# =============================================================================
# build.sh - Automated build script for RosCambo iOS Cheat on VPS / macOS
# =============================================================================
set -e

echo "[*] Initializing build environment for RosCambo iOS Cheat..."

# Check or download Dear ImGui if not present
if [ ! -f "imgui/imgui.h" ]; then
    echo "[*] Downloading Dear ImGui..."
    mkdir -p imgui/backends
    curl -sSL "https://raw.githubusercontent.com/ocornut/imgui/master/imgui.h" -o imgui/imgui.h
    curl -sSL "https://raw.githubusercontent.com/ocornut/imgui/master/imgui.cpp" -o imgui/imgui.cpp
    curl -sSL "https://raw.githubusercontent.com/ocornut/imgui/master/imgui_draw.cpp" -o imgui/imgui_draw.cpp
    curl -sSL "https://raw.githubusercontent.com/ocornut/imgui/master/imgui_tables.cpp" -o imgui/imgui_tables.cpp
    curl -sSL "https://raw.githubusercontent.com/ocornut/imgui/master/imgui_widgets.cpp" -o imgui/imgui_widgets.cpp
    curl -sSL "https://raw.githubusercontent.com/ocornut/imgui/master/imgui_internal.h" -o imgui/imgui_internal.h
    curl -sSL "https://raw.githubusercontent.com/ocornut/imgui/master/imstb_rectpack.h" -o imgui/imstb_rectpack.h
    curl -sSL "https://raw.githubusercontent.com/ocornut/imgui/master/imstb_textedit.h" -o imgui/imstb_textedit.h
    curl -sSL "https://raw.githubusercontent.com/ocornut/imgui/master/imstb_truetype.h" -o imgui/imstb_truetype.h

    # Metal Backend
    curl -sSL "https://raw.githubusercontent.com/ocornut/imgui/master/backends/imgui_impl_metal.h" -o imgui/backends/imgui_impl_metal.h
    curl -sSL "https://raw.githubusercontent.com/ocornut/imgui/master/backends/imgui_impl_metal.mm" -o imgui/backends/imgui_impl_metal.mm
    echo "[+] ImGui downloaded successfully."
fi

# Run Makefile
echo "[*] Compiling roscheat.dylib..."
make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

echo "[+] Compilation successful! File generated: roscheat.dylib"
ls -lh roscheat.dylib

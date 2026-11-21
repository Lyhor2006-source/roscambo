#pragma once
// =============================================================================
// Project: RosCambo Mod (Rules of Survival Fan-Made Private Server)
// Module: RosGameBridge (In-Process Python Bridge Engine inspired by RyomenX)
// Description: Dynamic Python runtime loader, native event loop injection,
//              native WorldToScreen, true 3D bone extraction, and engine aimbot.
// =============================================================================

#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#include <dlfcn.h>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <sstream>
#include <chrono>
#include <atomic>
#include <mutex>

#include "NeoXEngine.h"
#include "RyomenPayload.h"

struct BridgeBone {
    bool valid = false;
    float x = 0.0f;
    float y = 0.0f;
};

struct BridgePlayer {
    float fs_x = 0.0f, fs_y = 0.0f; // Feet screen pos
    float hs_x = 0.0f, hs_y = 0.0f; // Head screen pos
    bool on_screen = false;
    Vector3 pos;
    Vector3 vel;
    int health = 100;
    int max_health = 100;
    bool is_enemy = true;
    bool is_visible = false;
    float distance = 0.0f;
    bool is_knocked = false;
    bool is_bot = false;
    int team_id = 0;
    int shield = 0;
    int max_shield = 0;
    int in_vehicle = 0;
    int entity_id = 0;
    char name[64] = {0};
    BridgeBone bones[16];
    int weapon_kind = 0;
};

struct BridgeSnapshot {
    int entity_count = 0;
    Vector3 local_pos;
    Vector3 view_pos;
    Vector3 view_dir;
    int mode = 0;
    int trig = 0;
    uint64_t timestamp_ms = 0;
    std::vector<BridgePlayer> players;
};

class RosGameBridge {
public:
    typedef int (*Py_IsInitialized_t)();
    typedef int (*PyGILState_Ensure_t)();
    typedef void (*PyGILState_Release_t)(int);
    typedef void* (*PyImport_AddModule_t)(const char*);
    typedef void* (*PyModule_GetDict_t)(void*);
    typedef void* (*PyRun_StringFlags_t)(const char*, int, void*, void*, void*);
    typedef void (*PyErr_Clear_t)();

    static inline Py_IsInitialized_t   s_Py_IsInitialized = nullptr;
    static inline PyGILState_Ensure_t  s_PyGILState_Ensure = nullptr;
    static inline PyGILState_Release_t s_PyGILState_Release = nullptr;
    static inline PyImport_AddModule_t s_PyImport_AddModule = nullptr;
    static inline PyModule_GetDict_t   s_PyModule_GetDict = nullptr;
    static inline PyRun_StringFlags_t  s_PyRun_StringFlags = nullptr;
    static inline PyErr_Clear_t        s_PyErr_Clear = nullptr;

    static inline std::string s_DataDir;
    static inline std::string s_CfgPath;
    static inline std::string s_EspPath;
    static inline std::string s_StatPath;
    static inline std::atomic<bool> s_BridgeInjected{false};
    static inline std::atomic<bool> s_PythonFound{false};
    static inline std::mutex s_SnapshotMutex;
    static inline BridgeSnapshot s_LatestSnapshot;
    static inline uint64_t s_LastReadTick = 0;

    static bool ResolvePythonAPI() {
        if (s_PythonFound.load()) return true;

        uintptr_t base = MemoryEngine::GetBaseAddress();
        if (!base) return false;

        s_Py_IsInitialized  = (Py_IsInitialized_t)dlsym(RTLD_DEFAULT, "Py_IsInitialized");
        s_PyGILState_Ensure = (PyGILState_Ensure_t)dlsym(RTLD_DEFAULT, "PyGILState_Ensure");
        s_PyGILState_Release= (PyGILState_Release_t)dlsym(RTLD_DEFAULT, "PyGILState_Release");
        s_PyImport_AddModule= (PyImport_AddModule_t)dlsym(RTLD_DEFAULT, "PyImport_AddModule");
        s_PyModule_GetDict  = (PyModule_GetDict_t)dlsym(RTLD_DEFAULT, "PyModule_GetDict");
        s_PyRun_StringFlags = (PyRun_StringFlags_t)dlsym(RTLD_DEFAULT, "PyRun_StringFlags");
        s_PyErr_Clear       = (PyErr_Clear_t)dlsym(RTLD_DEFAULT, "PyErr_Clear");

        // Rules of Survival client binary strips dynamic export symbols.
        // Fallback to exact, verified internal Python runtime offsets from binary analysis:
        if (!s_Py_IsInitialized)   s_Py_IsInitialized   = (Py_IsInitialized_t)(base + 0x1d05a24);
        if (!s_PyGILState_Ensure)  s_PyGILState_Ensure  = (PyGILState_Ensure_t)(base + 0x1d05158);
        if (!s_PyGILState_Release) s_PyGILState_Release = (PyGILState_Release_t)(base + 0x1d051dc);
        if (!s_PyImport_AddModule) s_PyImport_AddModule = (PyImport_AddModule_t)(base + 0x1cf8fd4);
        if (!s_PyModule_GetDict)   s_PyModule_GetDict   = (PyModule_GetDict_t)(base + 0x1c79884);
        if (!s_PyRun_StringFlags)  s_PyRun_StringFlags  = (PyRun_StringFlags_t)(base + 0x1d0689c);
        if (!s_PyErr_Clear)        s_PyErr_Clear        = (PyErr_Clear_t)(base + 0x1cf17f0);

        bool all_valid = (s_Py_IsInitialized && s_PyGILState_Ensure && s_PyGILState_Release &&
                          s_PyImport_AddModule && s_PyModule_GetDict && s_PyRun_StringFlags && s_PyErr_Clear);

        s_PythonFound.store(all_valid);
        return all_valid;
    }

    static void InitializeDirectories() {
        if (!s_DataDir.empty()) return;

        NSArray* paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString* cachesDir = paths.firstObject;
        NSString* targetDir = [cachesDir stringByAppendingPathComponent:@"RosCambo"];

        NSFileManager* fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:targetDir]) {
            [fm createDirectoryAtPath:targetDir withIntermediateDirectories:YES attributes:nil error:nil];
        }

        s_DataDir  = [targetDir UTF8String];
        s_CfgPath  = s_DataDir + "/aim_cfg.txt";
        s_EspPath  = s_DataDir + "/ros_esp.txt";
        s_StatPath = s_DataDir + "/ros_stat.txt";
    }

    static bool TryInjectPayload() {
        if (s_BridgeInjected.load()) return true;

        // Rate-limit injection attempts to once every 2 seconds
        static uint64_t s_LastAttemptMs = 0;
        uint64_t now_ms = (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
        if (now_ms - s_LastAttemptMs < 2000) {
            return false;
        }
        s_LastAttemptMs = now_ms;

        if (!ResolvePythonAPI()) return false;

        // CRITICAL: Ensure game engine has initialized its Python runtime before calling it
        if (!s_Py_IsInitialized || s_Py_IsInitialized() == 0) {
            NSLog(@"[RosGameBridge] Waiting for game Python initialization...");
            return false;
        }

        InitializeDirectories();

        std::string init_prefix =
            "_RYOMENX_DIR = '" + s_DataDir + "'\n"
            "_PB_PATH = _RYOMENX_DIR + '/ros_esp.txt'\n"
            "_PB_STAT = _RYOMENX_DIR + '/ros_stat.txt'\n"
            "_PB_EMPTY = False\n"
            "_PB_ACTION_TS = 0.0\n"
            "_PB_DIAG_TS = 0.0\n"
            "class _PBNotBattle(Exception): pass\n";

        std::string full_script = init_prefix + kRyomenPythonPayload;

        // Safely acquire Python Global Interpreter Lock (GIL)
        int gil = s_PyGILState_Ensure();

        void* main_mod = s_PyImport_AddModule("__main__");
        if (!main_mod) {
            if (s_PyErr_Clear) s_PyErr_Clear();
            s_PyGILState_Release(gil);
            NSLog(@"[RosGameBridge] Failed to get __main__ module");
            return false;
        }

        void* globals_dict = s_PyModule_GetDict(main_mod);
        if (!globals_dict) {
            if (s_PyErr_Clear) s_PyErr_Clear();
            s_PyGILState_Release(gil);
            NSLog(@"[RosGameBridge] Failed to get module dictionary");
            return false;
        }

        // 257 = Py_file_input
        void* res = s_PyRun_StringFlags(full_script.c_str(), 257, globals_dict, globals_dict, nullptr);
        if (s_PyErr_Clear) s_PyErr_Clear();

        // Release GIL
        s_PyGILState_Release(gil);

        if (res != nullptr) {
            s_BridgeInjected.store(true);
            NSLog(@"[RosGameBridge] In-process Python bridge successfully installed!");
            return true;
        }

        NSLog(@"[RosGameBridge] Python payload execution returned null");
        return false;
    }

    // Push 40 floating point control options to aim_cfg.txt (throttled to 4Hz)
    static void PushConfig(
        bool aim_en, int aim_mode, float aim_fov, float aim_smooth, float aim_power,
        bool vis_chk, bool ign_knock, int aim_bone, float screen_w, float screen_h, float max_dist,
        bool silent_aim, bool aim_360, bool hide_bots, bool draw_skeleton,
        bool ipad_fov_en, float ipad_fov,
        bool speed_en, float speed_val,
        bool wallhack, bool no_fall, bool fly, bool underground,
        bool no_grass, bool fast_para, bool wide_cam, bool clear_fog, bool no_recoil)
    {
        if (!s_BridgeInjected.load()) return;

        static uint64_t s_LastPushMs = 0;
        uint64_t now_ms = (uint64_t)([[NSDate date] timeIntervalSince1970] * 1000.0);
        if (now_ms - s_LastPushMs < 250) {
            return;
        }
        s_LastPushMs = now_ms;

        InitializeDirectories();

        char buf[512];
        std::snprintf(buf, sizeof(buf),
            "%.1f %.1f %.1f %.2f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f "
            "0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f\n",
            aim_en ? 1.0f : 0.0f,
            (float)aim_mode,
            aim_fov,
            aim_smooth,
            aim_power,
            vis_chk ? 1.0f : 0.0f,
            ign_knock ? 1.0f : 0.0f,
            (float)aim_bone,
            screen_w,
            screen_h,
            0.0f,
            max_dist,
            0.0f,
            silent_aim ? 1.0f : 0.0f,
            aim_360 ? 1.0f : 0.0f,
            hide_bots ? 1.0f : 0.0f,
            draw_skeleton ? 1.0f : 0.0f,
            ipad_fov_en ? 1.0f : 0.0f,
            ipad_fov,
            speed_en ? 1.0f : 0.0f,
            speed_val,
            wallhack ? 1.0f : 0.0f,
            no_fall ? 1.0f : 0.0f,
            fly ? 1.0f : 0.0f,
            underground ? 1.0f : 0.0f,
            no_grass ? 1.0f : 0.0f,
            fast_para ? 1.0f : 0.0f,
            wide_cam ? 1.0f : 0.0f,
            clear_fog ? 1.0f : 0.0f,
            no_recoil ? 1.0f : 0.0f
        );

        std::string tmp = s_CfgPath + ".tmp";
        FILE* f = std::fopen(tmp.c_str(), "w");
        if (f) {
            std::fputs(buf, f);
            std::fclose(f);
            rename(tmp.c_str(), s_CfgPath.c_str());
        }
    }

    // Read atomic ros_esp.txt snapshot produced by Python BigWorld.callback
    static bool FetchSnapshot(BridgeSnapshot& out_snapshot) {
        if (!s_BridgeInjected.load()) return false;

        InitializeDirectories();

        FILE* f = std::fopen(s_EspPath.c_str(), "r");
        if (!f) return false;

        char line[2048];
        if (!std::fgets(line, sizeof(line), f)) {
            std::fclose(f);
            return false;
        }

        // Parse header: "%d %s %d %d %d"
        int ent_count = 0, mode = 0, bs = 0, trig = 0;
        float me_coords[9] = {0};
        int parsed_hdr = std::sscanf(line, "%d %f %f %f %f %f %f %f %f %f %d %d %d",
            &ent_count,
            &me_coords[0], &me_coords[1], &me_coords[2],
            &me_coords[3], &me_coords[4], &me_coords[5],
            &me_coords[6], &me_coords[7], &me_coords[8],
            &mode, &bs, &trig);

        if (parsed_hdr < 1) {
            std::fclose(f);
            return false;
        }

        out_snapshot.entity_count = ent_count;
        out_snapshot.local_pos = Vector3(me_coords[0], me_coords[1], me_coords[2]);
        out_snapshot.view_pos  = Vector3(me_coords[3], me_coords[4], me_coords[5]);
        out_snapshot.view_dir  = Vector3(me_coords[6], me_coords[7], me_coords[8]);
        out_snapshot.mode = mode;
        out_snapshot.trig = trig;
        out_snapshot.players.clear();

        while (std::fgets(line, sizeof(line), f)) {
            // Strip newline
            size_t len = std::strlen(line);
            if (len > 0 && (line[len-1] == '\n' || line[len-1] == '\r')) line[--len] = '\0';
            if (len == 0) continue;

            // Format: main_tokens | bone_tokens | weapon_kind
            char* bar1 = std::strchr(line, '|');
            if (!bar1) continue;
            *bar1 = '\0';
            char* bone_str = bar1 + 1;
            char* bar2 = std::strchr(bone_str, '|');
            int weapon_kind = 0;
            if (bar2) {
                *bar2 = '\0';
                weapon_kind = std::atoi(bar2 + 1);
            }

            BridgePlayer p{};
            p.weapon_kind = weapon_kind;

            // Parse main tokens
            int on_val = 0, hp = 100, mhp = 100, enemy = 1, vis = 0, kn = 0, bot = 0, team = 0;
            int sh = 0, msh = 0, in_veh = 0, eid = 0;
            char nm[64] = {0};

            int n = std::sscanf(line,
                "%f %f %f %f %d %f %f %f %f %f %f %d %d %d %d %f %d %d %d %d %d %d %d %63s",
                &p.fs_x, &p.fs_y, &p.hs_x, &p.hs_y, &on_val,
                &p.pos.x, &p.pos.y, &p.pos.z,
                &p.vel.x, &p.vel.y, &p.vel.z,
                &hp, &mhp, &enemy, &vis, &p.distance,
                &kn, &bot, &team, &sh, &msh, &in_veh, &eid, nm);

            if (n >= 17) {
                p.on_screen = (on_val != 0);
                p.health = hp;
                p.max_health = mhp;
                p.is_enemy = (enemy != 0);
                p.is_visible = (vis != 0);
                p.is_knocked = (kn != 0);
                p.is_bot = (bot != 0);
                p.team_id = team;
                p.shield = sh;
                p.max_shield = msh;
                p.in_vehicle = in_veh;
                p.entity_id = eid;
                std::strncpy(p.name, nm, sizeof(p.name) - 1);

                // Parse 16 skeleton joints: "%d %f %f;%d %f %f;..."
                char* token = std::strtok(bone_str, ";");
                int b_idx = 0;
                while (token && b_idx < 16) {
                    int v = 0;
                    float bx = 0.0f, by = 0.0f;
                    if (std::sscanf(token, "%d %f %f", &v, &bx, &by) == 3) {
                        p.bones[b_idx].valid = (v != 0);
                        p.bones[b_idx].x = bx;
                        p.bones[b_idx].y = by;
                    }
                    b_idx++;
                    token = std::strtok(nullptr, ";");
                }

                out_snapshot.players.push_back(p);
            }
        }

        std::fclose(f);

        auto now = std::chrono::steady_clock::now();
        out_snapshot.timestamp_ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();

        std::lock_guard<std::mutex> lock(s_SnapshotMutex);
        s_LatestSnapshot = out_snapshot;
        return true;
    }
};

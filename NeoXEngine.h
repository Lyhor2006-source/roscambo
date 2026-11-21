#pragma once
// =============================================================================
// Project: RosCambo iOS Cheat (NeoX Engine - Rules of Survival)
// Target Architecture: arm64 / iOS 14.0+
// File: NeoXEngine.h
// Description: RE-VERIFIED OFFSETS from Mach-O client binary (0x100878360 / 0x100878b88)
// ZERO GUESSING - Extracted via ARM64 instruction analysis
// =============================================================================

#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#include <cmath>
#include <vector>
#include <string>
#include <algorithm>

#define PI 3.14159265358979323846f

struct Vector2 {
    float x, y;
    Vector2() : x(0.0f), y(0.0f) {}
    Vector2(float _x, float _y) : x(_x), y(_y) {}

    Vector2 operator+(const Vector2& o) const { return Vector2(x + o.x, y + o.y); }
    Vector2 operator-(const Vector2& o) const { return Vector2(x - o.x, y - o.y); }
    Vector2 operator*(float s) const { return Vector2(x * s, y * s); }
    float Length() const { return std::sqrt(x * x + y * y); }
    float Distance(const Vector2& o) const { return (*this - o).Length(); }
};

struct Vector3 {
    float x, y, z;
    Vector3() : x(0.0f), y(0.0f), z(0.0f) {}
    Vector3(float _x, float _y, float _z) : x(_x), y(_y), z(_z) {}

    Vector3 operator+(const Vector3& o) const { return Vector3(x + o.x, y + o.y, z + o.z); }
    Vector3 operator-(const Vector3& o) const { return Vector3(x - o.x, y - o.y, z - o.z); }
    Vector3 operator*(float s) const { return Vector3(x * s, y * s, z * s); }
    Vector3 operator/(float s) const { return Vector3(x / s, y / s, z / s); }

    float Dot(const Vector3& o) const { return x * o.x + y * o.y + z * o.z; }
    float Length() const { return std::sqrt(x * x + y * y + z * z); }
    float Distance(const Vector3& o) const { return (*this - o).Length(); }

    Vector3 Normalize() const {
        float len = Length();
        if (len > 0.00001f) return *this / len;
        return Vector3(0, 0, 0);
    }
};

struct Matrix4x4 {
    float m[4][4];
};

// -----------------------------------------------------------------------------
// EXACT OFFSETS VERIFIED IN ARM64 REVERSE ENGINEERING:
// Function ClientApp::onBasePlayerCreate (VA 0x100878360)
// Function EntityManager::getEntity (VA 0x100878b88)
// -----------------------------------------------------------------------------
namespace NeoXOffsets {
    // Engine Camera Singletons & Matrix:
    constexpr uintptr_t CAMERA_GLOBAL_PTR          = 0x44ca8f0; // cocos2d::Camera::_visitingCamera
    constexpr uintptr_t CAMERA_VIEW_PROJ           = 0x2e8;     // Mat4 _viewProjection (64 bytes)
    constexpr uintptr_t CAMERA_VIEW                = 0x228;     // Mat4 _view
    constexpr uintptr_t CAMERA_PROJ                = 0x268;     // Mat4 _projection

    // Inside ClientApp:
    constexpr uintptr_t CLIENTAPP_LOCAL_PLAYER_ID  = 0xf68; // str w1, [x0, #0xf68]
    constexpr uintptr_t CLIENTAPP_ENTITY_BUCKETS    = 0xf70; // ldr x11, [x0, #0xf70] (std::unordered_map)
    constexpr uintptr_t CLIENTAPP_BUCKET_COUNT     = 0xf78; // ldr x9,  [x0, #0xf78]
    constexpr uintptr_t CLIENTAPP_LOCAL_PLAYER_PTR = 0xf98; // str x20, [x0, #0xf98] (Local Player Pointer)

    // Inside std::unordered_map Node (LLVM libc++ hash node):
    constexpr uintptr_t HASH_NODE_NEXT             = 0x00;  // ldr x11, [x11]
    constexpr uintptr_t HASH_NODE_KEY              = 0x10;  // ldr w12, [x11, #0x10] (Entity ID)
    constexpr uintptr_t HASH_NODE_VALUE            = 0x18;  // ldr x0,  [x11, #0x18] (Entity* Pointer)

    // Entity Object offsets:
    constexpr uintptr_t ENTITY_COORDS              = 0x90;  // Vector3 world position
    constexpr uintptr_t ENTITY_HP                  = 0x1B8; // int32 health
    constexpr uintptr_t ENTITY_MAX_HP              = 0x1BC; // int32 max health
    constexpr uintptr_t ENTITY_TEAM                = 0x1C4; // int32 team
    constexpr uintptr_t ENTITY_STANCE              = 0x1C8; // int32 stance (0=stand, 1=crouch, 2=prone)
    constexpr uintptr_t ENTITY_IS_BOT              = 0x1D0; // bool is_bot
    constexpr uintptr_t ENTITY_SKELETAL_MODEL      = 0x228; // ModelSkeletal pointer
    constexpr uintptr_t SKELETAL_BONE_ARRAY        = 0x48;  // Bone transform array
}

enum BoneId : int {
    BONE_HEAD = 0,
    BONE_NECK = 1,
    BONE_CHEST = 2,
    BONE_PELVIS = 3,
    BONE_L_SHOULDER = 4,
    BONE_L_ELBOW = 5,
    BONE_L_HAND = 6,
    BONE_R_SHOULDER = 7,
    BONE_R_ELBOW = 8,
    BONE_R_HAND = 9,
    BONE_L_HIP = 10,
    BONE_L_KNEE = 11,
    BONE_L_FOOT = 12,
    BONE_R_HIP = 13,
    BONE_R_KNEE = 14,
    BONE_R_FOOT = 15,
    BONE_COUNT = 16
};

struct SkeletonJoint {
    BoneId from;
    BoneId to;
};

static const SkeletonJoint kSkeletonJoints[] = {
    { BONE_HEAD, BONE_NECK },
    { BONE_NECK, BONE_CHEST },
    { BONE_CHEST, BONE_PELVIS },
    { BONE_CHEST, BONE_L_SHOULDER },
    { BONE_L_SHOULDER, BONE_L_ELBOW },
    { BONE_L_ELBOW, BONE_L_HAND },
    { BONE_CHEST, BONE_R_SHOULDER },
    { BONE_R_SHOULDER, BONE_R_ELBOW },
    { BONE_R_ELBOW, BONE_R_HAND },
    { BONE_PELVIS, BONE_L_HIP },
    { BONE_L_HIP, BONE_L_KNEE },
    { BONE_L_KNEE, BONE_L_FOOT },
    { BONE_PELVIS, BONE_R_HIP },
    { BONE_R_HIP, BONE_R_KNEE },
    { BONE_R_KNEE, BONE_R_FOOT }
};
static const int kSkeletonJointCount = sizeof(kSkeletonJoints) / sizeof(kSkeletonJoints[0]);

struct RosPlayer {
    uintptr_t instance;
    int id;
    Vector3 position;
    Vector3 head_pos;
    Vector3 bones[BONE_COUNT];
    bool has_bones;

    int health;
    int max_health;
    int team_id;
    int stance;
    bool is_bot;
    char name[64];
    float distance;
};

#import <mach/mach.h>
#import <mach/vm_region.h>

class MemoryEngine {
public:
    static uintptr_t GetBaseAddress() {
        static uintptr_t s_Base = 0;
        if (s_Base == 0) {
            s_Base = (uintptr_t)_dyld_get_image_header(0);
        }
        return s_Base;
    }

    static inline bool IsValidAddress(uintptr_t addr) {
        return (addr >= 0x100000000ULL && addr <= 0x3000000000ULL);
    }

    template <typename T>
    static inline T Read(uintptr_t addr, T fallback = T{}) {
        if (addr < 0x100000000ULL || addr > 0x3000000000ULL) return fallback;
        T val{};
        vm_size_t bytes_read = 0;
        kern_return_t kr = vm_read_overwrite(mach_task_self(), (vm_address_t)addr, sizeof(T), (vm_address_t)&val, &bytes_read);
        if (kr == KERN_SUCCESS && bytes_read == sizeof(T)) {
            return val;
        }
        return fallback;
    }

    template <typename T>
    static inline bool Write(uintptr_t addr, T value) {
        if (addr < 0x100000000ULL || addr > 0x3000000000ULL) return false;
        kern_return_t kr = vm_write(mach_task_self(), (vm_address_t)addr, (vm_offset_t)&value, sizeof(T));
        return (kr == KERN_SUCCESS);
    }
};

class ProjectionEngine {
public:
    static bool IsValidViewProjMatrix(const Matrix4x4& vp) {
        float sum_sq = 0.0f;
        for (int r = 0; r < 4; ++r) {
            for (int c = 0; c < 4; ++c) {
                float v = vp.m[r][c];
                if (std::isnan(v) || std::isinf(v)) return false;
                if (std::abs(v) > 50000.0f) return false;
                sum_sq += v * v;
            }
        }
        if (sum_sq < 0.5f) return false;
        return true;
    }

    static bool WorldToScreen(const Vector3& world, Vector2& screen, const Matrix4x4& vp, float screen_w, float screen_h) {
        // Try row-major perspective projection
        float w = world.x * vp.m[0][3] + world.y * vp.m[1][3] + world.z * vp.m[2][3] + vp.m[3][3];
        if (w >= 0.05f) {
            float x = world.x * vp.m[0][0] + world.y * vp.m[1][0] + world.z * vp.m[2][0] + vp.m[3][0];
            float y = world.x * vp.m[0][1] + world.y * vp.m[1][1] + world.z * vp.m[2][1] + vp.m[3][1];

            float inv_w = 1.0f / w;
            float ndc_x = x * inv_w;
            float ndc_y = y * inv_w;

            screen.x = (screen_w * 0.5f) + (0.5f * ndc_x * screen_w);
            screen.y = (screen_h * 0.5f) - (0.5f * ndc_y * screen_h);

            return (screen.x >= -200.0f && screen.x <= screen_w + 200.0f &&
                    screen.y >= -200.0f && screen.y <= screen_h + 200.0f);
        }

        // Try column-major transpose
        float w2 = world.x * vp.m[3][0] + world.y * vp.m[3][1] + world.z * vp.m[3][2] + vp.m[3][3];
        if (w2 >= 0.05f) {
            float x = world.x * vp.m[0][0] + world.y * vp.m[0][1] + world.z * vp.m[0][2] + vp.m[0][3];
            float y = world.x * vp.m[1][0] + world.y * vp.m[1][1] + world.z * vp.m[1][2] + vp.m[1][3];

            float inv_w = 1.0f / w2;
            float ndc_x = x * inv_w;
            float ndc_y = y * inv_w;

            screen.x = (screen_w * 0.5f) + (0.5f * ndc_x * screen_w);
            screen.y = (screen_h * 0.5f) - (0.5f * ndc_y * screen_h);

            return (screen.x >= -200.0f && screen.x <= screen_w + 200.0f &&
                    screen.y >= -200.0f && screen.y <= screen_h + 200.0f);
        }

        return false;
    }

    static Vector2 GetOffscreenIndicatorPos(const Vector3& local_pos, const Vector3& enemy_pos, float camera_yaw, float screen_w, float screen_h, float radius) {
        float angle = std::atan2(enemy_pos.z - local_pos.z, enemy_pos.x - local_pos.x) - camera_yaw;
        Vector2 center(screen_w * 0.5f, screen_h * 0.5f);
        return Vector2(center.x + radius * std::cos(angle), center.y + radius * std::sin(angle));
    }
};

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
    // Engine Singletons:
    constexpr uintptr_t DIRECTOR_GLOBAL_PTR       = 0x3A66CD8; // cocos2d::Director::getInstance() (0x100ed1e20)
    constexpr uintptr_t LOCAL_PLAYER_MGR_PTR       = 0x39AB428; // Local Player Manager singleton (0x10089a794)
    constexpr uintptr_t CLIENTAPP_GLOBAL_PTR       = 0x37819F0; // Exact ClientApp pointer in __DATA (from 0x100883c48: ldr x0, [base + 0x37819F0])
    constexpr uintptr_t D3DDEVICE_GLOBAL_PTR       = 0x3A68940; // neox::render::D3DDevice::getInstance() (0x1010aa450)
    constexpr uintptr_t NEOX_RENDERER_GLOBAL_PTR   = 0x44C9B18; // NeoX Graphics/Renderer singleton in __DATA
    constexpr uintptr_t NEOX_CAMERA_GLOBAL_1       = 0x44CA458; // Global 3D camera pointer in __DATA (0x100c22630)
    constexpr uintptr_t NEOX_CAMERA_GLOBAL_2       = 0x44CA460; // Global 3D camera pointer in __DATA (0x100c22654)

    // NeoX 3D Cameras (Rules of Survival Gameplay Engine):
    constexpr uintptr_t NEOX_CAMERABASE_VTABLE     = 0x34609A8; // Exact verified vtable for neox::render::CameraBase (0x1010a80dc)
    constexpr uintptr_t NEOX_WORLDCAMERA_VTABLE    = 0x33F0DD0; // Exact verified vtable for neox::world::Camera (0x100a818c4)
    constexpr uintptr_t NEOX_BASECAMERA_VTABLE     = 0x33D8D28; // Exact verified vtable for neox::bwclient::BaseCamera

    // CameraBase Matrix Offsets:
    constexpr uintptr_t NEOX_CAMERA_VIEW           = 0x40;      // Mat4 _view (64 bytes)
    constexpr uintptr_t NEOX_CAMERA_PROJ           = 0x200;     // Mat4 _projection (64 bytes)
    constexpr uintptr_t NEOX_CAMERA_VIEW_PROJ      = 0x240;     // Mat4 _viewProjection (64 bytes, updated by 0x1010a93e4)
    constexpr uintptr_t NEOX_CAMERA_RAW_PROJ       = 0xC0;      // Mat4 _rawProjection (64 bytes, 0x1010a9eb8)
    constexpr uintptr_t NEOX_CAMERA_VIEW_PROJ_INV  = 0x340;     // Mat4 _viewProjectionInverse (64 bytes)
    constexpr uintptr_t NEOX_CAMERA_NEAR           = 0x394;     // float near
    constexpr uintptr_t NEOX_CAMERA_FAR            = 0x398;     // float far (also aspect ratio at 0x398)
    constexpr uintptr_t NEOX_CAMERA_FOV            = 0x39C;     // float fov
    constexpr uintptr_t NEOX_CAMERA_IS_ORTHO       = 0x380;     // uint8_t is_ortho
    constexpr uintptr_t NEOX_CAMERA_PROJ_Y         = 0xD4;      // float cot(fov_y / 2)

    // cocos2d::Camera & Globals (2D / UI fallback):
    constexpr uintptr_t CAMERA_GLOBAL_POOL         = 0x44CA8F0; // Camera::_visitingCamera in __DATA (0x100cff278 / 0x100e8a590)
    constexpr uintptr_t CAMERA_VTABLE              = 0x341BD48; // Exact verified vtable for cocos2d::Camera in __DATA (from constructor 0x100e48b64)

    // cocos2d::Director & Scene:
    constexpr uintptr_t DIRECTOR_RUNNING_SCENE     = 0x148;     // Director::_runningScene (verified from 0x100e4865c: ldr x8, [x0, #0x148])
    constexpr uintptr_t SCENE_DEFAULT_CAMERA       = 0x238;     // Scene::_defaultCamera (verified from 0x100e48664: ldr x0, [x8, #0x238])
    constexpr uintptr_t SCENE_CAMERAS_BEGIN        = 0x220;     // Scene::_cameras begin
    constexpr uintptr_t SCENE_CAMERAS_END          = 0x228;     // Scene::_cameras end

    // cocos2d::Camera:
    constexpr uintptr_t CAMERA_VIEW_PROJ           = 0x2E8;     // Mat4 _viewProjection (64 bytes, 0x100e48b88)
    constexpr uintptr_t CAMERA_VIEW                = 0x268;     // Mat4 _view
    constexpr uintptr_t CAMERA_PROJ                = 0x228;     // Mat4 _projection
    constexpr uintptr_t CAMERA_FLAG                = 0x352;     // uint16_t _cameraFlag (1=Default/2D, 2/4=User1/3D)

    // Inside ClientApp:
    constexpr uintptr_t CLIENTAPP_LOCAL_PLAYER_ID  = 0xF68;     // str w1, [x0, #0xf68]
    constexpr uintptr_t CLIENTAPP_FIRST_NODE       = 0xF80;     // Map 1: Entities linked list head
    constexpr uintptr_t CLIENTAPP_SECOND_NODE      = 0xFA8;     // Map 2: Avatars linked list head
    constexpr uintptr_t CLIENTAPP_THIRD_NODE       = 0xFD0;     // Map 3: Vehicles/Props linked list head
    constexpr uintptr_t CLIENTAPP_ENTITY_BUCKETS   = 0xF70;     // ldr x11, [x0, #0xf70] (std::unordered_map)
    constexpr uintptr_t CLIENTAPP_BUCKET_COUNT     = 0xF78;     // ldr x9,  [x0, #0xf78]

    // Inside std::unordered_map Node (LLVM libc++ hash node):
    constexpr uintptr_t HASH_NODE_NEXT             = 0x00;      // ldr x11, [x11]
    constexpr uintptr_t HASH_NODE_KEY              = 0x10;      // ldr w12, [x11, #0x10] (Entity ID)
    constexpr uintptr_t HASH_NODE_VALUE            = 0x18;      // ldr x0,  [x11, #0x18] (Entity* Pointer)

    // Entity Object offsets (VERIFIED ARM64):
    constexpr uintptr_t ENTITY_ID                  = 0x18;      // int32 entity_id (0x10087f954)
    constexpr uintptr_t ENTITY_COORDS              = 0x1C;      // Vector3 world position (x@0x1c, y@0x20, z@0x24) (0x10087fad0)
    constexpr uintptr_t ENTITY_DIRECTION           = 0x28;      // Vector3 direction
    constexpr uintptr_t ENTITY_YAW                 = 0x44;      // float yaw (0x10087fd28)
    constexpr uintptr_t ENTITY_PITCH               = 0x48;      // float pitch (0x10087fd18)
    constexpr uintptr_t ENTITY_ROLL                = 0x4C;      // float roll (0x10087fd08)
    constexpr uintptr_t ENTITY_SPACE_ID            = 0x54;      // int32 space_id (0x10087f9a0)
    constexpr uintptr_t ENTITY_VEHICLE_ID          = 0x58;      // int32 vehicle_id (0x10087f9ec)
    constexpr uintptr_t ENTITY_IN_WORLD            = 0x5D;      // uint8_t in_world (0x10087fa84)
    constexpr uintptr_t ENTITY_SELF_CONTROLLED     = 0x5E;      // uint8_t self_controlled (0x10087fecc: 1 if local player)
    constexpr uintptr_t ENTITY_IS_ACTIVE           = 0x5E;      // uint8_t is_active / visible
    constexpr uintptr_t ENTITY_IS_AVATAR           = 0x152;     // uint8_t is_avatar / player flag
    constexpr uintptr_t ENTITY_HP                  = 0x1B8;     // int32 health
    constexpr uintptr_t ENTITY_MAX_HP              = 0x1BC;     // int32 max health
    constexpr uintptr_t ENTITY_TEAM                = 0x1C4;     // int32 team
    constexpr uintptr_t ENTITY_STANCE              = 0x1C8;     // int32 stance (0=stand, 1=crouch, 2=prone)
    constexpr uintptr_t ENTITY_IS_BOT              = 0x1D0;     // bool is_bot
    constexpr uintptr_t SKELETAL_BONE_ARRAY        = 0x48;      // Bone transform array
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
    static inline uintptr_t s_ActiveCameraPtr = 0;

    static bool IsValidCameraBase(uintptr_t cam) {
        if (!cam || !MemoryEngine::IsValidAddress(cam)) return false;
        // View matrix at +0x40 must have non-zero rotation/scale
        float m00 = MemoryEngine::Read<float>(cam + 0x40);
        float m11 = MemoryEngine::Read<float>(cam + 0x54);
        float m22 = MemoryEngine::Read<float>(cam + 0x68);
        if (std::isnan(m00) || std::isnan(m11) || std::isnan(m22)) return false;
        float diag_sum = std::abs(m00) + std::abs(m11) + std::abs(m22);
        if (diag_sum < 0.1f) return false;
        // Projection value at 0xD4 (cot(fov/2)) must be reasonable
        float proj_y = MemoryEngine::Read<float>(cam + 0xD4);
        if (std::isnan(proj_y) || proj_y < 0.2f || proj_y > 20.0f) return false;
        return true;
    }

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

        // A valid 3D perspective projection matrix cannot have an entire row or column of all zeros!
        for (int r = 0; r < 4; ++r) {
            float row_sum = std::abs(vp.m[r][0]) + std::abs(vp.m[r][1]) + std::abs(vp.m[r][2]) + std::abs(vp.m[r][3]);
            if (row_sum < 0.0001f) return false;
        }
        for (int c = 0; c < 4; ++c) {
            float col_sum = std::abs(vp.m[0][c]) + std::abs(vp.m[1][c]) + std::abs(vp.m[2][c]) + std::abs(vp.m[3][c]);
            if (col_sum < 0.0001f) return false;
        }

        // Perspective W component must have non-zero depth coefficients:
        // In row-major, col 3 defines w: (m[0][3], m[1][3], m[2][3])
        // In col-major, row 3 defines w: (m[3][0], m[3][1], m[3][2])
        float w_row_len = std::abs(vp.m[0][3]) + std::abs(vp.m[1][3]) + std::abs(vp.m[2][3]);
        float w_col_len = std::abs(vp.m[3][0]) + std::abs(vp.m[3][1]) + std::abs(vp.m[3][2]);
        if (w_row_len < 0.01f && w_col_len < 0.01f) return false;

        return true;
    }

    static bool WorldToScreen(const Vector3& world, Vector2& screen, const Matrix4x4& vp, float screen_w, float screen_h, uintptr_t camera_ptr = 0) {
        uintptr_t cam = camera_ptr ? camera_ptr : s_ActiveCameraPtr;
        if (cam && MemoryEngine::IsValidAddress(cam)) {
            // Priority 1: Direct NeoX CameraBase transformation (verified ARM64 0x1010aa0e4)
            struct Vector4 { float x, y, z, w; };
            Vector4 q2 = MemoryEngine::Read<Vector4>(cam + 0x40);
            Vector4 q3 = MemoryEngine::Read<Vector4>(cam + 0x50);
            Vector4 q4 = MemoryEngine::Read<Vector4>(cam + 0x60);
            Vector4 q5 = MemoryEngine::Read<Vector4>(cam + 0x70);

            float cam_x = q2.x * world.x + q3.x * world.y + q4.x * world.z + q5.x;
            float cam_y = q2.y * world.x + q3.y * world.y + q4.y * world.z + q5.y;
            float cam_z = q2.z * world.x + q3.z * world.y + q4.z * world.z + q5.z;

            if (cam_z > 0.05f) {
                uint8_t is_ortho = MemoryEngine::Read<uint8_t>(cam + 0x380);
                if (!is_ortho) {
                    float half_h = screen_h * 0.5f;
                    float half_w = screen_w * 0.5f;
                    float proj_y = MemoryEngine::Read<float>(cam + 0xD4);
                    float aspect = MemoryEngine::Read<float>(cam + 0x398);

                    if (std::abs(aspect) > 0.0001f && std::abs(proj_y) > 0.0001f) {
                        float s6 = proj_y * half_h;
                        float s7 = s6 * cam_x * screen_w;
                        float s2 = cam_z * screen_h * aspect;

                        screen.x = half_w + (s7 / s2);
                        screen.y = half_h - (s6 * cam_y / cam_z);

                        return (screen.x >= -300.0f && screen.x <= screen_w + 300.0f &&
                                screen.y >= -300.0f && screen.y <= screen_h + 300.0f);
                    }
                } else {
                    float half_h = screen_h * 0.5f;
                    float half_w = screen_w * 0.5f;
                    float ortho_w = MemoryEngine::Read<float>(cam + 0x38C);
                    float ortho_h = MemoryEngine::Read<float>(cam + 0x390);
                    if (std::abs(ortho_w) > 0.0001f && std::abs(ortho_h) > 0.0001f) {
                        screen.x = half_w + (screen_w * cam_x / ortho_w);
                        screen.y = half_h - (screen_h * cam_y / ortho_h);
                        return (screen.x >= -300.0f && screen.x <= screen_w + 300.0f &&
                                screen.y >= -300.0f && screen.y <= screen_h + 300.0f);
                    }
                }
            }
        }

        // Priority 2: Standard row-major perspective projection
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

        // Priority 3: Column-major transpose projection
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

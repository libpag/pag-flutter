#include <cstdint>
#include <hilog/log.h>
#include <napi/native_api.h>
#include <native_window/external_window.h>

#define TAG "flutter_ohos_texture_patch"
#define LOGI(fmt, ...) OH_LOG_INFO(LOG_APP, fmt, ##__VA_ARGS__)

/**
 * workaround for OHOSExternalTextureGL::setTextureBufferSize
 * !!! [ERROR:flutter/shell/platform/ohos/ohos_external_texture_gl.cpp(332)] OHOSExternalTextureGL::SetTextureBufferSize
 * OH_NativeWindow_NativeWindowHandleOpt err:40001000
 */
static void setTextureBufferSize(int64_t surfaceId, int32_t width, int32_t height) {
    OHNativeWindow *nativeWindow;
    int32_t ret = OH_NativeWindow_CreateNativeWindowFromSurfaceId(surfaceId, &nativeWindow);
    LOGI("flutter_ohos_texture_patch::setTextureBufferSize surfaceId=%ld; nativeWindow=%p; width=%d; height=%d; "
         "ret=%d; ",
         surfaceId, nativeWindow, width, height, ret);
    if (ret == 0 && nativeWindow) {
        ret = OH_NativeWindow_NativeWindowHandleOpt(nativeWindow, SET_BUFFER_GEOMETRY, width, height);
        LOGI("flutter_ohos_texture_patch::OH_NativeWindow_NativeWindowHandleOpt SET_BUFFER_GEOMETRY ret=%d", ret);
    }
}

static napi_value setTextureBufferSize(napi_env env, napi_callback_info info) {
    LOGI("flutter_ohos_texture_patch::setTextureBufferSize ...");
    size_t argc = 3;
    napi_value args[3] = {nullptr};

    napi_status status = napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (status != napi_ok) {
        return nullptr;
    }

    int64_t surfaceId{0};
    bool lossless = false;
    status = napi_get_value_bigint_int64(env, args[0], &surfaceId, &lossless);

    int32_t width{0}, height{0};
    status = napi_get_value_int32(env, args[1], &width);
    status = napi_get_value_int32(env, args[2], &height);

    setTextureBufferSize(surfaceId, width, height);

    return 0;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"setTextureBufferSize", nullptr, setTextureBufferSize, nullptr, nullptr, nullptr, napi_default, nullptr}};
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module flutter_ohos_texture_patch = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "flutter_ohos_texture_patch",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
    napi_module_register(&flutter_ohos_texture_patch);
}

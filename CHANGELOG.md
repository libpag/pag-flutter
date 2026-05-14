## 1.0.10
* 修复 Flutter 3.27+ 上 Impeller(Vulkan) 后端在 App 进入后台 / 低内存场景下崩溃的问题
  （`Unable to allocate Vulkan Image: ErrorInitializationFailed` → `Check failed: back_texture`）。
  原因是没有为 `SurfaceProducer` 注册生命周期回调，Surface 被 Flutter 销毁后插件仍持有失效的
  `PAGSurface` 继续 flush。现在监听 `onSurfaceCreated/onSurfaceDestroyed`，在销毁时暂停动画
  并释放旧的 `PAGSurface`，恢复时重建并继续渲染。

## 1.0.8
* 增加相同资源路径则复用的功能，可设置关闭

## 1.0.7
* 修复1.0.6安卓代码未正确包含的问题

## 1.0.6
* 提升libpag库版本
* 安卓库提升kotlin-gradle-plugin版本
* 安卓原生侧添加缓存，加快加载速度
* 安卓原生侧支持多线程，优化卡顿情况
* ！！！未正确发布，不可用！！！

## 1.0.5
* 增加鸿蒙支持

## 1.0.4
* 增加展位图参数

## 1.0.3
* 删除gradle无用引用

## 1.0.2
* 修正Android repeatCount空异常

## 1.0.1
* 修正命名规范的疏漏，podspec未修改

## 1.0.0
* 封装PAG动画使用方式
* 支持二进制、网络连接、资源文件等加载方式
* 提供动画流程中的事件监听，与原生API一致


# 校园地图性能对比

缓存底图默认启用。手势期间平移、缩放带少量预绘制边缘的底图图层，
选中高亮和定位标记单独绘制。拖到缓存边缘、缩放超过阈值或手势结束时刷新底图。
这避免为整张校区地图分配当前放大倍率下的大纹理；缩放途中仍可能暂时模糊。

只关闭缓存图层，保留其他修改：

```sh
flutter run --profile --dart-define=CAMPUS_MAP_CACHED_GESTURES=false
```

恢复缓存时省略该参数，或将其设为 `true`。
缓存图层单独提交，必要时也可以独立撤回该提交。

在同一设备、同一校区和放大倍率下比较连续拖动、双指缩放、搜索定位，
并检查底图与选中高亮是否一致、是否出现空白边缘。

单指拖动以最近 80 ms 的输入估计速度，松手后按时间积分减速。
双指操作、长按后松手、取消手势、再次触摸、搜索定位、尺寸变化和后台切换
不会沿用旧的惯性；系统要求减少动态效果时不启用惯性。
高频触摸和滚轮事件只在下一帧计算一次镜头变化。

## Android 合成模式

默认显式选择 Texture Layer Hybrid Composition，延续原插件默认行为。
保持缓存配置相同，用以下参数对比 Hybrid Composition：

```sh
flutter run --profile --dart-define=CAMPUS_MAP_ANDROID_HYBRID_COMPOSITION=true
```

将参数设为 `false` 或省略即可恢复纹理模式。
两种模式各有开销，不能仅凭单元测试认定其中一种在设备上更快。
记录设备型号、Android 与 Android System WebView 版本、屏幕刷新率，
在同一缩放倍率下对比持续拖动、快速滑动、双指缩放，以及显示详情面板时的表现。

如果设备为 Android 14/API 34 以上、支持 Vulkan，且应用使用 Impeller，
Flutter 3.44 以上还可单独对比实验性的 HCPP：

```sh
flutter run --profile --enable-hcpp
```

该命令只是本地评估入口，没有更改应用全局 manifest；不满足条件时由 Flutter 回退。
参考：[插件显示模式](https://pub.dev/packages/webview_flutter_android#display-mode)、
[Flutter Android Platform Views](https://docs.flutter.dev/platform-integration/android/platform-views)。

## 回归测试

键盘只改变搜索覆盖层的可见高度，地图和详情面板保留完整尺寸与底部安全区。
搜索遮住地图时暂停惯性、绘制和调试上报；返回地图复用现有 WebView 和底图。
点击提示、无结果区域或列表空白会一次关闭搜索并收起键盘；
点击结果选择地点，拖动列表则只收起键盘并保留查询与结果。

```sh
flutter test
```

其中 `campus_map_javascript_test.dart` 在安装了 Node.js 的环境中，
使用无外部依赖的 DOM 和时钟替身运行实际画布脚本的回归测试。
没有 Node.js 时只跳过该项，Dart/widget 测试仍照常执行。
这些测试检查坐标、缓存刷新和调度逻辑，不能证明 GPU 缓存是否生效或真机帧率。

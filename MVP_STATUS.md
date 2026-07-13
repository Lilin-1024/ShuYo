# MVP Status

## 已完成

- 创建 Flutter 源码包 `lehu_client/`。
- 已生成 Android / iOS / Windows 平台目录。
- 建立分层目录：
  - `lib/app`
  - `lib/core`
  - `lib/data/models`
  - `lib/data/repositories`
  - `lib/data/services`
  - `lib/features`
  - `lib/shared/widgets`
- 复制当前 MVP 所需 fixtures 到 `assets/fixtures/`。
- 实现默认深色主题。
- 实现固定顶部栏：
  - 返回按钮
  - 页面标题
  - 通知入口
  - “我”页设置入口
- 实现固定底部 Tab：
  - 最新
  - 热点
  - 消息
  - 我
- 实现最新/热点列表。
- 实现分区名称与颜色映射。
- 实现首楼正文纯文本摘要。
- 实现帖子详情页。
- 实现图片内容展示。
- 实现消息占位页。
- 实现个人 summary 页面。
- 个人 summary 已改为简洁列表布局，避免小屏 overflow。
- 顶部标题在无返回键时与内容区域左侧对齐。
- 实现评论主题、回复某一楼、点赞的请求 payload 构造。
- 接入 WebView 登录页：
  - 未登录时从“我”、通知、设置、评论、点赞入口进入登录。
  - 登录成功并看到论坛页面后，点击“完成”重载客户端数据。
- 接入真实 Discourse API repository：
  - `GET /session/current.json`
  - `GET /latest.json`
  - `GET /hot.json`
  - `GET /t/topic/{id}.json`
  - `GET /site.json`
  - `GET /u/{username}/summary.json`
- 实现 WebView Cookie 复用。
- 实现 CSRF Token 获取。
- 实现真实评论、回复某一楼、点赞 POST。
- 设置页和通知页已接入 WebView 兜底。
- 顶部通知图标已接入当前用户未读角标。
- 列表摘要改为按需加载 topic 详情后生成首楼纯文本摘要。
- Android 已加入网络权限。
- 关闭 Kotlin incremental，避免 Windows 跨盘 Pub cache 导致的 WebView Kotlin 编译噪音。
- 临时允许 `bbs.shu.edu.cn` 的过期证书通过，用于论坛证书续签前的 MVP 测试；统一认证域名不绕过证书错误。
- Flutter 图片请求也复用同一套限域名证书策略，修复论坛图片因过期证书加载失败的问题。
- 登录 WebView 在完成统一认证并回到论坛首页后会自动返回客户端。
- 评论/回复/点赞失败时会优先展示论坛返回的具体错误信息。
- 评论、回复、点赞、删除已加入操作中状态，避免重复点击造成重复请求。
- 评论、点赞、删除失败时会用弹窗展示论坛返回的具体原因。
- 帖子详情会过滤 Discourse 图片附件的文件名、尺寸和大小信息。
- 帖子详情支持图片点击查看大图，并可双指缩放。
- 帖子详情评论区已改为单层嵌套：
  - 回复某一楼的评论显示在目标楼层下方。
  - 回复的回复归入同一个回复区。
  - 回复过多时默认折叠，可点击查看更多。
- 自己发送且论坛允许删除的回复会显示删除按钮。
- 接入删除回复接口：`DELETE /posts/{post.id}`。
- 最新/热点列表支持展示首楼图片预览：
  - 单图按原比例缩放。
  - 多图显示方形缩略图，一行最多三张。
  - 超过三张时在第三张右上角显示总数角标。
- 最新/热点列表已支持上拉加载更多，使用 `more_topics_url` 获取下一页。
- “我”页已加入重新登录和退出登录入口。
- 登录失效时会清理登录态并提示重新登录。
- 增加纯 Dart 验证脚本 `tool/verify_fixtures.dart`。

## 当前限制

- 启动时会先加载本地 fixtures，再尝试读取 WebView Cookie 接入真实论坛；没有登录态时会停留在本地样例模式。
- 当前没有持久化自定义 session，登录态依赖 WebView/系统 Cookie。
- 当前包含临时证书兼容策略，论坛管理员续签证书后应关闭。
- 评论、点赞、删除已接真实接口；删除还需要等账号回复限额恢复后做一次端到端验证。
- 列表摘要会对可见帖子按需请求 topic 详情；后续可根据流量表现优化预取策略。
- 消息页按设计先占位。
- 原生通知列表、原生私信列表、原生设置页暂未实现。
- 图片上传暂未实现。

## 已验证

```text
D:\Project\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe analyze lib\core lib\data\models lib\data\services tool\verify_fixtures.dart
D:\Project\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe tool\verify_fixtures.dart
D:\Project\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe format lib\data\models\post.dart lib\data\services\payload_factory.dart lib\data\services\discourse_api_client.dart lib\data\services\html_text.dart lib\data\repositories\forum_repository.dart lib\features\topic\threaded_posts.dart lib\features\topic\topic_page.dart lib\features\home\topic_list_page.dart lib\features\profile\profile_page.dart lib\app\app_shell.dart test\model_parsing_test.dart
D:\Project\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe analyze
dart run tool\verify_fixtures.dart
flutter analyze
flutter test
flutter build apk --debug
```

结果：

```text
No issues found!
Fixtures verified: 30 latest, 30 hot, 12 categories.
dart analyze: No issues found!
flutter analyze: No issues found!
flutter test: All tests passed!
flutter build apk --debug: Built build\app\outputs\flutter-apk\app-debug.apk
```

## 模拟器测试步骤

1. 连接校园网或 VPN。
2. 启动模拟器后运行：

```text
flutter run
```

3. 进入“我”页，点击“登录乐乎”。
4. 在 WebView 中完成学校统一认证和二步验证。
5. 登录后如果 WebView 显示论坛页面，点击右上角“完成”。
6. 客户端应显示真实“最新”列表。
7. 打开一个帖子，检查正文、图片、评论楼层是否正常。
8. 用测试内容回复一个低风险帖子，确认论坛网页端能看到新回复。
9. 回复某一楼，确认回复会显示到目标楼层下方。
10. 点赞一楼或评论楼层，确认点赞数和按钮状态刷新。
11. 删除自己刚发送且可删除的回复，确认论坛网页端同步删除。

## 下一步

1. 做发新主题功能，需要先补充网页端抓包材料。
2. 做原生通知列表或消息 Tab 的 WebView 兜底。
3. 准备 App 名称、图标、启动页和 Release 签名。
4. 后续再开始图片上传。

# Kaneo App

Kaneo 的 Flutter 客户端，覆盖 iOS、iPadOS、Android、macOS、Windows、Linux。服务端和网页端不在本仓库，也不会被替换。

本仓库是公开的。不要提交服务器地址、账号、API Key 和签名文件。

## 开工前读什么

1. `kaneo show <任务> --context`：任务、父需求和评论
2. `kaneo show KAN-1`：产品范围、录屏发现、已定决定和执行方案
3. 按需读参考代码：功能和接口看 `kaneo/apps/mobile`，宽屏的交互和视觉看 `kaneo/apps/web`，服务端行为看 `kaneo/apps/api` 和 `kaneo/apps/docs/openapi.json`

新建工作目录后 `kaneo/` 是空的，先运行 `git submodule update --init --depth 1 kaneo`。`kaneo/` 只作参考，不在里面改代码，里面的 `AGENTS.md` 也不是本仓库的规则。构建和测试都不依赖它。

## 领取任务

一期的卡片都在「已计划」。先运行 `kaneo claim <任务> --named`。只有拒绝原因仅为「任务在 已计划」时才加 `--force`。依赖未完成等其他原因按被拒绝处理，不要强制，先做线内下一条，都做不了时报告主 Agent。

所有 Worker 共用一个账号，不要用 `kaneo next` 取任务，按 `KAN-1` 执行方案里的顺序领取。

## 产品规则

- 纯 Flutter，不用 WebView
- 只有宽屏和窄屏两套布局，按窗口较短边判断，600 及以上为宽屏
- 看板所有端都是多列，只有手机进入看板时自动横屏；其他页面不锁方向
- 描述编辑是纯文本框，不能改动用户没编辑的 Markdown 内容
- 不做快捷键、命令面板、批量选择
- 登录只做自托管服务器的账号密码和 API Key
- 优先保证 iOS、iPadOS、macOS 可用。Android、Windows、Linux 只要求 CI 构建和自动化测试通过，界面和安装由管理员最后验收

## 目录和分工

| 目录 | 标签 |
| --- | --- |
| `lib/core/`、`lib/features/shell/`、`lib/features/home/`、`lib/features/inbox/`、`lib/features/activity/`、`lib/features/search/`、`lib/features/notifications/` | A-框架 |
| `lib/features/board/` | B-看板 |
| `lib/features/task/`、`lib/features/markdown/` | C-任务 |
| `lib/features/auth/`、`lib/platform/`、`.github/`、各平台目录 | D-平台 |

## 共用入口

页面只导入 `package:kaneo_app/core/core.dart`，下面这些都从它导出。

| 要做什么 | 用什么 |
| --- | --- |
| 读数据 | `lib/core/data/queries.dart`（`boardQuery`、`projectsQuery`、`taskQuery` 等），配合 `AsyncBody` 显示加载中、错误、无权限、空数据 |
| 写数据 | `ref.read(kaneoApiProvider)`，配合 `runAction()` 提示失败原因 |
| 新增缓存查询 | `cachedQuery`、`cachedQueryFamily` |
| 文案 | `context.t('mobile:nav.home')`，复数传 `{'count': n}` |
| 颜色和字体 | `context.colors`（网页端的主题变量）、`KaneoFonts`、`KaneoRadius` |
| 宽屏还是窄屏 | `context.isWide` |
| 路由 | `AppRoutes` |
| 提示、确认框、菜单 | `showToast`、`showGlobalToast`、`showConfirm`、`showActionMenu` |
| 右键或长按打开菜单 | `ContextMenuRegion` |
| 自定义浮层和弹窗 | `showPopover`（宽屏就近浮层，窄屏底部弹层）、`showPanel`（宽屏居中弹窗，窄屏全屏页） |
| 选择器 | `pickOption`、`pickMany`、`pickStatus`、`pickPriority`、`pickAssignee`、`pickLabels`、`pickDate` |
| 打开任务、新建任务 | `lib/features/task/open_task.dart` 的 `openTask()`、`openNewTask()` |
| 显示 Markdown | `lib/features/markdown/markdown_view.dart` 的 `MarkdownView` |

文案的查找顺序：当前语言的覆盖文件、当前语言的目录、英语覆盖文件、英语目录。`assets/i18n/*.json` 从 `kaneo/i18n/` 复制，不要改。新增文案放 `assets/i18n/overrides/`，命名空间用 `app`，至少写 `en-US`、`zh-CN`、`zh-TW`。

## 并行规则

- 一条线用一个工作目录，每个任务从最新的 `origin/main` 建分支。线内任务按顺序做
- 只改自己这条线的目录。需要别的线改动时，在对方任务下评论
- `lib/core/` 只能增加，不改已有调用的参数
- 看板打开任务一律调用 `openTask()`，选择器、菜单、确认框、提示一律用 `lib/core/` 的入口
- 新增文案放 App 自己的覆盖文件，不改子模块
- 开发和测试连本地 Kaneo，不连团队线上服务器，不用生产数据和密钥。开发配置放 `~/.config/kaneo-app/dev.env`，不进仓库
- 线上验证只在任务明确要求时做。账号读本机 `~/.config/kaneo-app/real-server.env`，只在其中 `KANEO_REAL_TEST_PROJECT` 指定的项目里操作，不碰其他项目和已有卡片。这个文件的内容不写进仓库、评论和日志

## 这台机器的限制

只有 16 GB 内存，几个 agent 同时工作。

- 平时只跑 `flutter analyze` 和 `flutter test`，不开模拟器
- iOS 模拟器和完整构建必须用 `tool/with_device.sh` 排队，同一时间只运行一个，用完关闭。不开 Android 模拟器
- 用 `--boot` 启动的模拟器，`tool/with_device.sh` 结束时会关闭。别的模拟器不是你的，不要关，也不要用 `xcrun simctl shutdown all`
- `tool/with_device.sh` 拿到队列后默认最多运行 20 分钟（排队时间不算），超时后杀掉它启动的进程组、释放队列，以退出码 124 结束。确实要跑更久时用 `KANEO_DEVICE_TIMEOUT=<秒数>`

macOS 设备测试每条线使用自己固定的测试 bundle ID，并保持本地签名身份一致：A 线 `app.kaneo.kaneoApp.ATest`、B 线 `app.kaneo.kaneoApp.BTest`、C 线 `app.kaneo.kaneoApp.CTest`、D 线 `app.kaneo.kaneoApp.DTest`。通过本次命令的 `FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER` 环境变量覆盖，不改仓库里的正式 bundle ID，也不要把测试覆盖带进分发构建。不同签名共用同一个 macOS 应用容器可能卡在 `_libsecinit_appsandbox`，测试不会自行退出，还会一直占用设备队列。

## 常用命令

```bash
flutter pub get
flutter analyze
flutter test                                     # 全量，不需要本地 Kaneo
flutter test test/features/pages_test.dart       # 单个文件
dart format lib test tool integration_test       # 行宽 100，写在 analysis_options.yaml

# 下面的都要排队
tool/with_device.sh flutter build macos --debug
tool/with_device.sh --boot "iPhone 17" flutter test integration_test -d "iPhone 17" \
  --dart-define-from-file=$HOME/.config/kaneo-app/dev.env
tool/with_device.sh --boot "iPad Pro 13-inch (M5)" flutter test integration_test -d "iPad Pro 13-inch (M5)" \
  --dart-define-from-file=$HOME/.config/kaneo-app/dev.env
# macOS 示例用 D 线 ID，其他线替换成自己的固定 ID
FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER=app.kaneo.kaneoApp.DTest \
  tool/with_device.sh flutter test integration_test -d macos \
  --dart-define-from-file=$HOME/.config/kaneo-app/dev.env
```

`flutter test` 不会跑 `integration_test/`。CI 在推送到 `main` 和 `ci/**` 时运行，要在推送 `main` 之前检查 CI 能不能过，可以先推到 `ci/<任务>`，确认后删掉这个分支。

## 本地 Kaneo

用 Homebrew 的 Postgres 和 pnpm，只启动 API，不启动网页端和文档站。所有工作目录共用一份。

```bash
brew install postgresql@17 node@24 pnpm   # 只需一次
tool/local_kaneo.sh setup    # 只需一次：下载子模块对应版本的源码，装依赖，建数据库
tool/local_kaneo.sh start    # 启动 Postgres 和 API，等到健康检查通过
tool/local_kaneo.sh seed     # 只需一次：建开发账号、API Key 和示例数据，写入 dev.env
tool/local_kaneo.sh status
tool/local_kaneo.sh stop     # 用完就停，省内存
```

服务端配置在 `~/.config/kaneo-app/api.env`，数据和日志在 `~/.local/share/kaneo-app/`。

`~/.config/kaneo-app/dev.env` 的字段：

| 字段 | 说明 |
| --- | --- |
| `KANEO_DEV_SERVER_URL` | 本地 API 地址 |
| `KANEO_DEV_API_KEY` | 开发账号的 API Key |
| `KANEO_DEV_EMAIL`、`KANEO_DEV_PASSWORD` | 开发账号，测账号密码登录时用 |
| `KANEO_DEV_WORKSPACE_ID`、`KANEO_DEV_PROJECT_ID` | 示例工作区和 `Demo` 项目 |

开发登录：构建时带上 `--dart-define-from-file=$HOME/.config/kaneo-app/dev.env`，App 没有登录状态时会用这个地址和 Key 自动登录，登录页也会多一个开发登录按钮。发布版忽略这些配置。这样构建时登录状态只留在内存里，不写系统钥匙串，所以测试「重开后保持登录」时不要带 `dev.env`。

服务端限制每个 API Key 每分钟 100 次请求，超过后返回 429 和 `Retry-After`。账号密码登录得到的令牌没有这个限制。需要大量请求的脚本和测试，用账号密码登录。

## 测试

`test/support/` 是给所有线用的：

- `fake_kaneo.dart`：假 API `FakeKaneo`。`KaneoApi` 的每个接口都能用，写入的内容会保留，字段和真实服务端一致
- `test_app.dart`：`pumpKaneoApp()` 跑整个 App，`pumpInApp()` 跑单个组件，`testBothLayouts()` 把一个用例在宽屏和窄屏各注册一次

```dart
testBothLayouts('看板加载失败时提示原因', (tester, size) async {
  final server = FakeKaneo()..fail('api/task/tasks/', status: 500);
  final app = await pumpKaneoApp(
    tester,
    server: server,
    size: size,
    location: AppRoutes.board(FakeKaneo.projectId),
  );
  expect(find.text(app.i18n.t('mobile:ui.loadFailed')), findsOneWidget);
});
```

`FakeKaneo` 的常用方法：

| 目的 | 方法 |
| --- | --- |
| 造数据 | `FakeKaneo.empty()`、`addProject`、`addTask`、`addLabel`、`addRelation`、`addComment`、`addNotification`，也可以直接改 `tasks`、`projects` 等列表 |
| 让接口失败 | `failNext(路径, status:)`、`fail(路径, status:)`、`clearOverrides()` |
| 自定义响应 | `on(路径, (request) => FakeResponse(200, {...}))` |
| 看加载中状态 | `final gate = server.hold(路径)`，`pumpKaneoApp(settle: false)`，之后 `gate.release()` |
| 断网、令牌失效 | `unreachable = true`、`credentialsRevoked = true` |
| 分页 | `boardPageSize` |
| 检查发出的请求 | `requests`、`requestsTo(路径, method:)` |

它不包含 WebSocket。接口或字段有变化时，改 `FakeKaneo`，再连本地 Kaneo 跑一次对照测试，它会实际调用读写接口，并比较假 API 和真实服务端的字段：

```bash
flutter test test/contract --dart-define-from-file=$HOME/.config/kaneo-app/dev.env
```

## 完成标准

管理员不逐个审查，只验收最终结果，所以测试就是质量关。每个任务完成前必须做到：

1. `flutter analyze` 没有问题
2. 纯逻辑有单元测试
3. 每条验收标准都有对应的 widget 测试，页面在宽屏（1366×1024）和窄屏（390×844）各跑一次
4. 有对应状态时覆盖加载中、错误、空数据和无权限
5. 修过的问题加回归测试

然后合并和交付：

1. `git fetch origin && git rebase origin/main`
2. 跑全量 `flutter test`，失败不能推送
3. `git push origin HEAD:main`，被拒绝就回到第 1 步
4. `kaneo submit <任务> --done --summary-file <文件>`，对照验收标准逐条写结果

管理员已确认不需要逐任务审查，所以这里用 `--done`。不走 PR。

只有真机或人工才能验证的项（如中文输入法、Android、Windows 和 Linux 的界面），写"未验证，留给管理员验收"，不算未完成。其他没验证的不能提交。

`main` 不能红。CI 失败时，让它变红的任务负责修。

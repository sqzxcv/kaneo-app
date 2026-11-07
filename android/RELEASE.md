# Android 内测包

管理员提供固定的发布 keystore、别名及密码；后续升级必须沿用该身份。本仓库不会生成或提交发布密钥。CI 的 `android-unsigned-*` 是未签名编译产物，不能作为可安装的内测 APK；发布构建不会回退到 debug 签名。

将管理员提供的 keystore 放在仓库外，例如 `~/.config/kaneo-app/android-release.jks`。在 `~/.config/kaneo-app/android-signing.json` 中填写以下字段（不要复制真实值到仓库或任务评论）：

```json
{
  "storeFile": "android-release.jks",
  "storePassword": "<管理员提供>",
  "keyAlias": "<管理员提供>",
  "keyPassword": "<管理员提供>"
}
```

`storeFile` 可为绝对路径或相对此 JSON 的路径。私有文件权限建议设为 `600`。脚本通过进程环境把签名参数传给 Gradle，密码不会进入命令行参数。

```sh
python3 .github/scripts/mobile_release.py android --build-number 2 --check
python3 .github/scripts/mobile_release.py android --build-number 2
```

脚本内部使用 `tool/with_device.sh` 排队。输出位于 `build/app/outputs/flutter-apk/`，每次分发使用比上次更大的 build number。把签名 APK 交给管理员验证安装、同签名升级和重开保持登录；本机不开 Android 模拟器。

参考：[Flutter Android 发布](https://docs.flutter.dev/deployment/android)。

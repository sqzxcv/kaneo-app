# iOS 内测包

KAN-44 的签名输入必须由管理员提供。本仓库只保存构建逻辑，不保存证书、私钥、profile、账号或线上配置。CI 的 `ios-unsigned-*` 是编译验证产物，不能安装，也不是 TestFlight 包。

在这台 Mac 的登录钥匙串中导入 **Apple Distribution 证书及其私钥**（管理员提供 `.p12`，通过钥匙串访问导入；不要把密码放进命令行）。Apple Development 证书不能替代它。

管理员需要有 Apple Developer Program 和对应 App Store Connect 应用的访问权限，并提供：

- `~/.config/kaneo-app/ios-app-store.mobileprovision`：iOS App Store 分发 profile，App ID 对应 `app.kaneo.kaneoApp`，包含上述 Distribution 证书。
- `~/.config/kaneo-app/ios-export-options.plist`：Xcode 分发时导出的 ExportOptions，包含 `method=app-store-connect`、`signingStyle=manual`、`destination=export`、`teamID`，以及把 `app.kaneo.kaneoApp` 映射到该 profile 名称或 UUID 的 `provisioningProfiles`。

私有文件权限建议设为 `600`。脚本会校验 profile 的用途、有效期、App ID 和匹配的签名身份；构建时把 profile 安装到当前 Xcode 的用户目录。Runner 的签名设置来自本次构建参数，不把团队标识写入工程。

```sh
python3 .github/scripts/mobile_release.py ios --build-number 2 --check
python3 .github/scripts/mobile_release.py ios --build-number 2
```

每次分发选择比上次更大的 build number。脚本内部使用 `tool/with_device.sh` 排队，只构建，不上传。成功后的 `.ipa` 位于 `build/ios/ipa/`。管理员通过 Transporter 或 Xcode 上传到对应 App Store Connect 应用，等处理完再分配 TestFlight 测试者；在 iPad 和手机上验证安装及升级后保留登录。

只有提供真实签名材料、构建出 IPA 并完成安装/升级验证后，才能把这些验收项标成通过。

参考：[Flutter iOS 发布](https://docs.flutter.dev/deployment/ios)。

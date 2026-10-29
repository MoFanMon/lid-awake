# 合盖不眠 2.0

一个原生 macOS 小应用，一个开关。Apple 芯片 / Intel 通用二进制，macOS 13 或更新版本。

## 安装与使用

推荐双击 `合盖不眠-2.0.pkg`，使用 macOS 安装器完成一次管理员授权。应用安装到 `/Applications/合盖不眠.app`，同时安装系统辅助服务。之后打开、开启或关闭均无需重复授权。

也可从 DMG 将应用拖到「应用程序」。首次打开时会请求一次管理员授权，自动复制到标准应用目录并安装同一个辅助服务。取消授权后，可通过按钮再次安装。

点按钮开启，按钮变绿后合盖继续执行任务。再点一次、关闭窗口或 Command-Q 退出，恢复开启前的休眠设置。合盖后内置显示屏仍关闭；本工具保持电脑运行。开启期间也会阻止菜单或闲置触发的系统睡眠。请保持通风、留意电量。

卸载前先关闭开关，然后从应用菜单选择「卸载系统辅助服务」，最后将应用移至废纸篓。卸载、重新安装、更换版本或系统撤销后台服务权限后，可能需要再次授权。程序不保存管理员密码。

此构建使用本地临时签名和 Hardened Runtime。当前预览构建未配置 Developer ID 证书，应用与安装包未做 Apple 开发者签名和公证，不代表已满足面向公众分发的签名要求。

## 权限与恢复

- GUI 始终以普通用户运行，日常切换通过本地 Unix socket 发送固定的 `enable` / `disable` / `status` 请求。
- root 服务由 launchd 管理，随系统启动并待命。只有当前控制台用户运行的、安装时记录的准确应用代码签名散列可以调用。socket 的内核审计令牌用于识别进程，避免仅凭 PID 验证。
- 不提供任意命令执行、任意路径写入或任意电源设置修改接口。服务只调用系统 `pmset -a disablesleep`，并从 IOKit 核验实际状态。
- 修改前以原子写入、fsync 保存原设置。应用进程退出或崩溃时恢复；服务崩溃 / 系统重启后先恢复上次会话再处理新请求。恢复失败会保留记录并重试。
- 只修改 SleepDisabled，保留原来的值。其他工具原本设置的禁止休眠状态也会被保留。

安装位置：

- 应用：`/Applications/合盖不眠.app`
- 服务：`/Library/PrivilegedHelperTools/local.lidawake.helper`
- launchd：`/Library/LaunchDaemons/local.lidawake.helper.plist`
- 签名规则与恢复记录：`/Library/Application Support/LidAwake/`（root 私有目录）
- 日志：`/var/log/local.lidawake.helper.log`

如需手动紧急恢复正常休眠：`sudo pmset -a disablesleep 0`。这会恢复允许休眠，不会保留其他工具原本设置的禁用状态。

## 构建与打包

安装 Apple Command Line Tools 后运行：

```sh
./test.sh
./build.sh /绝对路径/产物文件夹
./package.sh /绝对路径/产物文件夹
```

`package.sh` 生成通用 `.app`、系统 Installer `.pkg`、压缩 `.dmg` 和应用 `.zip`。无第三方依赖。打包不会自动安装或修改系统设置。

## 验证范围

本地完整测试包含 41 项检查，覆盖：原设置保存和恢复、重复开启、写入失败回滚、恢复失败重试、进程所有权、模拟应用退出、服务重建后的持久恢复、本地 socket 协议、拒绝未认可签名、审计令牌认可正确签名、恢复记录重新打开、目录与文件保护，以及本机 IOKit 状态读取。

另验证 arm64 / x86_64 编译、临时签名完整性、安装脚本语法、PKG 展开结构和 DMG 校验。

实际管理员授权安装、跨系统重启的服务注册、Intel 硬件运行和物理合盖需要在对应设备上确认。测试使用文件电源后端模拟系统写入，不会自动禁用本机休眠。

## 实现参考

- [Apple Code Signing：SecCodeCopyGuestWithAttributes](https://developer.apple.com/documentation/security/seccodecopyguestwithattributes(_:_:_:_:))
- [Apple 开源 pmset](https://github.com/apple-oss-distributions/PowerManagement/blob/main/pmset/pmset.m)
- [Apple 开源 XNU 电源管理](https://github.com/apple-oss-distributions/xnu/blob/main/iokit/Kernel/IOPMrootDomain.cpp)

本地临时签名构建通过用户明确授权的 PKG / 首次安装脚本安装 launchd 服务。具备 Developer ID 后，可进一步采用 Apple 推荐的 SMAppService 注册流程并签名、公证安装产物。

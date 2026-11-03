# Berry-FCM

**OriginOS / vivo FCM 推送守护模块** —— 解析自 OriginOS FCM Guardian(io.github.originosfcmguardian v1.0.0)的 smali,把其全部特权逻辑移植为纯 shell 的 Shizuku ADB 模块(Shevery / Shizuku-Next 模块格式)。

## 解决什么问题

vivo OriginOS 的 iManager / 后台清理会把应用置为 `stopped` 状态(强制停止)。处于 stopped 状态的应用**收不到任何广播**,包括 FCM 推送;如果被停的是 GMS(com.google.android.gms)本体,整个 Google 推送链路直接死亡。本模块:

1. **检测**:GMS 与自选目标是否带 stopped 标记、GcmService 是否存活、GMS 接收器是否注册;
2. **修复**:`cmd package unstop --user 0 <pkg>` 解除 stopped(写后只读复检确认)+ 三连 GCM 心跳广播唤醒推送;
3. **自动守护**:每次 Shizuku binder 会话自动跑一轮"每包每 boot 最多一次"的保守自愈(带 boot_count 账本,防止与系统互相打架);
4. **引导**:一键打开 vivo 后台自启动管理 / GMS 通知设置(OriginOS 常悄悄关掉这两处)。

## 移植对照(原版 smali → shell)

| 原版组件(smali) | 机制 | Berry-FCM 对应 |
|---|---|---|
| GuardianUserService | UserService 只允许 shell uid 2000(root/其他身份拒绝) | `lib/berry.sh` `b_identity_guard` |
| 执行器白名单 | 仅 am/cmd/getprop/id/pm/settings/dumpsys,含单次命令预算 | berry.sh 允许清单 + `FIX_BUDGET=10` |
| ie0.stopped 解析 | `dumpsys -t 3 package <pkg>` 匹配 `User 0:.*stopped=true` | `b_pkg_stopped` |
| e.smali 能力探测 | `cmd package help` 含 `unstop [--user USER_ID] PACKAGE` 才走新路径 | `b_unstop_supported` |
| y11.unstop | `cmd package unstop --user 0 <pkg>` | `b_unstop` |
| bd2 旧路径(反射 IPackageManager.setPackageStoppedState) | `app_process` 跑 APK 自带类 —— **不可移植** | 不移植;见下方限制 |
| sp0/bg0/fe0 心跳 ×3 | MCS_HEARTBEAT / ACTION_HEARTBEAT_NOW / SEND→GcmSenderProxy,校验 `result=0` | `b_heartbeat` |
| tc2 存活 | `dumpsys -t 2 activity service …/.gcm.GcmService` | `b_gcm_service_alive` |
| vi 接收器计数 | ReceiverList 正则于 `dumpsys activity broadcasts` | `b_gms_receiver_count` |
| rr2 boot 账本 | `settings get global boot_count` 每包每 boot 一次自愈 | `service.sh` + `state/` |
| wp 深链 | BgStartUpManagerActivity / com.iqoo.secure.BGSTARTUPMANAGER / GMS 通知设置 | `lib/links.sh` |

## 安装

**方式 A · Shevery 模块市场(推荐)**:Shevery → Modules → Catalog(首次需填一个 GitHub PAT,只用于调 api.github.com)→ 搜 **Berry-FCM** → 安装模式选 **Release ZIP**(装的正是本仓 release 里的成品 zip;Sources 模式会从源码树现打包,亦可用)。

**方式 B · 手动 ZIP**:下载 [dist/Berry-FCM-1.0.0.zip](https://github.com/miuiadmin/Berry-FCM/releases/latest) → Shevery → Modules → Install from ZIP。

无论哪种方式,装完都要:
1. 手机装好 [Shevery](https://github.com/HmnDev-Tech/shevery)(或 Shizuku-Next),以**无线调试/ADB** 方式激活(不要用 root —— 原版硬性要求 shell uid 2000,模块同样校验);
2. 模块设置:**Access mode = Full access**,并打开 **Allow background actions**(service.sh 自愈需要;Safe 模式按设计屏蔽它);
3. WebUI 需要 `usesShellBridge=true`(已声明)+ Full access,在模块卡片打开即用。

## 使用

- **Action 按钮** = 检测 → 修复 → 复检,输出弹窗 + `logs/action-last.log`;
- **WebUI**:状态四灯、立即检测 / 一键修复 / 监视 90 秒、守护目标增删(默认只守 GMS,可加 `org.telegram.messenger` 等)、vivo 快捷入口;
- 命令行(任意 Shizuku shell):
  ```sh
  sh <MODDIR>/lib/check.sh            # 只读体检,尾行 JSON:
  sh <MODDIR>/lib/fix.sh              # unstop + 心跳
  sh <MODDIR>/lib/watch.sh 90 15 4    # 监视 90s/间隔 15s/每 4 轮一次心跳
  sh <MODDIR>/lib/targets.sh list|add <pkg>|remove <pkg>|reset
  sh <MODDIR>/lib/links.sh autostart|gmsnotif|bootid
  ```

## 限制

- **`unstop` 需要 Android 13+**(`cmd package` 支持);低版本上原版走 `app_process` 反射 `setPackageStoppedState` 的旧路径依赖 APK 自带 dex,模块无法携带,故不移植——低版本上心跳仍可用,但 stopped 只能手动解除。
- GMS(`com.google.android.gms`)是核心目标,不可从列表移除。
- 所有写操作均为标准 shell 命令,无注入、无反射、无自有二进制;单次修复命令预算 10 条,超预算即停。

## 目录

```
module.prop        # id=berry_fcm · banner/webui/action/usesShellBridge 声明
action.sh          # Action 按钮:check → fix → 复检
service.sh         # 每 binder 会话一次的守门自愈(boot_count 账本)
lib/berry.sh       # 共享库:常量、身份守卫、探针、unstop、心跳、预算
lib/check.sh       # 只读体检 → 人读报告 + 单行 JSON
lib/fix.sh         # unstop(写后只读复检)+ 心跳
lib/watch.sh       # 限时监视循环
lib/targets.sh     # 守护目标管理(config/targets.txt)
lib/links.sh       # vivo 设置深链
webui/index.html   # 离线单文件 WebUI(暗色)
banner.png         # tools/gen_banner.py 生成(纯 stdlib)
tools/gen_banner.py
dist/Berry-FCM-1.0.0.zip
```

逆向分析全文见 `文档/技术调研/Berry-FCM模块与OriginOS-FCM-Guardian解析.md`(工作目录)。

— ported with attribution from OriginOS FCM Guardian v1.0.0

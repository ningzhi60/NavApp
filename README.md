# 因导航 · NavApp

高德导航 + 因的克隆音播报的 iOS App。没有 Mac，靠 **GitHub Actions 云 macOS 编译** + **Windows 用 Sideloadly 侧载**。

> **Bundle ID 全程锁定 `com.an.yinnav`。** 高德 key 绑它、Sideloadly 也保持它——改了就 `INVALID_USER_KEY`。

---

## Phase 1：先把管线跑通（现在做这个）

目标：CI 打出 IPA → 侧载进 iPhone → 启动看到「高德 SDK 链接 OK」。**先不做真导航**，先验证工具链没问题。

### 1. 申请高德 iOS Key
1. 高德开放平台 → 控制台 → 应用管理 → 创建新 key。
2. 服务平台选 **iOS 平台**，**安全码 Bundle Identifier 填 `com.an.yinnav`**（一字不差）。
3. 记下这个 Key。

### 2. 建 GitHub 仓库（建议 public，macOS Actions 分钟数无上限）
```bash
cd NavApp
git init && git add . && git commit -m "phase1: 骨架 + CI"
git branch -M main
git remote add origin https://github.com/<你的用户名>/NavApp.git
git push -u origin main
```
> 密钥不在代码里（`Secrets.swift` 已 gitignore），public 也不泄露。

### 3. 配 GitHub Secrets
仓库 → Settings → Secrets and variables → Actions → New repository secret：

| 名字 | 值 | 阶段 |
|---|---|---|
| `AMAP_IOS_KEY` | 上面的高德 Key | **Phase 1 必需** |
| `MINIMAX_GROUP_ID` | MiniMax GroupId | Phase 2 |
| `MINIMAX_API_KEY` | MiniMax API Key | Phase 2 |
| `MINIMAX_VOICE_ID` | 因的 voice_id | Phase 2 |

Phase 1 只用得到 `AMAP_IOS_KEY`；另外三个先随便填或留空都行。

### 4. 触发编译，下载 IPA
- push 后 Actions 会自动跑；或到 **Actions 页手动点 “Build IPA” → Run workflow**。
- 绿了之后进这次运行，底部 **Artifacts → NavApp-ipa** 下载，解压得到 `NavApp.ipa`。

### 5. Windows 侧载（联想小新直接跑）
1. 装 **Apple 官网版** iTunes + iCloud（**不要** Microsoft Store 版，Sideloadly 认不到设备）。
2. 装 [Sideloadly](https://sideloadly.io/)。
3. iPhone 数据线连电脑，Sideloadly 里：
   - 拖入 `NavApp.ipa`；
   - Apple ID 填你的（免费即可）；
   - **Bundle ID 保持 `com.an.yinnav` 不要改**；
   - Start，输入 Apple ID 密码（建议用 App 专用密码）。
4. iPhone：设置 → 通用 → VPN与设备管理 → 信任你的开发者证书。
5. 打开「因导航」，看到「高德 SDK 链接 OK ✅ / Key 尾号 xxxx」= **Phase 1 成功**。

> ⚠️ 免费 Apple ID 签的 App **7 天过期**，到期重新 Sideloadly 侧载一次即可。想省心可换 $99 开发者号（证书管一年）。

---

## Phase 2：真导航 + 因的声音（管线绿了再做）
CC 会加：路径规划、`playNaviSoundString` 回调、MiniMax TTS（hex 解码 + 磁盘缓存 + 2s 超时回退系统语音）、`AVAudioSession` duck、打断逻辑、高频短语预合成。

---

## 出错了怎么办
把 **Actions 里失败那一步的红色日志**整段贴给 CC。最可能需要微调的点：高德 pod 版本、隐私合规方法名、桥接头链接。这些都靠 CI 日志迭代，正常现象。

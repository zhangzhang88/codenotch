# Codenotch 额度测试版

基于 Codenotch 1.26.0。Gemini App 使用 Codenotch 内置网页登录，从 Gemini 用量页读取 5 小时和每周额度。Gemini API 支持内置网页登录 Google AI Studio 结算页，读取可用总额（赠金余额 + GCP 赠金）、赠金余额、GCP 赠金以及每月支出上限。Antigravity 沿用原有本地来源，包含 Gemini 模型及 Claude 和 GPT 模型。

在 Mac 上用 Xcode 和 XcodeGen 构建：

```sh
bash Scripts/build-quota-test.sh
```

输出为 `build/quota-test/DerivedData/Build/Products/Release/Codenotch.app`。测试版有独立的应用标识。构建脚本不会启动或替换已安装的应用。

打开测试版后，在「设置 → 账号」找到 Gemini App 并登录。读取到有效额度后，登录窗口会自动关闭，用量面板会刷新 Gemini App 卡片。Antigravity 的额度可对照 Antigravity IDE 的 View Usage 页面。

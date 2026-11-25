# Codenotch 额度测试版

基于 Codenotch 1.26.0。Gemini App 使用 Codenotch 内置网页登录，从 Gemini 用量页读取 5 小时和每周额度。Antigravity 沿用原有本地来源，包含 Gemini 模型及 Claude 和 GPT 模型。

在 Mac 上用 Xcode 和 XcodeGen 构建：

```sh
bash Scripts/build-quota-test.sh
```

输出为 `build/quota-test/DerivedData/Build/Products/Release/Codenotch.app`。测试版有独立的应用标识。构建脚本不会启动或替换已安装的应用。

打开测试版后，在「设置 → 账号」找到 Gemini App 并登录。Google 能否在这个内嵌窗口完成登录，以及登录后读取的真实数值，仍需实测。若 Google 拒绝登录，请保留错误信息。Antigravity 原有读数可对照独立应用的 View Usage 页面。

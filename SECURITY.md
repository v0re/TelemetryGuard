# 安全政策

## 支援版本

只支援 [GitHub Releases](https://github.com/v0re/TelemetryGuard/releases) 中最新的正式版本。

## 私下回報漏洞

請使用 [GitHub Private Vulnerability Reporting](https://github.com/v0re/TelemetryGuard/security/advisories/new) 私下回報；不要建立公開 Issue，也不要在 Threads 或其他社群貼出可利用細節。

回報請包含：

- TelemetryGuard 版本與 Windows 版本／Edition
- 最小重現步驟
- 預期結果與實際結果
- 已移除個資的錯誤訊息

請勿上傳 `backup-v1.json`、`resource-backup-v1.json`、`activity.log`、MachineFingerprint、使用者名稱、電腦名稱、公司裝置資訊、權杖或密鑰。

安全問題包括但不限於：固定白名單繞過、任意服務／排程／登錄修改、命令注入、ACL 或備份驗證失效，以及不正確或不可逆的還原。單純不同意 Microsoft 遙測政策，或對某個可選功能是否應停用的意見，不屬於安全漏洞，可改用一般 Issue 討論。

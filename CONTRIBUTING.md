# 參與貢獻

感謝你協助改善 TelemetryGuard。這個專案會修改 Windows 系統狀態，因此安全邊界比功能數量更重要。

## 開發原則

- 保持 Windows PowerShell 5.1 相容；`TelemetryGuard.ps1` 必須保留 UTF-8 BOM，避免 Windows PowerShell 5.1 顯示中文亂碼。
- 禁止加入任意名稱、萬用字元或使用者自訂的服務、排程、登錄路徑。
- 新增可選項目必須預設不勾選，並在 PR 提供 Microsoft 官方資料、使用影響及完整還原語意。
- 不得移除機器指紋、結構、ACL、固定白名單與備份內容驗證。
- 不得把 Microsoft Defender、Windows Update、SysMain、BITS、網路、登入、音效或儲存核心元件加入候選。
- 不得增加網路請求、遠端下載、自動更新、遙測上傳或靜默執行高權限變更。
- 不得提交備份、日誌、機器資訊、Release ZIP、憑證、權杖或密鑰。

## Pull Request

PR 請說明：

1. 變更內容與使用情境。
2. 可能影響及失敗時的行為。
3. 執行過的唯讀測試。
4. 若涉及系統狀態，手動套用與還原的測試方法。

PR CI 只解析語法與做靜態檢查，不會執行外部 PR 中的程式。受信任的 `main` 只執行 `Status` 與 `Preview` 唯讀測試。CI、Copilot、Codex 或其他機器人永遠不得執行 `Disable`、`Restore`、GUI 或 `Start-TelemetryGuard.cmd`。

所有變更必須經過 PR 與成功 CI；機器人可以提出修正或功能分支，但不得直接推送受保護的 `main` 或自動合併。

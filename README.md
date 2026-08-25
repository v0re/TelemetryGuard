# TelemetryGuard

一個可還原、固定白名單、預設保守的 Windows 遙測與背景資源最佳化工具。

> [!CAUTION]
> 本工具需要系統管理員權限，會變更 Windows 服務、排程與政策。可選項目全部預設不勾選；「高記憶體」不等於「不必要」，請先閱讀每個選項的影響並建立可用的系統備份。

## 下載與快速使用

1. 從 [Latest Release](https://github.com/v0re/TelemetryGuard/releases/latest) 下載 `TelemetryGuard-1.1.1.zip` 與 SHA-256 檔。
2. 解壓縮整個資料夾。
3. 雙擊 `Start-TelemetryGuard.cmd`，在 UAC 提示中確認允許。
4. 先查看狀態；需要時才切換到「可選資源最佳化」並勾選確定不用的功能。
5. 按「關閉遙測＋已勾選項目」。若要復原，按「還原原始設定」。

1.1.1 正式 ZIP 的 SHA-256：

```text
20D229062D9991106157A49BB8123DE7179F64FF34EF419CA806850E6FABF32A
```

在 PowerShell 驗證下載：

```powershell
Get-FileHash .\TelemetryGuard-1.1.1.zip -Algorithm SHA256
```

## 主要功能

- 停止並停用 `DiagTrack`（Connected User Experiences and Telemetry）。
- 依 Windows 版本套用 Microsoft 官方支援的最低診斷資料政策，並退出 CEIP。
- 停用固定白名單內、且實際存在的主要相容性／CEIP 排程。
- 套用前在 `%ProgramData%\TelemetryGuard` 建立 ACL 保護的原始狀態備份。
- 驗證機器、資料結構、白名單與備份內容後才允許還原。
- 提供圖形介面、唯讀狀態、變更預覽及一鍵還原。

## 可選資源最佳化

以下項目全部預設不勾選，且只能操作程式內的固定名稱；不能輸入任意服務、排程或萬用字元。

| 項目 | 可能影響 |
| --- | --- |
| Windows 搜尋索引 | 檔案、開始功能表及 Outlook 搜尋可能變慢或不完整 |
| Mixed Reality Link | Meta Quest 3／3S 串流與混合實境連線 |
| 列印服務 | 實體列印、Microsoft Print to PDF 與其他列印功能 |
| 跨裝置與手機連結 | Phone Link、附近分享與部分跨裝置功能 |
| 定位與離線地圖 | 定位、天氣及離線地圖更新 |
| Xbox 與 Game Pass | Xbox 登入、雲端存檔、多人連線與部分配件 |
| 額外遙測、錯誤回報與意見回饋 | Windows Error Reporting 與部分故障診斷能力 |
| 程式相容性小幫手 | 舊程式相容性偵測與修正建議 |

「勾選目前 ≥ 50 MB」只會勾選固定候選中、當下相關宿主工作集達門檻的項目。服務可能共用宿主行程，因此顯示值不等於保證可釋放的記憶體；Ready 排程也不會持續占用該數字。

## 安全邊界

本工具刻意不變更：

- Windows Update、Microsoft Defender
- hosts、DNS、防火牆
- 網路、音效、藍牙、電源、登入與儲存核心服務
- SysMain、BITS、Delivery Optimization
- Edge、Office 或其他 Microsoft 應用程式本身的遙測設定

程式沒有網路請求、遙測上傳或自動更新功能。啟動時會鎖定 `TelemetryGuard.ps1` 並驗證正式版 SHA-256，避免 UAC 等待期間被同一使用者層級的程序置換。隨附 PowerShell 程式仍未經 Authenticode 簽署；啟動器的 `ExecutionPolicy Bypass` 只作用於該次 PowerShell 程序，不會永久修改系統執行原則。請只從正式 Release 下載並核對 ZIP 雜湊。

若套用時排程正在執行，程式會將該次工作停止。還原會恢復備份的 `Enabled` 設定，但不會重新啟動先前被中止的那一次工作。

備份只在本機保存 MachineGuid 的 SHA-256 以防跨機器誤還原，`activity.log` 保存操作時間與摘要；兩者都不會上傳。成功還原後的備份封存與日誌不會自動刪除，確認不再需要時可由系統管理員刪除 `%ProgramData%\TelemetryGuard`。

## 相容性與限制

- 支援 Windows 10、Windows 11 與 Windows Server 2016 或更新版本。
- Windows Pro 的官方最低等級是「必要診斷資料」（政策值 1）；Enterprise、Education 與 Server 才支援官方「診斷資料關閉」等級。
- Home 版不在相關官方管理政策支援清單內，程式會略過不適用的政策寫入。
- 關閉相容性遙測可能讓大型功能更新的就緒資訊不完整；進行就地升級前可先還原。
- 本工具不宣稱阻止 Windows 或 Microsoft 產品的所有網路連線或資料收集。
- 公司或學校管理的裝置，請先取得 IT 管理員同意。

## 唯讀檢查

查看目前狀態：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\TelemetryGuard.ps1 -Mode Status -NoElevation
```

只預覽預計變更：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\TelemetryGuard.ps1 -Mode Preview -NoElevation
```

預覽指定可選項目：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\TelemetryGuard.ps1 -Mode Preview -NoElevation -OptionalProfiles search-indexing,compatibility-assistant
```

## PR 自動化

- 所有 PR 都會自動執行 Windows PowerShell 5.1 語法與靜態安全檢查。
- 只有受信任的 `main` 分支會執行 `Status`／`Preview` 唯讀煙霧測試；CI 永遠不執行 `Disable`、`Restore` 或啟動器。
- 儲存庫包含 Copilot／Codex 維護指令，讓有權限的維護機器人依相同安全邊界審查或提出修正。
- 機器人不得直接合併、不得繞過 CI，也不得讓外部 fork PR 取得密鑰或寫入權限。

詳見 [CONTRIBUTING.md](CONTRIBUTING.md)、[SECURITY.md](SECURITY.md) 與 [AGENTS.md](AGENTS.md)。

## 資料來源與聲明

- [原 Threads 影片](https://www.threads.com/@rememberyouenterprise/post/DcchAhSjB2q/media)
- [Microsoft Learn：Configure Windows diagnostic data in your organization](https://learn.microsoft.com/windows/privacy/configure-windows-diagnostic-data-in-your-organization)
- [Microsoft Learn：System Policy CSP / AllowTelemetry](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-system#allowtelemetry)
- [Microsoft Learn：Turn off Windows Customer Experience Improvement Program](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-admx-icm#ceipenable)
- [Microsoft Learn：Windows Setup compatibility scan logs](https://learn.microsoft.com/troubleshoot/windows-client/setup-upgrade-and-drivers/use-windows-setup-compatibility-scan-logs-to-identify-blocking-issues)
- [Microsoft Learn：Windows Search performance](https://learn.microsoft.com/troubleshoot/windows-client/shell-experience/windows-search-performance-issues)
- [Microsoft Learn：Windows service optimization guidance](https://learn.microsoft.com/windows/iot/iot-enterprise/optimize/services)

TelemetryGuard 是獨立的開放原始碼專案，與 Microsoft、Meta／Threads 或原影片作者沒有隸屬或背書關係。

## 授權

[MIT License](LICENSE) — Copyright (c) 2026 v0re。

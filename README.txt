Windows 遙測與資源最佳化 TelemetryGuard
=======================================
版本 1.2.0 新增四個背景服務候選、可調整的高記憶體門檻、共用宿主辨識及更安全的相依服務檢查。

使用方式
--------
支援 Windows 10、Windows 11 與 Windows Server 2016 或更新版本。

1. 解壓縮整個資料夾。
2. 雙擊 Start-TelemetryGuard.cmd。
3. Windows 顯示使用者帳戶控制（UAC）時，確認允許。
4. 切換到「可選資源最佳化」，只勾選確定不用的功能。
5. 按「關閉遙測＋已勾選項目」。

高記憶體門檻可在 10–2048 MB 間調整。「勾選目前 ≥」只會勾選固定白名單中、當下相關宿主達門檻且能歸因到單一服務的候選；共用宿主只顯示總值，不會自動勾選。仍需由你確認影響後再套用。

程式會做什麼
------------
- 第一次套用前，將原始設定備份到：
  %ProgramData%\TelemetryGuard\backup-v1.json
- 勾選額外資源項目時，另將那些項目的原始狀態備份到：
  %ProgramData%\TelemetryGuard\resource-backup-v1.json
- 備份資料夾只允許 Administrators 與 SYSTEM 存取；還原時會驗證機器、固定白名單與資料格式。
- 兩份備份會獨立驗證；若其中一份損壞或不可讀，另一份通過驗證的備份仍可還原，問題檔案會原封保留並顯示錯誤。
- 停止並停用 DiagTrack（Connected User Experiences and Telemetry）服務。
- 將 Windows 診斷資料政策設成此版本官方支援的最低值。
- 透過 Microsoft 官方政策讓所有使用者退出 CEIP。
- 在支援的 Windows 11／Server 版本限制額外診斷記錄與完整傾印收集。
- 未勾選額外項目時，主要遙測處理只停用以下精確白名單內、且實際存在的排程：
  Microsoft Compatibility Appraiser
  Microsoft Compatibility Appraiser Exp
  Consolidator
  KernelCeipTask
  UsbCeip
- 提供「還原原始設定」按鈕，精確恢復備份中仍存在目標的已備份設定值；成功後會封存備份，下一次套用重新建立基準。
- 若 Windows 大型更新已移除舊服務或排程，還原時會安全略過且不自行重建；更新後新出現、未在備份中的元件也不會被舊備份變更。
- 套用時若目標排程正在執行，程式會將它停止；還原會恢復 Enabled 設定，但不會重新啟動先前已被中止的那一次工作。

遙測處理範圍
------------
- 主要範圍是 DiagTrack、官方診斷資料／CEIP 政策，以及固定的 Compatibility Appraiser／CEIP 排程。
- Windows Error Reporting、意見回饋與永續性遙測只有在主動勾選對應選項時才會處理。
- Edge、Office、Microsoft Store App、其他第三方程式及每使用者動態服務的遙測不在自動處理範圍。
- Windows 版本可能另有其他元件；本工具不宣稱完全關閉 Windows 或 Microsoft 所有遙測與連線。

可勾選的資源最佳化
------------------
下列項目全部預設不勾選。程式只會操作固定名稱，不能輸入自訂服務或萬用字元。

- Windows 搜尋索引：WSearch 與索引維護排程。會讓檔案、開始功能表及 Outlook 搜尋變慢或不完整。
- Mixed Reality Link：若不用 Meta Quest 3／3S 串流，可選擇停用。
- 列印服務：停用 Spooler；實體印表機、Microsoft Print to PDF 與其他列印功能都會失效。
- 跨裝置與手機連結：影響 Phone Link、附近分享及部分跨裝置功能。
- 定位與離線地圖：影響定位、天氣、離線地圖更新及其他依位置功能。
- Xbox 與 Game Pass：影響 Xbox 登入、雲端存檔、多人連線與部分控制器配件。
- 額外遙測、錯誤回報與意見回饋：停用額外遙測／回饋排程及 Windows Error Reporting 服務，會降低故障診斷資訊。
- 程式相容性小幫手：影響舊程式相容性偵測與建議修正。
- Microsoft Store 應用程式安裝：停用 InstallService；Store 無法安裝或更新 App，但 Windows Update 不受此項控制。
- Windows Media Player 媒體庫分享：停用 WMPNetworkSvc；無法再經 UPnP 分享媒體庫給電視或其他網路裝置。
- Windows 行動熱點：停用 icssvc；已透過這台電腦上網的裝置會中斷連線。
- WebDAV 網路檔案用戶端：停用 WebClient；檔案總管與程式無法使用 WebDAV／部分 SharePoint 對應資料夾。

顯示的 MB 是候選服務所在宿主行程的當下 Working Set。共用宿主的數值是整個行程總值，無法歸因到單一服務；程式不會用門檻按鈕自動勾選這類項目。數值不等於保證能釋放的記憶體。排程在 Ready 狀態不會常駐占用該數字，主要造成間歇性的 CPU、磁碟與記憶體尖峰。

建立資源備份後，選項會鎖定。若要改選另一組，先按「還原原始設定」，再重新勾選；這可避免停用沒有原始狀態可供還原的新項目。

刻意不會變更
------------
- Windows Update
- Microsoft Defender
- hosts、DNS 或防火牆規則
- 網路、音效、藍牙、電源、登入及儲存核心服務
- SysMain、BITS 與 Delivery Optimization
- Edge、Office 或其他 Microsoft 應用程式本身的遙測設定

Windows Error Reporting 只有在你主動勾選「額外遙測、錯誤回報與意見回饋」時才會停用；未勾選時只套用官方的傾印與額外診斷記錄限制政策。

重要限制
--------
- Windows 11/10 Pro 不支援官方「診斷資料完全關閉」等級；本工具會採官方最低的「必要診斷資料」（政策值 1）。
  本工具仍會停用影片所示的 DiagTrack 與主要相容性／CEIP 排程。
- Home 版不在上述官方管理政策支援清單內，工具會略過不適用的政策寫入。
- Enterprise、Education 與 Server 版才支援官方「診斷資料關閉」等級。
- 關閉診斷資料可能降低 Microsoft 分析更新失敗、驅動程式相容性及系統故障的能力。
- 停用 Compatibility Appraiser 可能讓大型功能更新的相容性／就緒資訊不完整；進行就地升級前可先還原。
- 大型 Windows 版本更新可能新增、移除或重新啟用排程。若工具提示基準已過期，先按「還原原始設定」封存舊基準，再重新套用；工具不會猜測新元件的舊狀態。
- 1.2.0 可讀取並還原 1.1.1 的既有備份；若要降回舊版，先用 1.2.0 還原，因為 1.1.1 不認得新 profile。
- 公司或學校管理的裝置，請先取得 IT 管理員同意。
- 「高記憶體」不等於「不必要」；請依是否使用搜尋、列印、Xbox、定位等功能自行決定。
- 本工具不宣稱阻止 Windows 或 Microsoft 產品的所有網路連線。

本機資料與完整性
----------------
- 程式沒有網路請求、遙測上傳或自動更新功能。
- 啟動時會鎖定目前的 TelemetryGuard.ps1，並在提升權限時驗證相同 SHA-256，避免 UAC 等待期間被另一個同使用者程序替換。
- 隨附程式未經 Authenticode 簽署；Start-TelemetryGuard.cmd 的 ExecutionPolicy Bypass 只作用於該次 PowerShell 程序。請只從正式 GitHub Release 下載並核對 ZIP 的 SHA-256。
- 備份會在本機保存 MachineGuid 的 SHA-256，用來阻止跨機器誤還原；activity.log 會保存操作時間與摘要，兩者都不會上傳。
- 每次成功還原後，舊備份會以 backup-restored-* 或 resource-backup-restored-* 封存在 %ProgramData%\TelemetryGuard。工具不會自動刪除封存與日誌；不再需要且確認已完成還原後，可由系統管理員手動刪除整個該資料夾。

唯讀檢查（進階）
----------------
在 PowerShell 執行：
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\TelemetryGuard.ps1 -Mode Status

只看預計變更，不修改系統：
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\TelemetryGuard.ps1 -Mode Preview

預覽特定可選項目：
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\TelemetryGuard.ps1 -Mode Preview -OptionalProfiles search-indexing,compatibility-assistant

命令列還原若只有部分備份成功，JSON 會回傳 Partial=true 與 Errors，程序結束碼為 2；成功全部還原時結束碼為 0。

資料來源
--------
- 使用者提供的 Threads 影片：
  https://www.threads.com/@rememberyouenterprise/post/DcchAhSjB2q/media
- Microsoft Learn：Configure Windows diagnostic data in your organization
  https://learn.microsoft.com/windows/privacy/configure-windows-diagnostic-data-in-your-organization
- Microsoft Learn：System Policy CSP / AllowTelemetry
  https://learn.microsoft.com/windows/client-management/mdm/policy-csp-system#allowtelemetry
- Microsoft Learn：Turn off Windows Customer Experience Improvement Program
  https://learn.microsoft.com/windows/client-management/mdm/policy-csp-admx-icm#ceipenable
- Microsoft Learn：Compatibility Appraiser 對功能更新相容性掃描的用途
  https://learn.microsoft.com/troubleshoot/windows-client/setup-upgrade-and-drivers/use-windows-setup-compatibility-scan-logs-to-identify-blocking-issues
- Microsoft Learn：Windows Search 效能問題與停用索引的影響
  https://learn.microsoft.com/troubleshoot/windows-client/shell-experience/windows-search-performance-issues
- Microsoft Learn：Windows IoT Enterprise 固定用途裝置的服務最佳化指引
  https://learn.microsoft.com/windows/iot/iot-enterprise/optimize/services
- Microsoft Learn：VDI 服務最佳化與 Microsoft Store Install Service 影響
  https://learn.microsoft.com/windows-server/remote/remote-desktop-services/remote-desktop-services-vdi-optimize-configuration
- Microsoft Learn：Service Host 分組與共用行程
  https://learn.microsoft.com/windows/application-management/svchost-service-refactoring
- Microsoft Learn：WebClient 已淘汰且預設不啟動
  https://learn.microsoft.com/windows/whats-new/deprecated-features
版本：1.2.0

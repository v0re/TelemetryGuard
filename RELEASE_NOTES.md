# TelemetryGuard 1.2.0

可還原的 Windows 遙測與背景資源最佳化工具。

## 新功能

- 新增 Microsoft Store 應用程式安裝、Windows Media Player 媒體庫分享、Windows 行動熱點與 WebDAV 用戶端四個固定白名單候選。
- 高記憶體勾選門檻可調整為 10–2048 MB。
- 標示共用服務宿主的總工作集；這類項目不會被門檻按鈕自動勾選，但仍可由使用者閱讀影響後手動選擇。
- 停用前會拒絕連帶停止未勾選且仍在執行的相依服務。
- 所有新項目仍預設不勾選，並使用既有受保護備份與完整還原流程。
- 1.2.0 可還原 1.1.1 的既有備份；降版前應先由 1.2.0 完成還原。

## 範圍與限制

- 遙測核心仍限於 DiagTrack、官方診斷資料／CEIP 政策及固定的 Compatibility Appraiser／CEIP 排程。
- Edge、Office、商店 App、每使用者服務及其他應用程式的資料收集不在自動處理範圍。
- 不變更 Defender、Windows Update、SysMain、BITS、Delivery Optimization 或網路連線／登入／儲存核心。
- 高工作集不等於不必要，也不等於可釋放量。

## 下載驗證

`TelemetryGuard-1.2.0.zip`

```text
SHA-256: 44757EC30B6E7AF19789A4114959C4F70DC3D7A89BBEDC978BE351008E1AF487
```

> 使用前請閱讀 README。工具需要系統管理員權限；高記憶體不等於不必要。程式不宣稱完全阻止 Windows 或 Microsoft 產品的所有資料收集或網路連線。

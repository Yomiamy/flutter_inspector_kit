---
name: list-work-dir
description: 當使用者輸入 /list-work-dir，或詢問「目前工作目錄有哪些」、「working directory 有什麼」時使用。
---

# list-work-dir

## 概述

從 session 環境中讀取並列出所有工作目錄路徑，不展開目錄內容。

## 使用時機

- 使用者輸入 `/list-work-dir`
- 使用者詢問「目前工作目錄有哪些」
- 使用者詢問「working directory 有什麼」

## 執行步驟

1. 從 session 環境讀取主要工作目錄（Primary working directory）
2. 讀取附加工作目錄（Additional working directories）
3. 依序列出路徑，不執行 `ls`，不展開內容

## 輸出格式

```
主要目錄：/path/to/primary

其他目錄：
- /path/to/additional-1
- /path/to/additional-2
```

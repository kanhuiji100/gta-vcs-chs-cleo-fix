# 变更记录

## 1.0.0 — 2026-10-25

首个版本，针对 `ULJM05297`（日版基底，v1.01）汉化版。

### 修复

- **开场加载数据时崩溃**：改用上游 `main`（2.0.3）的对齐安全脚本流读取
  （`read_u16` / `read_i32`），修复 PPSSPP 2026-08 之后版本因未对齐访问返回 0
  导致脚本 ip 损坏的问题。
- **`CPU Jump to 00000000`**：`OP_CALL_FUNCTION` 增加地址范围检查，
  `addr < 0x08800000` 时停掉脚本并记录日志，不再让模拟器崩溃。
  触发者为 `gtavcs.autoaim.csa`（特征串按美/欧版生成，日版中不存在）。
- **CLEO 菜单文字乱码**：新增 `cleo.ini` 配置 `text_offset` / `text_offset_disc`，
  统一在 `wstr_from_ansi`、`ansi_to_unicode`、`OP_CREATE_MENU` 三处应用字符码映射
  （字母转大写后 −2，数字 −1，空格不变）。

### 新增

- `build/build-cleo.sh`：自动拉取上游、打补丁、拉取 injector 依赖并编译
- `scripts/install.sh` / `scripts/uninstall.sh`：安装与回滚
- `config/cleo.ini`：配置样例
- `docs/ROOT-CAUSE.md`：三个问题的完整技术分析
- 分发包 `cleopsp-vcs-chs-fix.zip`（memstick 布局）

### 已知限制

- `autoaim` 在日版/汉化版上不可用（函数特征不匹配），已安全跳过，不影响其他功能。

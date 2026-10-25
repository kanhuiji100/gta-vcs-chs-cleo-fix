# 三个问题的技术分析

环境：PPSSPP v1.20.1（SDL 构建），CLEO PSP 2.0.2（2024-10-01 发布版），
游戏镜像 `PLAY Grand Theft Auto Vice City Stories CHS 2.0.iso`（日版基底 `ULJM05297` v1.01）。

---

## 问题 1：开场后加载数据时崩溃

### 现象

开场动画结束、开始加载世界与任务脚本的瞬间，PPSSPP 直接段错误退出。

```
08:56:56  sceKernelSuspendThread(411/412/413): bad thread ID
08:56:57  MIPSCompileOp: Invalid instruction b233ba03      ← 连续 8 条
          MIPSCompileOp: Invalid instruction b63c3884
          ... b49b38bb, b393b824, b6a32e44, b5b5b75e, b372256a, b522316e
08:56:57  Bad memory access detected and ignored: 628d4f04 / 54536d8c / ffffb4cc ...
08:56:57  EmuThread: segfault at 7f130000309c   → SIGSEGV
```

`0xb233ba03` 这类字按 MIPS 解码是非法指令，说明 CPU 已经跑进数据区。
执行线程是 `threadmain`——GTA 主线程，脚本 VM 也在这里。

### 根因

CLEO 2.0.2 的脚本指令流读取是直接解引用：

```cpp
uint16_t op = *(uint16_t *)ip;          // 可能是奇数地址
int32_t offset_signed = *(int32_t *)ip; // 命令流 7 字节一条，跳转偏移常落在未对齐地址
```

PPSSPP 从 2026 年 8 月的构建起会检查访问对齐，未对齐访问被报为非法内存访问并**返回 0**，
于是 `ip` 被算成错误值，脚本 VM 跳到脚本数据里继续"执行"。

上游 2.0.3 的更新日志正是描述这一条：

> fixed a crash on PPSSPP builds which check memory alignment (Aug 2026 and later),
> the script command stream was read with unaligned 32-bit loads — which current PPSSPP
> reports as an invalid memory access and returns as 0, corrupting the script ip on jumps and calls

### 修复

直接基于上游 `main` 构建，其读取已改为对齐安全的形式（`source/unaligned.h`）：

```cpp
uint16_t op = read_u16(ip);
int32_t offset_signed = read_i32(ip);   // 逐字节拼接，任何地址都安全
```

### 验证

| | 旧版 2.0.2 | 新版 |
|---|---|---|
| 日志 | 停在 `initialize success` | 走到 `CTheScripts::Init()`，加载 17 个脚本 |
| `Invalid instruction` | 8 条 | 0 |
| 存活 | 约 24 秒后崩溃 | 120 秒无异常 |

---

## 问题 2：`CPU Jump to 00000000`

### 现象

修好问题 1 之后，进入游戏 30～100 秒（不固定，取决于何时触发）崩溃：

```
Bad Execution Address
Destination: CPU Jump to 00000000
PC: 0822afdc   RA: 0822afe4   Cur thread: threadmain
```

### 定位

PPSSPP 的模块加载日志给出 CLEO 的装载区间：

```
Block: 08220e00 - 082d0900 size 000afb00 taken=1 tag=ELF/"CLEO"
```

`PC 0x0822afdc` 落在该区间内，偏移 `0xa1dc`，用带调试信息的构建反查：

```
$ psp-addr2line -C -f -e cleo.elf 0xa1dc
core::custom_opcode(core::t_script&, unsigned short)
```

对应 `core.cpp` 里 `case OP_CALL_FUNCTION` 的函数指针调用：

```cpp
uint32_t res = cast<func_i_t>(addr)(PARAM_VALS);   // addr == 0 → 跳转 0
```

即脚本执行 `0DDE call_func` 时传入的地址是 0。

### 根因

`gtavcs.autoaim.csa`（自动启动脚本）：

```
0DD0: 2@ = get_label_addr @eptn_CPad_GetPad
0DDA: 2@ = get_pattern_addr_cstr 2@ index 0
...
:set_aim
0DDE: call_func 2@ add_ib 0 __result 'resi' 0@ __pad_index 'i' 0
```

它用字节特征在游戏可执行段里搜索 `CPad::GetPad`：

```
?? ?? ?? ?? 23 20 A4 00 C0 20 04 00 23 10 85 00
```

该特征串在本镜像的 `EBOOT.BIN` 中**出现 0 次**（全文件扫描确认）。原因是日版/汉化版的
编译结果与美/欧版不同，函数寄存器分配变了，特征自然对不上。

`get_pattern_addr_cstr` 找不到时返回 0，脚本没有做判空，直接 `call_func 0`。

### 修复

在 `OP_CALL_FUNCTION` 里加一道范围检查——游戏代码永远位于 image base 之上：

```cpp
if (addr < 0x08800000u)
{
    utils::log("call_func to invalid address 0x%08X, stopping script '%s'", addr, script.name.c_str());
    script.invalid = true;
    return true;
}
```

效果：坏脚本被单独停掉并记录，模拟器不再崩溃。

```
[UTC|02:35:20] call_func to invalid address 0x00000000, stopping script 'gtavcs.autoaim.csa'
```

（`ULJM05297` 的 image base 是 `0x08804000`。）

### 遗留

autoaim 功能本身在该版本仍不可用。已核对 EBOOT 中 4 处 `23 10 85 00` 候选，均非同一函数，
无法用简单替换修好。要恢复需重新逆向定位 `CPad::GetPad`，再改写 `gtavcs.autoaim.csa`
偏移 209 处那串 ASCII 特征（长度上限 47 字符）。

---

## 问题 3：菜单文字乱码

### 现象

```
cleo menu     →  engq ogPw
bodyguards    →  只剩零星字母
1 of 3        →  0 of 3
```

装同样的 CLEO 到 USA 版镜像上，菜单显示完全正常。

### 根因

两个版本的字体来源不同：

| 版本 | 字体位置 |
|---|---|
| USA v1.03 | 内嵌在 EBOOT 中 |
| 日版 / 汉化版 | 外置 `PSP_GAME/USRDIR/ART/FONTS/FSFONTSJP1.XTX`（262,396 字节） |

汉化组替换了这个外置字体以容纳中文字模，导致字模表重排；而 CLEO 是把自己的 ASCII
字符串直接当字模索引交给游戏的字体渲染器。

### 实验方法

在 `ui::draw_menu` 里临时把真正送进 `CFont::PrintString` 的 16 位字符码打印出来，
与截图逐一对照：

```
menu title 'CLEO MENU' -> codes: 0041 004A 0043 004D 0020 004B 0043 004C 0053
menu item 0 codes: 0060 006D 0062 0077 0065 0073 005F 0070 0062 0071
```

- 标题原本就是大写，减 2 后是 `A J C M · K C L S`，显示成 `cleo menu` —— 正确
- 列表项 `bodyguards` 减 2 后是 `` `mbwes_pbq ``，几乎全空白

结论：字体**只有一套字母字形块**（小写形态，位于 `0x3F`–`0x58`），没有独立的大写块。
小写字母减 2 落进空白区，所以必须先转大写。

数字则不同：`1 of 3` 减 2 会显示成 `0 of 3`，说明数字块比字母块偏移少一格。

### 修复

统一成一个转换函数，三处文本路径共用：

```cpp
uint16_t glyph_code(int c)
{
    if (ansi_char_offset)
    {
        if (c >= 'a' && c <= 'z') c -= 'a' - 'A';           // 字体只有一套字母字形
        if (c >= '0' && c <= '9') c += ansi_char_offset + 1; // 数字块差一格
        else if (c > 0x20)        c += ansi_char_offset;     // 空格不参与
    }
    return (uint16_t)c;
}
```

调用点：

| 位置 | 覆盖范围 |
|---|---|
| `strutils::wstr_from_ansi` | GXT 文本表（`CLMNU` 等）、fxt、菜单项 |
| `ui::ansi_to_unicode` | 菜单标题、`OPEN CLEO MENU` 等提示、页码 |
| `core::OP_CREATE_MENU` | 脚本内联的标题字符串 |

早期只改了第一处，表现为"标题正常、列表乱码"——因为标题走的是 `ansi_to_unicode`。

### 结果

```
cleo menu                          cheats  3 OF 3                 teleport  1 OF 2
  bodyguards                         mad cars                      starfish island
  carspawner                         black cars                    docks
  cheats                             trashmaster                   airport
  clear wanted                       pickup chicks                 military base
  select mission                     fanny magnet                  downtown
  teleport                           glass cars                    stadium
  weather                            topsy turvy                   movie studio
                                                                   malibu
```

---

## 附：关于这个 ISO

镜像本身不是标准原盘，排查时的几个发现：

- `PSP_GAME/SYSDIR/EBOOT.BIN` 是**明文 ELF**（`ET_SCE_RELEXEC`，MIPS，入口 `0x350a30`，
  4,612,604 字节，带完整 `.rel.text` / `.rel.data` 重定位表），而零售 UMD 应是加密 SELF
- `PSP_GAME/SYSDIR/BOOT.BIN` 是同尺寸的**全零占位文件**（4,612,604 字节）
- `PARAM.SFO`：`DISC_ID = ULJM05297`，`DISC_VERSION = 1.01`

也就是说汉化包替换过可执行文件。这也是 CLEO 这类按代码特征打补丁的插件容易出问题的原因之一
——不过本例中三个问题分别来自插件自身缺陷，与镜像改动没有直接因果关系
（问题 1、2 换到正常构建同样会触发，问题 3 纯粹是字体差异）。

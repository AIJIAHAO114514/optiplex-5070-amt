# 开启 Intel AMT 的标准流程（fpt.efi + Shell 脚本）

> 本流程在 Dell OptiPlex 5070 MT（Q370 / CSME 12.0 / BIOS 1.35.0）上完整跑通并验证，
> 回读哈希一致，AMT 在 MEBx 中可配置。

## 0. 先判断"这台能不能做"

四条全过才动手，缺一条就别浪费时间：

| 条件 | 怎么查 | 不满足的后果 |
|---|---|---|
| **芯片组是 Q 系列**（Q370/Q470/Q570/Q670…） | 主板型号 | B/H/Z 系列多数没有 AMT 硬件 |
| **ME 是 Corporate（COR）** | `MEA me.bin` → `SKU: Corporate H/LP` | `CON`（1.5MB）永远没有 AMT，且不可互换 |
| **SPI 可写** | `fpt.efi -i` 能出区域表 + 服务跳线可装 | 写保护，`Error 280` |
| **BIOS 有 Manageability / MEBx** | F2 里看有没有 Manageability 项 | AMT 开了也没入口 |

## 1. 准备（一次性）

```
目标机（UEFI Shell，不需要 PE、不需要驱动）
  Fpt.efi                   读写 SPI

台外 Windows（需要 Python 3）
  FIT（Flash Image Tool）    生成新 ME 区
  MEA（ME Analyzer）         判断 SKU / 状态 / 版本

RGN（干净 ME 区镜像）
  命名规则：<版本>_<SKU>_<平台>_<PRD>_RGN.bin
  例：12.0.68.1606_COR_H_BA_PRD_RGN.bin
  必须是 RGN，不能是 EXTR / EXTR-Y（那是从整机抽的已配置区）

U 盘（FAT32，整盘，不必可引导）
  \EFI\BOOT\BOOTX64.EFI    Shell.efi（BIOS 认这个路径就能直接进 Shell）
  \fpt.efi
  \dump.nsh                导出脚本
  \write.nsh               写入脚本
```

## 2. 导出原始 ME 区（目标机，UEFI Shell）

```
断电 → 装服务跳线 → 插电开机        ← 必须"断电拔线"后装，软关机不算
Shell 里：fpt.efi -i                 ← 记下 CSME 区的 Base/Limit
          dump.nsh                    ← 产出 full.bin + me.bin
```

校验三条：

1. `full.bin` 大小 = `Total Installed SPI Memory`
2. `me.bin` 大小 = 描述符里 CSME 区大小（5070 是 `0xFFD000`）
3. `fpt.efi -me -d` 与"从 full.bin 按描述符裁剪"逐字节一致

> `me.bin` 是唯一原始备份，出问题全靠它。复制两份，别只留 U 盘。

## 3. 生成新 ME 区（桌面 Windows + FIT）

```
1. FIT 打开 full.bin（路径不能有空格）
2. 左树点 Ifwi: Intel(R) ME and Pmc Region
3. 右侧 ME Binary File → 指向 RGN
   ★ 成功的唯一标志：左树冒出 Intel (R) AMT / Platform Protection / Flex I/O 等节点
4. 核对 Intel (R) AMT 页：AMT Supported=Yes、initial power-up=Enabled、KVM Redirection=Yes
5. Build → Build Image（弹 Boot Guard Profile 5 - FVME → Yes）
6. outimage.bin 必须仍是原大小（5070 是 32MB）
7. 02_make_me.bat fit-output → 裁出 me_amt.bin
```

`02` 会强制校验：BIOS 区、GbE 区与原 dump 逐字节相同；ME 区长度不变；MEA 判定 `File System State = Configured`。

## 4. 写入（目标机 Shell）

```
me_amt.bin 放 U 盘根目录
write.nsh 三步：
  fpt.efi -me -d me_before.bin      ← 刷前备份（这台机的回滚点）
  fpt.efi -f me_amt.bin -me         ← 只写 ME 区
  fpt.efi -me -d me_after.bin       ← 回读
```

**回读必须与 `me_amt.bin` 哈希一致**，FPT 打印 successful 不算数。

收尾：

```
fpt.efi -greset      → 机器立刻重启，让 ME 重新初始化
断电 → 拔电源线 → 取下服务跳线 → 上电
```

## 5. 验收

```
F2 → Manageability          应出现 Intel AMT 开关，状态 Enabled
Ctrl+P → MEBx               默认密码 admin，强制改密码（大小写+数字+特殊字符）
  Intel(R) AMT Configuration
    Manageability Feature Selection = Intel AMT
    User Consent = KVM / All（需要远程桌面时）
    Network Setup → 主机名/域名
    Activate Network Access
浏览器 http://<本机IP>:16992
```

## 6. 回滚

```
fpt.efi -f me_before.bin -me
```

ME 区坏了机器通常还能进 BIOS / Shell（BIOS 由 CPU 执行，与 ME 无关），所以这条路能救回来。
真正的"砖"只会发生在描述符或 BIOS 被改坏时 —— 本流程只写 ME 区，不会碰到。

## 7. 故障对照

| 现象 | 原因 | 处理 |
|---|---|---|
| `Error 280` | 服务跳线没真正生效 | 断电、拔电源线、装跳线、再上电 |
| `Error 1 / 4` | 权限或 SPI 访问被拒 | 确认是在 Shell 里跑 `fpt.efi`（不是 Windows 版程序）；再核对跳线 |
| FIT 树里只有版本号、没有 AMT 节点 | ME Binary File 没换成功，或点过 `File → Open` 被重置 | 重做第 3 步，Build 前不要 Open |
| Build 后 MEA 仍 `Initialized` | RGN 没真正进去 | 检查 ME Binary File 路径 |
| 写入成功但 F2 里没有 AMT | 跳线没取 / 没断电池 / MEBx 未启用 | 断电取跳线，进 Ctrl+P 设 Manageability |
| `me_after.bin` 哈希不符 | 写保护、容量不足、中途中断 | 重刷，别在 X: 内存盘上操作 |

## 8. 实测数据（OptiPlex 5070 MT）

| 项 | 值 |
|---|---|
| SPI | 32768KB，CSME `0x3000-0xFFFFFF`（`0xFFD000`） |
| 原 ME | `12.0.97.3000` / Extracted / **Initialized** |
| 新 ME | `12.0.68.1606` / **Configured** / MEA Size `0x77C000` |
| RGN | `12.0.68.1606_COR_H_BA_PRD_RGN.bin`（13,225,984 B） |
| me_amt.bin | 16,764,928 B，SHA256 `ea31e562…f264` |
| 回读 | 与 me_amt.bin **逐字节一致** |
| 结构差异 | FIT 12.0.72 把 FPT 从 `0x1000` 挪到 `0x634000`，区头布局表同步更新（ME 靠表定位，自洽） |
| 刷前备份 | 与首日 dump 仅差 1 字节（`0x146CCE`，运行期日志计数） |

## 9. 其他平台可行性

三条硬门槛与平台无关：**COR SKU、SPI 可写、BIOS 有 MEBx**。
变的是工具版本和 RGN 可得性。

| 平台 | 芯片组 | ME 大版本（以 MEA 实测为准） | 工具 | RGN 可得性 | 结论 |
|---|---|---|---|---|---|
| 300 系 | Q370 | CSME 12.0 | FPT/FIT **12** | 好（12.0 COR_H_BA 有 68/70） | **已验证** |
| 400 系 | Q470 | CSME 12.0（CMP-H） | FPT/FIT **12** | 同上，同家族 | **高**，流程照抄 |
| 500 系 | Q570 | CSME 14.x | FPT/FIT **14** | 需另找 14.x COR RGN | 中高 |
| 600 系 | Q670 | CSME 16.x | FPT/FIT **16** | 稀缺，多为 EXTR | 中，需试点 |
| 700 系 | Q770 | CSME 16.x/18 | 对应版本 | 更稀缺 | 低-中 |

判断方法一律相同：`MEA me.bin` 看 `SKU` 和 `Version`，再按大版本取对应工具与 RGN。

### 各平台额外注意

- **Q470（400 系）**：与 300 系同属 CSME 12，同一套 FPT/FIT/MEA 直接可用，RGN 也是同一家族。唯一差异是描述符布局和 BIOS 选项位置。**先在样机上只做"导出 + MEA"两步**，确认 SKU 是 COR，再按本流程走。
- **Q570（500 系）**：工具换 v14。RGN 需要匹配 `14.x_COR_H_*_RGN`，公开库比 12.0 少。没有 RGN 时，FIT 直接改原区基本无效（配置已定稿），别浪费时间。
- **Q670（600 系）**：工具换 v16。三个新风险：
  1. RGN 极稀缺，多数公开文件是 `EXTR`；
  2. CSME 16 引入更严的 SVN/回滚保护，跨版本替换能否启动没有公开验证；
  3. 600 系主板/整机的 ME 写保护更强，服务跳线未必存在（消费级主板常见）。
  建议只做到"导出 + MEA 判定 + 找 RGN"这三步，评估通过再上机。
- **所有平台通用**：BIOS 更新会重写 ME 区（Dell 的 1.35.0 包里就带 `12.0.97.3000` 载荷），
  所以顺序永远是 **先升 BIOS，再改 ME**；之后再升 BIOS 需要重刷一次 `me_amt.bin`。

### 同一个 me_amt.bin 能不能"通刷"？

**能，但只在"同型号 + 同 BIOS 版本"范围内。按芯片组通刷不行。**

`me_amt.bin` 不是一个通用固件，它是"某台 5070、BIOS 1.35.0"的 ME 区完整快照（16MB 区域）。
它和三样东西绑定：

| 绑定项 | 不同会怎样 |
|---|---|
| **区域大小**（描述符定义，5070 是 `0xFFD000`） | 大小不符 → `fpt -me -f` 直接拒绝（`03` 也会在写前拦） |
| **Boot Guard 配置**（Profile 5 + PCH strap） | 大小碰巧相同也会在开机阶段失败（可回滚） |
| **ME SKU**（必须 `Corporate H`） | `CON` / `LP` 平台刷了也不会有 AMT |

每台刷前三项必查：

```
fpt.efi -i         → CSME Base 0x3000 / Limit 0xFFFFFF（即 0xFFD000）
MEA me.bin         → SKU: Corporate H，Chipset: CNP/CMP-H B,A
CPU                → 必须支持 vPro（i5-8500/8600/9500/9600、i7-8700/9700…；i3 与非 vPro i5 不行）
```

三条全过才能复用同一个 `me_amt.bin`；**每台仍要单独留 `me_before.bin`**。

不能通刷的典型：OptiPlex 7070、Precision 3630 这类同为 Q370 但不同机型的机器
（描述符、区域大小、Boot Guard strap 都可能不同）——这种必须用该机自己的 `full.bin` 走一遍 FIT。

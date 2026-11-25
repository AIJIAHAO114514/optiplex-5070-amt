# 强刷 ME 区激活 vPro / AMT：一台 OptiPlex 5070 的完整实战

> **先说人话**
>
> - 大晚上刷机，记得先拔蜂鸣器。（这是一个悲伤的故事）
> - BIOS 相关的任何操作，动手前先备份。

---

**一句话结论**

vPro 的 AMT 开关不在 BIOS 里，而在 ME 固件的"配置数据"里。
把整块 ME 区换成一版干净的 **RGN**，用 FIT 重新构建一次，AMT 就出来了。

下面三条路都走不通——升级 BIOS 设置、用 FWUpdate 刷 ME、在 FIT 里直接改原始 dump。
本文说明为什么，以及正确的第四条路。

| 项 | 内容 |
|---|---|
| **环境** | Dell OptiPlex 5070 MT / Q370 / BIOS 1.35.0 / CSME 12.0（Corporate H） |
| **结果** | ME `12.0.97.3000 · Initialized` → `12.0.68.1606 · Configured` |
| **验证** | 回读哈希与写入文件逐字节一致；AMT 可配置 |

**全文导航**

```
0   Q370 为什么出厂没有 AMT
1   为什么常规办法都没用
2   先判断这台机器值不值得动手
3   工具链
4   准备：一个 FAT32 U 盘
5   第一步：导出原始 ME 区
6   第二步：FIT 里换 RGN（核心）
7   第三步：裁出 me_amt.bin 并校验
8   第四步：写入（只写 ME 区）
9   第五步：MEBx 与验收
10  避坑清单
11  能不能"通刷"
12  扩展到其他平台
13  风险与回滚
附  实测数据 / 参考来源
```

---

## 0. 先回答一个疑问：Q370 为什么出厂没有 AMT？

拆开机器看到 Q370，很多人就觉得"这台应该支持 vPro"。**它确实支持，只是被关掉了。**

这件事分三层看。

**第一层｜硬件和固件都够**

AMT 需要三样东西同时成立：Q 系列芯片组、支持 vPro 的 CPU、Corporate（COR）版 ME 固件。
5070 用的就是 COR 固件（本文实测 `SKU: Corporate H`）。所以不是"固件缺这一块功能"。

**第二层｜Dell 在 ME 里把 AMT 关了，而且已经"定稿"**

出厂 ME 区在构建时 AMT 就是关闭状态；机器首次上电又完成了一次数据初始化，`File System State = Initialized`。
配置写进 MFS 之后，FIT 打开它连配置树都不展开，改也改不进去。

这才是"升级 ME、改 BIOS 都没用"的根因。

**第三层｜入口被藏起来了**

Dell 的 `Manageability` 菜单是按 ME 上报的能力**动态显示**的。ME 不报 AMT，F2 里要么没有这一项，要么显示为不可用。
于是绝大多数人的判断是"这机器不支持"——其实是菜单没露面。

**但也有真的不支持的**

5070 有非 vPro 的配置（i3，以及 i5-9400 这类非 vPro 型号）。CPU 侧不满足，刷了 ME 也不会有 AMT。

判断标准就两条：**CPU 是否 vPro、ME 是否 COR**。两条都满足，缺的只是"把 ME 区换成一版 AMT 打开的干净区域"。

---

## 1. 为什么常规办法都没用

社区里那位把 5070 改成 AMT 的帖主，前三次尝试全部失败。这三条路值得先看清楚，因为它们正是大多数人的第一反应。

| 尝试 | 做法 | 结果 |
|---|---|---|
| ① 升级 ME | `FWUpdLcl64 -allowsv -f cse_image_FWU_Base.bin` | 刷写成功，**零效果**。BIOS 和开机画面毫无变化 |
| ② 改 dump 后整片刷 | FIT 打开 32MB dump、打开 AMT、`fptw64 -f outimage.bin` | **变砖**：2 短 1 橙 "Bad Motherboard"，拔 CMOS 30 秒才救回 |
| ③ 只改 FIT 设置 | FIT 里勾上 AMT，Build，再打开产物检查 | AMT 仍是 disabled，"设置像没写进二进制一样" |

三次失败，原因只有一个词：**`Initialized`**。

ME 区首次上电时会执行一次性的"数据初始化"：把配置写进内部的 **MFS** 文件系统，然后打上"已初始化"标记。从此这块区域就是**定稿状态**。

- `FWUpdate` 只换代码分区，不碰 MFS → 配置不变，AMT 照旧是关的；
- BIOS 里没有 AMT 开关，因为开关根本不在 BIOS 侧；
- FIT 打开一块已定稿的区域时，配置树是只读的（甚至不展开），勾了也写不进去。

> **唯一有效的动作**
>
> 把整块 ME 区（代码 + 配置）替换成 Intel 出厂的干净区域 **RGN**，让 FIT 在此基础上重新生成配置。

---

## 2. 先判断这台机器值不值得动手

四条硬门槛，缺一条就别浪费时间：

| 门槛 | 怎么查 | 不满足会怎样 |
|---|---|---|
| **Q 系列芯片组** | 主板型号（Q370 / Q470 / Q570 / Q670…） | B / H / Z 系列多数没有 AMT 硬件 |
| **ME 是 Corporate** | `MEA me.bin` → `SKU: Corporate H/LP` | `CON`（1.5MB）永远没有 AMT，且不可互换 |
| **SPI 可写** | `fpt.efi -i` 能出区域表 + 服务跳线可装 | 写保护，报 `Error 280` |
| **CPU 支持 vPro** | i5-8500 / 8600 / 9500 / 9600、i7-8700 / 9700 一类 | 刷了也不会有 AMT |

四条里最容易漏的是最后一条。ME 刷成功、MEBx 也进了，结果因为 CPU 不带 vPro 而用不了 AMT——这种事只能靠事前查清楚。

---

## 3. 工具链

整套流程分两段：**目标机上全是 UEFI Shell 命令**，**构建和校验在台外 Windows 上做**。

目标机侧不需要 PE、不需要 MEI 驱动——EFI 版 FPT 直接调 UEFI 的 SPI 协议，开机进 Shell 就能读写。

### 目标机：UEFI Shell

| 文件 | 用途 |
|---|---|
| `Fpt.efi` | 真正读写 SPI 的程序（Intel 原厂 EFI 版） |
| `Shell.efi` | UEFI Shell 本体。放到 `\EFI\BOOT\BOOTX64.EFI`，开机就能直进 |
| `startup.nsh` | 进 Shell 自动打印文件系统列表 + `fpt.efi -i`，先确认能读到 SPI |
| `dump.nsh` | 一键导出 `full.bin` + `me.bin` |
| `write.nsh` | 一键写入：备份 → `fpt.efi -f me_amt.bin -me` → 回读 `me_after.bin` |

### 台外 Windows：构建与校验

| 文件 | 用途 |
|---|---|
| `02_make_me.bat fit-input` | 从整片 dump 里裁出 ME 区，作为 FIT 的对照参考 |
| `02_make_me.bat fit-output` | 从 FIT 的 `outimage.bin` 裁出 **`me_amt.bin`**；强制校验 BIOS/GbE 未变、ME 长度不变、MEA 判 `Configured` |
| `tools\FIT\fit.exe` | 换 RGN、核对 AMT、Build 出新的整片镜像 |
| `tools\spi_region.py` | 解析 Flash Descriptor、按区域裁剪、逐区域比对、ME 区合法性检查 |
| `tools\mea\MEA.py` | 判断 ME 的 SKU / 版本 / `File System State`（`Initialized` 还是 `Configured`） |

> **顺序记忆**
>
> 目标机导出 → 台外构建 → 目标机写入
> `dump.nsh` → `02 fit-input` / FIT / `02 fit-output` → `write.nsh`

---

## 4. 准备：一个 FAT32 U 盘

整套流程只用**一个 U 盘，整盘格成 FAT32**——不做启动盘，不用 Ventoy，也不分两个区。

原理很简单：UEFI 固件启动时会去每个分区找 `\EFI\BOOT\BOOTX64.EFI`，找到就执行它。把 `Shell.efi` 改成这个文件名放进去，BIOS 就会把它当成一个启动项。单 U 盘能跑起来，靠的就是这一条。

### 4.1 格式化

资源管理器右键 U 盘 → 格式化 → 文件系统选 **FAT32** → 快速格式化。

| 容量 | 做法 |
|---|---|
| 32GB 及以下 | Windows 直接能格 FAT32 |
| 64GB 及以上 | Windows 会拒绝，用 Rufus（选 FAT32，**非可引导**）或 `diskpart` |

**不要用 Ventoy。** 它的数据区是 exFAT，而 UEFI Shell 只带 FAT 驱动——Shell 起来了也看不见里面的文件。

### 4.2 放文件

把 `uefi-shell\` 里的**所有内容**拷到 U 盘根目录，最终长这样：

```
U:\
├── EFI\
│   └── BOOT\
│       └── BOOTX64.EFI      ← 就是 Shell.efi，BIOS 认的是这个路径
├── Shell.efi                ← 同一个文件，留一份方便单独取用
├── fpt.efi
├── startup.nsh
├── dump.nsh
└── write.nsh
```

三个必须对的地方：

| 要点 | 说明 |
|---|---|
| **层级不能错** | 必须正好是 `\EFI\BOOT\BOOTX64.EFI`，多一层少一层都认不到 |
| **不要套文件夹** | 不是 `U:\uefi-shell\EFI\...`，是 `U:\EFI\...` |
| **空间要够** | `full.bin` 32MB + `me.bin` 16MB，根目录至少留 100MB 空闲 |

### 4.3 开机进 Shell

1. 插 U 盘，开机连按 **F12** 进 One-Time Boot Menu。
2. 选 **`UEFI: <你的U盘名>`**——不是 `Legacy` / `BIOS` 那一条。
3. 直接进 Shell，`startup.nsh` 自动执行，先打印文件系统列表和区域表。

F12 列表里如果没有 `UEFI:` 开头的项，进 F2 把 **Boot Mode** 从 Legacy 改成 **UEFI**，再试一次。

### 4.4 提示符不是 `fs0:\>` 怎么办

这是最常见的卡点。先看一眼提示符：

| 提示符 | 含义 | 下一步 |
|---|---|---|
| `fs0:\>` | 当前目录就是 U 盘根目录 | 直接敲 `dump.nsh` |
| `Shell>` | **当前目录没设置** | 先 `map` → `fs0:` → `dir` |

`Shell>` 状态下 `dir` 会报 `Current directory not specified`，`dump.nsh` 也会找不到 `fpt.efi`。按顺序敲：

```
map            列出所有文件系统（fs0:、fs1:、blk0:…）
fs0:           切过去
dir            看有没有 fpt.efi 和 dump.nsh
```

`fs0` 不对就试 `fs1:`、`fs2:`，直到 `dir` 能列出 `fpt.efi`。

不想来回切也行，直接用全路径：

```
fs1:\fpt.efi -i
fs1:\dump.nsh
```

### 4.5 Shell 里够用的几个命令

| 命令 | 作用 |
|---|---|
| `map` | 列出所有文件系统 |
| `fs0:` | 切换到 fs0 |
| `dir` / `ls` | 列当前目录 |
| `cd <目录>` | 进子目录 |
| `cls` | 清屏 |
| `fpt.efi -i` | 看 SPI 区域表 |
| `reset` | 重启 |
| `exit` | 退出 Shell（会尝试下一个启动项） |

`.nsh` 脚本就是把这些命令写进一个文本文件。Shell 里敲文件名 = 逐行执行，`dump.nsh` 干的就三件事：dump 整片、dump ME 区、`ls` 确认产物。

---

## 5. 第一步：导出原始 ME 区

### 5.1 装服务模式跳线

![](https://cyberbus.net/pictrs/image/68123d13-e3fb-4234-8f08-b3ae0e407fe5.avif)

*服务模式跳线在这里，1~6 pin。正常工况连接 3-4 pin；连接 1-2 pin 启用服务模式；5-6 pin 应该是清除 CMOS 用的（未验证）。*

服务模式跳线**只管写保护，不管读权限**。所以读不出全片时，别急着怀疑跳线。

装上跳线后，`fpt -i` 的 `Master Region Access` 一栏能看到各主控对每个区域的读写权限，可以作为"跳线是否生效"的旁证。

**顺序不能错：**

```
断电 → 拔电源线 → 装跳线 → 插电开机
```

软关机不算。

### 5.2 看区域表

进 Shell 之后（怎么进见 §4.3）先跑 `fpt.efi -i`，看区域表：

<!-- 图：UEFI Shell 下 fpt.efi -i 的区域表输出 -->

关键三行：

```
CSME   - Base: 0x00003000, Limit: 0x00FFFFFF
Total Accessible SPI Memory: 32768KB, Total Installed SPI Memory: 32768KB
FPT Operation Successful.
```

`Total Accessible` = `Total Installed`，说明描述符把整片 32MB 都暴露出来了，没有被裁掉一截。

### 5.3 导出，并做双路互校

`dump.nsh` 会导出两个文件：

| 文件 | 内容 |
|---|---|
| `full.bin` | 32MB 整片 |
| `me.bin` | ME 区 |

**双路互校是必做的**：用描述符裁剪出来的 ME 区，和 `fpt -me -d` 直接读出来的 ME 区，逐字节比对。

这一步能抓出"dump 看着有 32MB、其实是残的"这类隐蔽问题。两个来源对得上，才说明这次 dump 是干净的。

### 5.4 顺手存一份配置快照

FIT 打开 `full.bin` 之后，`File → Save As`，存一份 XML（比如 `full-config.xml`）。

**这一步不要省。** 下一步换 ME 区时，FIT 会把整棵配置树替换掉（§6.2 会讲），
到时候你唯一的对照基准就是这份快照。

里面记着 Dell 在这台机器上的全部 426 项配置：AMT 关闭、PTT 开启、SATA/PCIe 复用方式、
HD Audio 电压、时钟输出开关……丢了就只能靠猜。

---

## 6. 第二步：FIT 里换 RGN（核心步骤）

> **可以跳过这一章吗？**
>
> 如果机器是 **OptiPlex 5070 + BIOS 1.35.0**，并且 Shell 里
> `fpt.efi -me -d me_now.bin` 出来的文件正好是 **16,764,928 字节**（`0xFFD000`），
> 说明 ME 区长度和本仓库的预置镜像一致，可以直接取 `firmware/me_amt.bin` 跳过 §6、§7，
> 从 §8 开始刷。
>
> 其他机型或 BIOS 版本请走完这一章。配置不匹配的镜像刷进去，轻则 TPM 报错、掉盘，
> 重则开不了机。

### 6.1 三步操作

1. 把 `fit.exe` 解到**路径没有空格**的目录下（FIT 的老毛病），打开。
2. `File → Open` 选 `full.bin`。
3. 左树点 `Ifwi: Intel(R) ME and Pmc Region` → 右侧属性表找 **`ME Binary File`** → 双击值 → 浏览 → 选干净的 RGN：
   `12.0.68.1606_COR_H_BA_PRD_RGN.bin`

### 6.2 注意：换 ME 文件会把整棵配置树重置

先澄清一个容易搞错的地方：**从 `full.bin` 导入时，左边的树本来就是完整的。**

`Intel (R) ME Kernel`、`Intel (R) AMT`、`Platform Protection`、`Integrated Clock Controller`、
`Flex I/O`、`GPIO` —— 这些节点在换 RGN **之前**就都在，`ME Binary File` 指向原厂那块 ME，
ME 版本显示 `12.0.97.3000`。

FIT 底部的日志也能确认这一点——每换一次 ME 文件，它就把 `full.bin` 重新加载一遍：

```
Loading D:\...\full.bin
Decomposed SVU Value: "Intel(R) Cannonlake H Series Chipset - CNP-H No Emulation"
FIT version used to build the image: 12.0.33.1422
Writing map file D:\...\full.map
```

换 RGN 之后，树**看起来没有任何变化**——节点还是那些，能展开的还是能展开。

**这恰恰是它危险的地方。** 树看着是好的，你不会去怀疑；但里面的值已经被整棵换成
RGN 的默认配置了。

FIT 读的是 ME 文件里自带的那套配置，**整棵替换掉**从 `full.bin` 继承的配置。
Dell 在这台机器上的定制，一项都不剩。

同一台机器逐项对比（原厂快照 vs 换 RGN 后的产物），**426 项里有 35 项被改**：

| 被改的项 | 原厂 | RGN 默认 | 后果 |
|---|---|---|---|
| `PttSupported` | **Yes** | **No** | **fTPM 失效，开机报 `TPM could not be initialized`** |
| `PttPwrUpState` | Enabled | Disabled | 同上 |
| `SataPCIeComboPort2` | **SATA** | **PCIe** | 接在这个口的硬盘消失 |
| `HdaVoltSelect` | **3.3V** | **1.8V** | 声卡供电不对，可能没声音 |
| `ClkoutSRC0/5/6/7/12/13/14/15` | Disabled | **Enabled** | 8 路时钟输出被凭空打开 |
| `FwUpdateOemId` | Dell 的 GUID | 全 0 | OEM ID 丢失 |
| `ProfileChangeable` | true | false | BIOS 里改不了 boot profile |
| `NvarPostManUnLckd` | No | Yes | 生产后 NVAR 可改，安全变松 |
| `DbgOverridePreProdSi` | `0x0` | `0x8` | 调试位被置位 |

**怎么判断换没换成功**：看 `Intel (R) ME Kernel` 下面的版本号。
从 `12.0.97.3000` 变成 `12.0.68.1606` 就是换上了。

节点数量、树的结构都不会告诉你任何事——它们前后一模一样。

> **一句话：树看着正常，不代表配置是对的。**
> 正确做法是拿 §5.4 那份快照逐项对照，或者直接用 §6.6 的 XML 修复法。

### 6.3 关键认知：AMT 不需要你手动开

**空白 RGN 的出厂默认就是 AMT 打开的。** 换区成功后，`Intel (R) AMT` 页上的值已经是：

| 选项 | 默认值 | 说明 |
|---|---|---|
| Intel (R) AMT Supported | **Yes** | 核心开关，已经是开的 |
| Intel (R) ME Network Services Supported | **Yes** | 网络服务 |
| Manageability Application Supported | **Yes** | 可管理性应用 |
| Manageability Application initial power-up state | **Enabled** | 上电即生效 |
| Intel (R) AM IDE Timeout | `0xFFF` | 保持默认 |
| Intel (R) AMT Watchdog Automatic Reset Enabled | No | 保持默认 |

所以这一页**基本不用改**。你要做的是**核对**，不是"开启"。

> 如果发现 `AMT Supported = No`，说明 RGN 拿错了，很可能是 `CON` 或 `EXTR`。

Corporate H 的树里没有 `Standard Manageability` 这一项——那是低配 SKU 的字段，不用去找。

### 6.4 其他要留意的选项

| 位置 | 选项 | 该怎么做 |
|---|---|---|
| ME 节点 | `ME Binary File` | **必须指向 RGN** — 全流程的关键一步 |
| `Intel (R) AMT` | 6.3 那 6 项 | 核对为 `Yes` / `Enabled`，一般无需改 |
| KVM 段 | `KVM Redirection Supported` | 默认 **Yes**，远程桌面靠它 |
| KVM 段 | `Firmware KVM Screen Blanking` | 只影响远程画面是否黑屏，按需 |
| **`Intel (R) PTT Configuration`** | `PTT Supported` | **照抄原厂快照**（这台是 Yes） |
| **`Intel (R) PTT Configuration`** | `initial power-up state` | **照抄**（Enabled） |
| **`TPM Over SPI Bus Configuration`** | `TPM Over SPI Supported` | **照抄**（这台是 No，用 fTPM，没有独立芯片） |
| `Platform Protection` | `Boot Guard Profile Configuration` | **保持 `Profile 5 - FVME`，不要改** |
| Build Settings | `Enable Boot Guard` | **必须 Yes**。改 No 后 BIOS 验签过不去，开不了机 |
| Build Settings | `Output Path` / `Region Order` / `Signing Tool` | 全部保持默认——这个窗口**不是改 AMT 的地方** |
| **任何位置** | **带 `[FPF]` 后缀的项** | **一律不动** —— 那是熔丝，烧断不可逆 |

**PTT 这三项为什么必须单独拎出来说**：它俩是 fTPM 的载体，跑在 ME 里。

RGN 的默认值**不等于**你机器出厂时的实际配置。原厂是 `Yes` 而 RGN 给了 `No`，刷完 TPM 就废，
开机直接报 `TPM could not be initialized`；反过来原厂用独立 TPM 芯片（`No`），
RGN 给了 `Yes`，ME 会去找一颗不存在的芯片，同样初始化失败。

**判断依据只有一条：打开 §5.4 存的那份快照，照着抄。**

![](https://cyberbus.net/pictrs/image/c4516c18-bac1-4efb-9e76-3f38662360eb.avif)

*Build Settings：这里一个字段都不要改。*

### 6.5 Build 时那个弹窗

`Build → Build Image` 会弹：

> `Boot Guard Profile Configuration is set to 'Boot Guard Profile 5 - FVME'. Do you want to continue?`

**点 Yes。**

理由不是"看着像默认值"，而是能在 BIOS 区里找到证据：

| 证据 | 位置 | 说明 |
|---|---|---|
| `__KEYM__` + RSA 签名块 | BIOS 区偏移 `0xFC4C80` | Boot Guard 的 Key Manifest 在 |
| TCG 事件 `Boot Guard Measured S-CRTM` | BIOS 区偏移 `0xE970B8` | 这台机器本来就在跑"验证 + 度量" |

FVME 正是这一档。真正会拦开机的是 FVE（验证）那一半，而 BIOS 一个字节都不动，KM/BPM 保持有效。Measured 只往日志里记账，不拦截。

### 6.6 配置对不上怎么办：用 XML 快照修

如果已经换过 RGN，开机发现 TPM 报错、硬盘少了一块、或者没声音——**不必从头再来**，
也不用在 GUI 里逐个开关去改（35 项，肉眼必漏）。

FIT 的项目文件本身就是一份 XML。做法：

**第一步，改两处**

打开 §5.4 存的那份 `full-config.xml`，用文本编辑器改：

```
① MeRegionFile  ->  指向你构建出的 ME 代码子分区
                    例如 ...\outimage\Decomp\ME Sub Partition.bin
② 6 项 AMT：
     <AmtSupported value="No"           -> "Yes"
     <NetServicesSupported value="No"   -> "Yes"
     <MngAppSupported value="No"        -> "Yes"
     <MngAppPowerUpState value="Disabled" -> "Enabled"
     <KvmSupported value="No"           -> "Yes"
     <AmtIdleTimeout value="0x0001"     -> "0xFFFF"
```

**其余 420 项一个字不动。** 尤其别碰带 `[FPF]` 的。

**第二步，验证配置有没有被再次重置**

```
FIT → File → Open → 改好的 XML
→ 立刻展开 Intel (R) PTT Configuration
→ 确认 PTT Supported = Yes
```

**这一步是整个方法的关键动作。** 如果显示 `No`，说明 FIT 又按 `MeRegionFile` 重载了配置，
XML 这条路走不通，只能退回 GUI 逐项改（对照 6.2 那张表）。

**第三步，Build**

```
Build → Build Image → 弹 Boot Guard FVME 确认框 → Yes
→ 02_make_me.bat fit-output → write.nsh
```

**效果**：这么重建出来的 ME 区，和"错版"的差异只有 **0.09%**（15,877 字节，全是配置），
代码一个模块没动——这一点可以用 `spi_region.py compare` 验证。

> 本仓库的 [`policy/fixed.xml`](../policy/README.md) 就是这么一份成品（原厂配置 + 6 项 AMT），
> 可以直接拿来对照。

---

## 7. 第三步：裁出 me_amt.bin 并校验

> 用预置镜像的，`me_amt.bin` 已经在手上了，跳过本章的裁剪步骤，直接看 §8。

```
02_make_me.bat fit-output   →  拖入 outimage.bin，再拖入原始 full.bin
```

它会做四件事，任何一条不过就拒绝产出：

| # | 关卡 | 说明 |
|---|---|---|
| 1 | `outimage.bin` 必须还是 **32MB** | 长度不对说明构建有问题 |
| 2 | **BIOS 区、GbE 区**与原 dump **逐字节相同** | 描述符差异单独报告，不写入 |
| 3 | ME 区长度必须与原来一致（5070 是 `0xFFD000`） | 长度不符，`fpt -me -f` 也会拒绝 |
| 4 | MEA 判定 `File System State` 必须是 **`Configured`** | 是 `Initialized` 就说明换区没生效 |

这四道关卡是"能不能上机刷"的分界线。全过了，才值得动目标机。

实测前后对比：

| 字段 | 原机 | 构建后 |
|---|---|---|
| Version | 12.0.97.3000 | **12.0.68.1606** |
| Type | Extracted | Extracted（构建产物都是这个） |
| SKU / Chipset | Corporate H / CNP-CMP-H B,A | 一致 |
| OEM Configuration | No | No |
| **File System State** | **Initialized** | **Configured** |
| Size | 0x77C000 | 0x77C000 |

---

## 8. 第四步：写入（只写 ME 区）

回到 UEFI Shell，确认 `me_amt.bin` 在当前目录（U 盘根目录）——用预置镜像的就是从仓库拷来的那个，
自己生成的就是 §7 裁出来的那个。然后跑 `write.nsh`，三步：

```
fpt.efi -me -d me_before.bin      ← 刷前备份，这台机的回滚点
fpt.efi -f me_amt.bin -me         ← 只写 ME 区，期间不能断电
fpt.efi -me -d me_after.bin       ← 回读
```

> **判据只有一个**
>
> `me_after.bin` 与 `me_amt.bin` 哈希一致。
> FPT 打印 `successful` 不算数——那只说明命令执行完了，不说明字节写对了。

本次实测：

```
me_amt.bin    ea31e562…f264
me_after.bin  ea31e562…f264     逐字节一致
```

收尾：

```
fpt.efi -greset        → 立即重启，让 ME 重新初始化
断电 → 拔电源线 → 取下跳线 → 上电
```

> **不要整片刷 `outimage.bin`。**
>
> 原帖的变砖就是整片刷造成的。我们只写 ME 区，BIOS 和描述符一个字节都不碰。

---

## 9. 第五步：MEBx 与验收

```
F2 → Manageability        应出现 Intel AMT，状态 Enabled
Ctrl+P → MEBx             默认密码 admin，首次登录强制改密码
                          （≥8 位，含大小写 + 数字 + 特殊字符）
```

MEBx 里的顺序：

| 菜单 | 设置 |
|---|---|
| `Intel(R) AMT Configuration` | `Manageability Feature Selection` = **Intel AMT** |
| 同上 → `User Consent` | 需要远程 KVM 就设 `KVM` 或 `All` |
| 同上 → `Network Setup` | 主机名 / 域名；`Activate Network Access` 拿 DHCP 地址 |
| `Mebx Exit` | 保存并重启 |

然后浏览器开 `http://<本机IP>:16992`。KVM 远程桌面走 `:16994`（或 VNC 5900）。

---

## 10. 避坑清单

全部是这次实际踩到的，按阶段分组。目标机侧只有 UEFI Shell，所以坑基本集中在"能不能读到 SPI"和"FIT 里换没换成"这两件事上。

### 读取阶段

| 坑 | 现象 | 解法 |
|---|---|---|
| 跳线没真正生效 | `Error 280` | 必须**拔电源线**后装跳线再上电，软关机不算 |
| Ventoy 引导 `fpt.efi` 失败 | 黑屏 / 秒退 | 别用 Ventoy：`fpt.efi` 不是启动项，且它的 exFAT 数据区 Shell 读不到。改用单 FAT32 U 盘，见 §4 |
| Shell 提示符是 `Shell>` | `dir` 报 `Current directory not specified` | 当前目录没设置。`map` → `fs0:` → `dir`，见 §4.4 |
| nsh 脚本报 `Unknown flag -i` | `echo` 行里出现以 `-` 开头的词 | EDK2 Shell 的 `echo` 会把 `-x` 当参数；`echo.` 也不认，空行用 `echo ` |
| U 盘空间不足 | dump 出来是残文件 | `full.bin` 32MB + `me.bin` 16MB，根目录至少留 100MB，见 §4.2 |

### FIT 阶段

| 坑 | 现象 | 解法 |
|---|---|---|
| 树里只有版本号、没有 AMT 节点 | `ME Binary File` 没换成功 | 中途点过 `File → Open` 会被重置回 `full.bin`，重新指向 RGN |
| **树里冒出满屏配置节点** | **以为成功了，但 TPM / 硬盘 / 声音出问题** | **这是整棵树被重置的信号，不是成功标志**（§6.2）。用 §6.6 的 XML 法修 |
| **开机报 `TPM could not be initialized`** | **换 ME 时 PTT 被重置成 No，fTPM 失效** | 照 §6.4 改回原厂值重刷，刷完在 BIOS 里 Clear TPM |
| 开机后没声音 / 硬盘少一块 | `HdaVoltSelect`、`SataPCIeComboPort2` 被 RGN 默认值改掉 | 同上，用 §6.6 恢复原厂配置 |
| FIT 把 FPT 挪了位置 | 原厂 FPT 在 `0x1000`，构建后变成 `0x634000` | 正常。区头 CSE Layout Table 第一项同步改了，ME 靠表定位 FPT，MEA 也能正常识别 |

### 运行阶段

| 坑 | 现象 | 解法 |
|---|---|---|
| BIOS 更新冲掉 AMT | 升级后又变回 ISM | BIOS 更新包带 ME 载荷（1.35.0 里是 `12.0.97.3000`）。顺序永远是**先升 BIOS，后改 ME** |

---

## 11. 能不能"通刷"？

**同型号 + 同 BIOS 版本，可以复用同一个 `me_amt.bin`。按芯片组通刷，不行。**

`me_amt.bin` 是"某台机器 + 某个 BIOS 版本"的 ME 区快照，它绑定三样东西：

| 绑定项 | 不同会怎样 |
|---|---|
| 区域大小（描述符定义） | 长度不符时 `fpt.efi -me -f` 直接拒绝，最坏只是"写不进去" |
| Boot Guard 配置（Profile + PCH strap） | 长度碰巧相同也可能开机失败（可用 `me_before.bin` 回滚） |
| ME SKU | `CON` / `LP` 平台刷了也不会有 AMT |

每台刷前必查：

```
fpt.efi -i      → CSME Base 0x3000 / Limit 0xFFFFFF（即 0xFFD000）
MEA me.bin      → SKU: Corporate H，Chipset: CNP/CMP-H B,A
CPU             → 支持 vPro
```

三条全过才能复用。**每台仍要单独留 `me_before.bin`**——1 号机的备份只能救 1 号机。

---

## 12. 扩展到其他平台

| 平台 | 芯片组 | ME 大版本（以 MEA 实测为准） | 工具 | RGN 可得性 | 结论 |
|---|---|---|---|---|---|
| 300 系 | Q370 | CSME 12.0 | FPT/FIT **12** | 好（12.0 COR_H_BA 有 68/70） | **已验证** |
| 400 系 | Q470 | CSME 12.0（CMP-H） | FPT/FIT **12** | 同家族 | **高**，流程照抄 |
| 500 系 | Q570 | CSME 14.x | FPT/FIT **14** | 需另找 14.x COR RGN | 中高 |
| 600 系 | Q670 | CSME 16.x | FPT/FIT **16** | 稀缺，多为 EXTR | 中，需试点 |

**Q670 额外三个风险**，建议只做到"导出 + MEA 判定 + 找 RGN"三步再决定：

1. RGN 极稀缺；
2. CSME 16 的 SVN / 回滚保护更严，跨版本替换没有公开成功案例；
3. 不少整机 / 主板取消了服务跳线，SPI 写保护绕不过去。

---

## 13. 风险与回滚

- **只写 ME 区**，BIOS / GbE / 描述符不落盘，不会走到"Bad Motherboard"那条路；
- ME 区写坏时，机器通常还能进 BIOS / Shell（BIOS 由 CPU 执行，与 ME 无关），用 `fpt.efi -f me_before.bin -me` 刷回；
- 真正不可恢复的情况需要 SPI 编程器（CH341A + SOP8 夹子）——但只要不动描述符和 BIOS，用不到；
- **换 ME 会让 TPM 密钥全部失效**（fTPM 的数据存在 ME 的 MFS 里）。开了 BitLocker 的机器下次启动会要求 48 位恢复密钥，动手前先备份；
- 拆机装跳线会影响保修；企业环境请确认合规再操作。

**应急卡（存手机里）：**

```
刷坏了 → fpt.efi -f me_before.bin -me → fpt.efi -greset → 断电取跳线
```

---

## 附：本次实测数据

| 项 | 值 |
|---|---|
| SPI | 32768KB，CSME `0x3000-0xFFFFFF`（`0xFFD000`） |
| 原 ME | `12.0.97.3000` / Extracted / Initialized |
| 新 ME | `12.0.68.1606` / Configured / Size `0x77C000` |
| RGN | `12.0.68.1606_COR_H_BA_PRD_RGN.bin`（13,225,984 B） |
| me_amt.bin | 16,764,928 B，SHA256 `ea31e562…f264` |
| 回读 | 与 me_amt.bin 逐字节一致 |
| 刷前备份 | 与首日 dump 仅差 1 字节（`0x146CCE`，运行期日志计数） |

---

## 参考来源

**社区原帖（方法与踩坑的源头）**

- win-raid：Intel CSME 驱动 / 固件 / 工具总帖（固件库入口在 B1 段）
  `https://winraid.level1techs.com/t/intel-csme-drivers-firmware-and-tools-for-me-2-15/30719`
- win-raid：OptiPlex 5070 开启 AMT 的成功案例（本文的路线依据，含三次失败记录）
  `https://winraid.level1techs.com/t/112351`

**固件来源（本文实际使用）**

- MEGA 固件库（社区主源，国内需代理，且 HTTP 代理会 502，要用 SOCKS5）
  `https://mega.nz/folder/2Q0klQpA#6o04nlV_4xqfx76tjvgi4g`
- Internet Archive 完整归档（本文从这里取的 RGN，592MB 7z，覆盖 CSME 11.00–15.40）
  `https://archive.org/details/intel-management-engine-me-converged-security-and-management-engine-csme-firmware`
  直链：
  `https://archive.org/download/intel-management-engine-me-converged-security-and-management-engine-csme-firmware/Intel%20Management%20Engine%20(ME)%2C%20Converged%20Security%20and%20Management%20Engine%20(CSME)%3B%20Firmware.7z`
- 用到的文件在归档内的 `CSME 12.0 Repository r33/` 目录：
  - `12.0.68.1606_COR_H_BA_PRD_RGN.bin`（本文使用）
  - `12.0.70.1652_COR_H_BA_PRD_RGN.bin`（备选）

**工具来源**

- MEAnalyzer（判断 SKU / 版本 / File System State）
  `https://github.com/platomav/MEAnalyzer`
- BIOSUtilities（Dell BIOS 更新包解包，用于确认 1.35.0 里带的 ME 载荷）
  `https://github.com/platomav/BIOSUtilities`
- EDK2 UEFI Shell（`ShellBinPkg`，`edk2-stable201903` 分支的 `Shell.efi`）
  `https://github.com/tianocore/edk2`
- Dell OptiPlex 5070 BIOS 1.35.0
  `https://downloads.dell.com/FOLDER13601562M/1/OptiPlex_5070_1.35.0.exe`

**说明**：ME 固件与 FPT/FIT 的版权归 Intel，此处仅作技术记录；商用分发前请自行确认授权与合规。

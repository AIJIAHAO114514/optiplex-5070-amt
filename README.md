# OptiPlex 5070 开启 vPro / AMT

> 用 FPT + FIT 把 Dell OptiPlex 5070 的 CSME 区域换成一版干净的 **RGN**，激活出厂被关掉的 Intel AMT。

一次在真机上跑通并验证的完整记录：原理、操作步骤、每一步的判据、以及真实踩过的坑。

---

## 为什么出厂没有 AMT

拆开机器看到 Q370，很多人会觉得"这台应该支持 vPro"。**它确实支持，只是被关掉了。** 分三层看：

**1｜硬件和固件都够**
AMT 需要三样东西同时成立：Q 系列芯片组、支持 vPro 的 CPU、Corporate（COR）版 ME 固件。5070 用的就是 COR 固件（实测 `SKU: Corporate H`），不是"固件缺这一块功能"。

**2｜Dell 在 ME 里关掉了 AMT，而且已经"定稿"**
出厂 ME 区在构建时 AMT 就是关闭状态；机器首次上电又完成了一次数据初始化，`File System State = Initialized`。配置写进 MFS 之后，FIT 打开它连配置树都不展开，改也改不进去——这才是"升级 ME、改 BIOS 都没用"的根因。

**3｜入口被藏起来了**
`Manageability` 菜单按 ME 上报的能力动态显示。ME 不报 AMT，F2 里要么没有这一项，要么显示为不可用，看起来就像"不支持"。

> 也有**真的不支持**的情况：非 vPro 的 CPU（i3、i5-9400 一类）。判断标准就两条——**CPU 是否 vPro、ME 是否 COR**。

---

## 结果

| 项 | 值 |
|---|---|
| 环境 | OptiPlex 5070 MT / Q370 / BIOS 1.35.0 / CSME 12.0（Corporate H） |
| ME 固件 | `12.0.97.3000 · Initialized` → `12.0.68.1606 · Configured` |
| 写入文件 | `me_amt.bin`，16,764,928 B（`0xFFD000`） |
| 回读校验 | 与写入文件**逐字节一致** |
| 结果 | F2 出现 Manageability，`Ctrl+P` 可进 MEBx，AMT 可配置 |

---

## 文档

| 文件 | 内容 |
|---|---|
| [docs/强刷ME激活vPro-AMT.md](docs/强刷ME激活vPro-AMT.md) | 完整实战：原理、FIT 操作、避坑清单、平台可行性 |
| [docs/SOP-AMT开启.md](docs/SOP-AMT开启.md) | 现场检查单，照着一步步做 |

---

## 仓库结构

```
README.md                 本文件
docs/
  强刷ME激活vPro-AMT.md    实战长文
  SOP-AMT开启.md          操作规范
  images/                文中配图的本地备份
uefi-shell/              目标机侧（拷到 FAT32 U 盘根目录）
  startup.nsh            进 Shell 自动打印文件系统 + 区域表
  dump.nsh               一键导出 full.bin + me.bin
  write.nsh              一键写入：备份 → 写 ME → 回读
  说明.txt               U 盘怎么放、Ventoy 为什么不行
tools/
  spi_region.py          Flash Descriptor 解析 / 按区裁剪 / 逐区比对
02_make_me.bat            台外 Windows：裁 ME 区 + 四道校验
_lib.cmd / config.cmd     02_make_me.bat 的依赖
```

---

## 快速开始

目标机侧全程在 **UEFI Shell** 里完成：不需要 PE，不需要 MEI 驱动，也不用往目标机装任何东西。EFI 版 FPT 直接调用 UEFI 的 SPI 协议。

```
① 目标机  dump.nsh                    → full.bin + me.bin
② 台外    FIT 换 RGN 并 Build         → outimage.bin
          02_make_me.bat fit-output    → me_amt.bin
③ 目标机  write.nsh                   → 写入 + 回读
```

U 盘准备：**整盘格 FAT32**（不必可引导），把 `uefi-shell/` 全部内容拷到根目录，形成 `\EFI\BOOT\BOOTX64.EFI` + `fpt.efi` + 三个 `.nsh`。F12 选 `UEFI: <U盘>` 直接进 Shell。

详细步骤见文档，尤其是 §4「准备：一个 FAT32 U 盘」。

---

## 前置条件

四条全过才值得动手：

| 条件 | 怎么查 | 不满足会怎样 |
|---|---|---|
| Q 系列芯片组 | Q370 / Q470 / Q570 / Q670… | B/H/Z 系列多数没有 AMT 硬件 |
| ME 是 Corporate | `MEA me.bin` → `SKU: Corporate H/LP` | `CON`（1.5MB）永远没有 AMT |
| SPI 可写 | `fpt.efi -i` 出区域表 + 服务跳线可装 | 写保护，报 `Error 280` |
| CPU 支持 vPro | i5-8500/8600/9500/9600、i7-8700/9700… | 刷了也不会有 AMT |

---

## 需要的固件与工具

本仓库**不包含**二进制文件，全部按官方渠道自行获取：

- **FPT / FIT / MEInfo**：Intel CSME System Tools v12 r36（版本要与 ME 大版本一致）
- **干净 RGN**：`12.0.68.1606_COR_H_BA_PRD_RGN.bin`，来自 win-raid 社区固件库或 Internet Archive 的 CSME 全量归档
- **MEA**：[platomav/MEAnalyzer](https://github.com/platomav/MEAnalyzer)
- **UEFI Shell**：EDK2 `ShellBinPkg`

出处与直链写在文档的「参考来源」一节。

---

## 风险

- **只写 ME 区**，BIOS / GbE / 描述符不落盘，不会走到整片刷坏那条路；
- 写入前会自动备份 `me_before.bin`，出问题用 `fpt.efi -f me_before.bin -me` 刷回；
- 拆机装服务跳线会影响保修，企业环境请确认合规后再操作；
- 每台机器都要单独留自己的 `me_before.bin`——别人的备份救不了这台。

---

## 说明

ME 固件、FPT、FIT 的版权归 Intel。本仓库只记录方法与自写脚本，不含任何 Intel 二进制或固件镜像。

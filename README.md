# OptiPlex 5070 开启 vPro / AMT

> 用 FPT + FIT 把 Dell OptiPlex 5070 的 CSME 区域换成一版干净的 **RGN**，激活出厂被关掉的 Intel AMT。

一次在真机上跑通并验证的完整记录：原理、操作步骤、每一步的判据，以及两个花了很久才搞明白的坑。

| 项 | 值 |
|---|---|
| 环境 | OptiPlex 5070 MT / Q370 / BIOS 1.35.0 / CSME 12.0（Corporate H） |
| ME 固件 | `12.0.97.3000 · Initialized` → `12.0.68.1606 · Configured` |
| 写入校验 | 回读哈希与写入文件逐字节一致 |
| 结果 | F2 出现 Manageability，`Ctrl+P` 进 MEBx，AMT 可配置 |

---

## 先看这条：换 ME 会重置整棵配置树

**这是本仓库最有价值的部分，也是最容易踩的坑。**

在 FIT 里把 `ME Binary File` 指向干净 RGN 的那一刻，FIT 会把整棵配置树**重置成 Intel 默认值**，不再继承 Dell 的定制。

我们拿同一台机器做了逐项对比（原厂 `full.bin` 的配置快照 vs 换 RGN 后构建出的镜像），**426 项里有 35 项被改**：

| 被改的项 | 原厂 | RGN 默认 | 后果 |
|---|---|---|---|
| `PttSupported` | **Yes** | **No** | **fTPM 失效，开机报 `TPM could not be initialized`** |
| `SataPCIeComboPort2` | **SATA** | **PCIe** | 接在这个口的硬盘消失 |
| `HdaVoltSelect` | **3.3V** | **1.8V** | 声卡供电不对，可能没声音 |
| `ClkoutSRC0/5/6/7/12/13/14/15` | Disabled | **Enabled** | 8 路时钟输出被凭空打开 |
| `FwUpdateOemId` | Dell 的 GUID | 全 0 | OEM ID 丢失 |
| `ProfileChangeable` | true | false | BIOS 里改不了 boot profile |
| `NvarPostManUnLckd` | No | Yes | 生产后 NVAR 可改，安全变松 |

> **关键认知：「换 RGN 后左边树冒出 AMT 节点」不是成功标志，而是整棵树被替换的信号。**
> 正确做法是先从原厂 dump 导出一份配置快照，换区后逐项对照，而不是只看 AMT 一项。

修复文件在 [`policy/fixed.xml`](policy/README.md)：以原厂快照为基底，只改 6 项 AMT，其余 420 项全部保留 Dell 原值。用它构建出的 ME 区，与错版的差异只有 **0.09%**（纯配置，代码一个模块没动）。

---

## 仓库结构

```
README.md
docs/
  强刷ME激活vPro-AMT.md    完整实战：原理 / FIT 操作 / 避坑 / 平台可行性
  SOP-AMT开启.md           现场检查单
policy/
  fixed.xml                FIT 项目快照：原厂配置 + 仅 6 项 AMT 改动
  README.md                配置漂移清单 + fixed.xml 用法
firmware/
  me_amt.bin               预置 ME 区域镜像（5070 / BIOS 1.35.0 可直接刷）
  README.md                适用条件、风险、怎么用
uefi-shell/                目标机侧（拷到 FAT32 U 盘根目录）
  startup.nsh              进 Shell 自动打印文件系统 + 区域表
  dump.nsh                 一键导出 full.bin + me.bin
  write.nsh                一键写入：备份 → 写 ME → 回读
  说明.txt                 U 盘怎么放、Ventoy 为什么不行
tools/
  spi_region.py            Flash Descriptor 解析 / 按区裁剪 / 逐区比对
02_make_me.bat             台外 Windows：裁 ME 区 + 四道强制校验
_lib.cmd / config.cmd      上面那个的依赖
```

---

## 快速开始

目标机侧全程在 **UEFI Shell** 里完成：不需要 PE，不需要 MEI 驱动，也不用往目标机装任何东西。EFI 版 FPT 直接调用 UEFI 的 SPI 协议。

```
① 目标机  dump.nsh                    → full.bin + me.bin
② 台外    FIT 打开 full.bin，换 RGN    → outimage.bin
          02_make_me.bat fit-output    → me_amt.bin
③ 目标机  write.nsh                   → 写入 + 回读
```

U 盘准备：**整盘格 FAT32**（不必可引导），把 `uefi-shell/` 全部内容拷到根目录，形成 `\EFI\BOOT\BOOTX64.EFI` + `fpt.efi` + 三个 `.nsh`。F12 选 `UEFI: <U盘>` 直接进 Shell。

详细步骤见 [docs/强刷ME激活vPro-AMT.md](docs/强刷ME激活vPro-AMT.md)，尤其是 §4「准备：一个 FAT32 U 盘」。

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

## 预置镜像 vs 自己生成

| | 直接刷 `firmware/me_amt.bin` | 自己走完整流程 |
|---|---|---|
| 适用 | 5070 + BIOS 1.35.0，ME 区长度 `0xFFD000` | 任何同代 Q 系列机型 |
| 前提 | `fpt.efi -i` 确认长度一致 | 先导出自己的 `full.bin` |
| 风险 | 机型/BIOS 不符时配置可能不匹配 | 全流程可控，配置来自本机 |
| 耗时 | 10 分钟 | 40 分钟/台 |

**批量部署同型号机器时用前者，其他情况用后者。** 每台机器都必须单独留自己的 `me_before.bin`——别人的备份救不了这台。

---

## 需要的固件与工具

本仓库只提供**预置的 ME 区域镜像**（`firmware/me_amt.bin`），不含 FPT / FIT / MEA 等 Intel 工具，按官方渠道自行获取：

- **FPT / FIT**：Intel CSME System Tools v12 r36（版本要与 ME 大版本一致）
- **干净 RGN**：`12.0.68.1606_COR_H_BA_PRD_RGN.bin`，来自 win-raid 社区固件库或 Internet Archive 的 CSME 全量归档
- **MEA**：[platomav/MEAnalyzer](https://github.com/platomav/MEAnalyzer)
- **UEFI Shell**：EDK2 `ShellBinPkg`

出处与直链写在文档的「参考来源」一节。

---

## 风险

- **只写 ME 区**，BIOS / GbE / 描述符不落盘，不会走到整片刷坏那条路；
- 写入前自动备份 `me_before.bin`，出问题用 `fpt.efi -f me_before.bin -me` 刷回；
- **开了 BitLocker 的机器**，换 ME 会让 TPM 状态丢失，下次启动要求 48 位恢复密钥，动手前先备份；
- **BIOS 更新会覆盖 ME**（更新包带 ME 载荷），顺序永远是先升 BIOS、后改 ME；
- 拆机装服务跳线会影响保修，企业环境请确认合规后再操作。

---

## 说明

ME 固件、FPT、FIT 的版权归 Intel。`firmware/me_amt.bin` 是本站机器构建出的区域镜像，仅作技术记录与同型号机器的部署便利；其他 Intel 二进制未包含在本仓库中。

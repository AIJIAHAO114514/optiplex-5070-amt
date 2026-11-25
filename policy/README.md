# policy/fixed.xml —— 原厂配置基准 + 只改 AMT 的 FIT 项目文件

## 这个文件解决的问题

在 FIT 里把 `ME Binary File` 指向干净 RGN 的那一刻，**FIT 会把整棵配置树重置成 Intel 默认值**，不再继承 Dell 的定制。

实测对比同一台 5070（原厂 `full.bin` vs 换 RGN 后构建的 `outimage.bin`），**426 项配置里有 35 项被改**：

| 被改的项 | 原厂 | RGN 默认 | 后果 |
|---|---|---|---|
| `PttSupported` | **Yes** | **No** | **fTPM 失效，开机报 `TPM could not be initialized`** |
| `PttPwrUpState` | Enabled | Disabled | 同上 |
| `SataPCIeComboPort2` | **SATA** | **PCIe** | 接在这个口的硬盘消失 |
| `HdaVoltSelect` | **3.3V** | **1.8V** | 声卡 codec 供电不对，可能没声音 |
| `ClkoutSRC0/5/6/7/12/13/14/15` | Disabled | **Enabled** | 8 路时钟输出被凭空打开 |
| `FwUpdateOemId` | `68853622-EED3-4E83-8A86-6CDE315F6B78` | 全 0 | Dell 的 OEM ID 丢失 |
| `ProfileChangeable` | true | false | BIOS 里改不了 boot profile |
| `NvarPostManUnLckd` | No | Yes | 生产后 NVAR 变成可改，安全变松 |
| `DbgOverridePreProdSi` | `0x0` | `0x8` | 调试位被置位 |

**关键认知：「换 RGN 后左边树冒出 AMT 节点」不是成功标志，而是整棵树被替换的信号。**

## 这个文件怎么做的

以**原厂 full.bin 导出的项目快照**为基底，只改 6 项 AMT：

```
AmtSupported              No       -> Yes
NetServicesSupported      No       -> Yes
MngAppSupported           No       -> Yes
MngAppPowerUpState        Disabled -> Enabled
KvmSupported              No       -> Yes
AmtIdleTimeout            0x0001   -> 0xFFFF
```

其余 420 项（含 PTT、Boot Guard、SATA 复用、音频电压、时钟输出）全部保持 Dell 原值。

产物验证：新 ME 区与"错版"的差异只有 **0.09%**（15,877 字节，纯配置），代码一个模块没动。

## 怎么用

**前提**：你已经用自己的 `full.bin` 打开过一次 FIT，生成了 Decomp 目录（里面有 `ME Sub Partition.bin` 等文件）。

```
1. 用文本编辑器打开 policy/fixed.xml
   把所有绝对路径改成你自己的（原作者的是 D:\optiplex5070-amt\fit-work\...）：
     - MeRegionFile    -> 你构建出的 ME 代码子分区
     - BIOS / GbE / PMC / OemBinary / EcRegionPointer -> 你自己的 Decomp 文件

2. FIT -> File -> Open -> 选改好的 fixed.xml

3. ★ 关键验证：点开 Intel (R) PTT Configuration
     确认 PTT Supported = Yes、initial power-up state = Enabled
     如果显示 No，说明 FIT 又按 ME 文件重置了配置，停下，改用「手工逐项改」方案

4. Build -> Build Image
     （弹 Boot Guard Profile 5 - FVME 确认框，点 Yes）

5. 02_make_me.bat fit-output  ->  me_amt.bin
```

## 关于 `Build FWUpdate` 的警告

Build 时会生成两个文件：

```
cse_image_FWU_Base_WARNING.txt
cse_image_FWU_Full_WARNING.txt
```

内容都是：

```
FW image for FW Update was NOT created!
  Reason: CSE FW from a decomposed IFWI image was used.
```

**无害。** 这条警告只针对 `Build → Build FWUpdate`（生成 FWUpdate 包），因为我们用的 ME 源是从镜像里分解出来的，Intel 只允许用原始发布的 CSE 镜像做 FWU 包。

本流程用的是 `fpt -me -f` 直接写 ME 区，**不需要 FWUpdate 包**。`Build Image` 不受影响。

## 带 `[FPF]` 的项一律不要动

树里凡是有 `[FPF]` 后缀的（`PTT Supported [FPF]`、`Boot Guard Profile Configuration [FPF]` 等），都是**写熔丝**，烧断不可逆。看一眼可以，不要改。

## 这个文件不能直接拿来 Build

里面的路径是原作者机器的目录结构。直接打开会因为找不到文件而失败。**必须先改路径**，见上面第 1 步。

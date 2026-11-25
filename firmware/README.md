# firmware/me_amt.bin —— 预置 ME 区域镜像

```
大小      16,764,928 字节（0xFFD000）
SHA256    0894af9ce8f97ea0bbc97cb2d34ec0040ffa6670926ce574540e14698cbdb613
```

## 里面是什么

一块**完整可写入的 CSME 区域镜像**，由三部分组成：

| 组成 | 来源 |
|---|---|
| 固件代码 | Intel CSME **12.0.68.1606**（Corporate H，取自 Intel 原厂 RGN） |
| 配置数据 | **Dell OptiPlex 5070 / BIOS 1.35.0 的原厂配置**（426 项里的 420 项原样保留） |
| AMT 相关 | 6 项已改为启用（AMT / ME Network Services / Manageability App / KVM / 空闲超时） |

MEA 判定：`Version 12.0.68.1606` / `Type Extracted` / `SKU Corporate H` / `File System State Configured` / `Size 0x77C000`

`Configured` 是关键——ME 已完成数据初始化，AMT 参数已落盘，刷完就能进 MEBx。

## 什么情况下能直接刷

**三条同时满足才行**：

| 条件 | 怎么查 | 不符的后果 |
|---|---|---|
| 机器是 **OptiPlex 5070**（同代同 BIOS 的 7070 可试） | 机箱标签 | 配置项与硬件不匹配 |
| BIOS 是 **1.35.0** | 开机 F2，或 `wmic bios get smbiosbiosversion` | ME 区长度可能不同 |
| ME 区长度 = **`0xFFD000`** | `fpt.efi -i` 看 CSME 的 Base / Limit | `fpt -me -f` 直接拒绝，刷不进去 |

长度不符是**硬拦截**——`fpt` 自己会拒绝，不会写坏。这是唯一能放心的地方。

## 但它不是"通用固件"

这是**一台具体机器（BIOS 1.35.0）的快照**，不是 Intel 或 Dell 发布的通用包。它绑定：

- **区域大小**（`0xFFD000`，由描述符决定）
- **Boot Guard 配置**（Profile 5 - FVME + PCH strap）
- **PTT / TPM 相关配置**（这台机器用 fTPM，`PTT Supported = Yes`）

换成别的机型、别的 BIOS 版本，即使长度碰巧相同，也可能开不了机（能回滚，但麻烦）。

## 风险，说清楚

1. **刷坏了要靠自己的 `me_before.bin` 救**。刷之前必须先 dump 一份本机 ME 区，`write.nsh` 会自动做（Step 1），也可以手动 `fpt.efi -me -d me_before.bin`。
2. **开了 BitLocker 的机器**，换 ME 会导致 TPM 状态丢失，下次启动要求 48 位恢复密钥。先备份密钥或挂起 BitLocker。
3. **BIOS 更新会覆盖它**。Dell 的 BIOS 更新包带 ME 载荷（1.35.0 里是 `12.0.97.3000`），升完 BIOS 后 AMT 会掉回 ISM，需要重刷一次。顺序永远是：先升 BIOS，后改 ME。
4. **版权**：固件代码版权归 Intel。这份文件仅作技术记录与同型号机器的批量部署便利，商用分发前请自行确认授权与合规。

## 怎么刷

```
1. 把本文件拷到 FAT32 U 盘根目录，文件名保持 me_amt.bin
2. U 盘根目录还要有：fpt.efi、write.nsh、EFI\BOOT\BOOTX64.EFI
3. F12 → UEFI: <U盘> → 进 Shell
4. 跑 write.nsh（备份 → 写 ME → 回读）
5. 断电 → 拔电源线 → 上电
6. F2 → Security → TPM → Clear TPM
```

详细步骤见 [docs/强刷ME激活vPro-AMT.md](../docs/强刷ME激活vPro-AMT.md)。

## 想自己生成一份

不要用别人的快照，走完整流程：

```
① 目标机  dump.nsh                    → full.bin + me.bin
② 台外    FIT 打开 full.bin，换 RGN    → outimage.bin
          02_make_me.bat fit-output    → me_amt.bin
③ 目标机  write.nsh                   → 写入 + 回读
```

生成之前先看 [policy/fixed.xml](../policy/README.md)——**这一步决定了你会不会踩配置漂移的坑**。

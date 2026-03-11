#!/bin/bash

# ==========================================
# 脚本名称: setswap.sh
# 功能: 动态创建或调整 Swap 分区大小 (GitHub Action 复刻版)
# 用法: sudo ./setswap.sh [大小(GB)]
# 示例: sudo ./setswap.sh 16  (创建一个 16GB 的 swap)
# ==========================================

set -euo pipefail

SWAP_SIZE_GB=${1:-0}

if ! [[ "$SWAP_SIZE_GB" =~ ^[0-9]+$ ]]; then
    echo "错误: 请输入整数作为 Swap 大小 (GB)!"
    exit 1
fi

if [[ "$SWAP_SIZE_GB" = 0 ]]; then
    echo "错误: 请设置一个大于0的整数作为 Swap 大小 (GB)!"
    exit 1
fi

echo "准备设置 Swap 大小为: ${SWAP_SIZE_GB} GB"
echo "----------------------------------------"
echo ">>> 修改前的内存与 Swap 状态:"
free -h
echo
swapon --show || true
echo "----------------------------------------"

# 获取当前活动的 swap 文件（如果有）
SWAP_FILE=$(swapon --noheadings --show=NAME | tail -n 1 || true)

if [ -n "$SWAP_FILE" ] && [ -f "$SWAP_FILE" ]; then
    echo "检测到旧 Swap 文件: $SWAP_FILE"
    # 尝试卸载旧 swap，如果未激活则忽略错误
    sudo swapoff "$SWAP_FILE" || echo "无法卸载 $SWAP_FILE (可能未激活)"
    # 删除旧文件
    sudo rm -f "$SWAP_FILE"
    echo "旧 Swap 文件已清除。"
else
    echo "未检测到活动 Swap，将使用默认路径: /swapfile"
    SWAP_FILE=/swapfile
fi

# 检测目标目录的文件系统类型，以选择分配策略
# $(dirname "$SWAP_FILE") 获取文件所在目录，通常是 /
FS_TYPE=$(df --output=fstype "$(dirname "$SWAP_FILE")" | tail -n 1)

echo "将在 $SWAP_FILE 创建 Swap，文件系统类型: $FS_TYPE"

# 根据文件系统类型选择创建方式
if [[ "$FS_TYPE" == "xfs" || "$FS_TYPE" == "btrfs" ]]; then
    echo "检测到 $FS_TYPE 文件系统，使用 dd 命令以保证兼容性..."
    # 使用 dd 创建。bs=1M, count=Size*1024 (即 Size + K 后缀)
    # 例如 10GB -> count=10K -> 10*1024 = 10240 * 1MB = 10GB
    sudo dd if=/dev/zero of="$SWAP_FILE" bs=1M count="${SWAP_SIZE_GB}K" status=progress
else
    echo "使用 fallocate 快速预分配..."
    sudo fallocate -l "${SWAP_SIZE_GB}G" "$SWAP_FILE"
fi

# 设置权限 (必须为 600，只有 root 可读写)
sudo chmod 600 "$SWAP_FILE"

# 针对 Btrfs 的特殊优化 (禁用 CoW 和压缩)
if [[ "$FS_TYPE" == "btrfs" ]]; then
    echo "针对 Btrfs 禁用 CoW (写时复制) 和压缩..."
    sudo chattr +C "$SWAP_FILE" || echo "chattr +C 失败，继续尝试..."
    sudo btrfs property set "$SWAP_FILE" compression none || echo "禁用压缩失败"
fi

# 初始化 Swap 文件
echo "正在格式化 Swap 文件..."
if sudo mkswap "$SWAP_FILE"; then
    echo "Swap 文件格式化成功。"
else
    echo "警告: mkswap 失败。文件可能无效。"
fi

echo "正在启用 Swap..."
if sudo swapon "$SWAP_FILE"; then
    echo "成功! Swap 已启用: $SWAP_FILE"
else
    echo "警告: swapon 失败 (可能是容器权限限制)。将在无 Swap 状态下继续。"
fi

echo "----------------------------------------"
echo ">>> 修改后的内存与 Swap 状态:"
free -h
echo
swapon --show || true
echo
echo "Swap 设置脚本执行完毕。"

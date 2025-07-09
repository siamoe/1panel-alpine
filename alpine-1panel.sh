#!/bin/bash

# --- 兼容性处理：处理 DOS 换行符 ---
# 检查 dos2unix 是否存在，优先使用
if command -v dos2unix &> /dev/null; then
    dos2unix "$0"
# 如果 dos2unix 不存在，尝试使用 sed
elif command -v sed &> /dev/null; then
    sed -i 's/\r$//' "$0"
fi

# --- 依赖检查与安装：curl 和 sha256sum ---
# 检查 curl 命令是否存在，不存在则安装
if ! command -v curl &> /dev/null; then
    echo "[1Panel-Alpine Install Log]: 'curl' 命令未找到，正在安装..."
    apk add curl || { echo "[1Panel-Alpine Install Log]: 安装 'curl' 失败。请检查网络连接或手动安装。" >&2; exit 1; }
fi

# 检查 sha256sum 命令是否存在，不存在则安装 (由 openssl 包提供)
if ! command -v sha256sum &> /dev/null; then
    echo "[1Panel-Alpine Install Log]: 'sha256sum' 命令未找到，正在安装 'openssl'..."
    apk add openssl || { echo "[1Panel-Alpine Install Log]: 安装 'openssl' (用于 sha256sum) 失败。请检查网络连接或手动安装。" >&2; exit 1; }
fi

# --- Docker 自动安装 ---
# 检查 Docker 是否已安装
if ! command -v docker &> /dev/null; then
    echo "[1Panel-Alpine Install Log]: 检测到 Docker 未安装，开始自动安装 Docker..."

    # 确保 community 仓库已启用
    if ! grep -q "community" /etc/apk/repositories; then
        # 动态获取 Alpine 版本，例如 v3.20
        ALPINE_VERSION=$(cut -d'.' -f1,2 /etc/alpine-release)
        echo "http://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/community" >> /etc/apk/repositories
        echo "[1Panel-Alpine Install Log]: 已添加 'community' 仓库。"
    fi
    apk update || { echo "[1Panel-Alpine Install Log]: apk update 失败。请检查网络连接。" >&2; exit 1; }

    # 安装 Docker 及其依赖包
    apk add docker docker-cli --no-cache || {
        echo "[1Panel-Alpine Install Log]: Docker 核心组件安装失败。请检查网络连接或手动安装 Docker。" >&2; exit 1;
    }

    # 启动 Docker 服务并设置开机自启
    echo "[1Panel-Alpine Install Log]: 启动 Docker 服务并设置开机自启..."
    rc-service docker start || { echo "[1Panel-Alpine Install Log]: Docker 服务启动失败。请检查系统日志。" >&2; exit 1; }
    rc-update add docker boot

    echo "[1Panel-Alpine Install Log]: Docker 已成功安装并启动。"
else
    echo "[1Panel-Alpine Install Log]: 检测到 Docker 已安装，跳过安装步骤。"
fi

# --- 架构检测 ---
osCheck=$(uname -a)
if [[ $osCheck =~ 'x86_64' ]]; then
    architecture="amd64"
elif [[ $osCheck =~ 'arm64' ]] || [[ $osCheck =~ 'aarch64' ]]; then
    architecture="arm64"
elif [[ $osCheck =~ 'armv7l' ]]; then
    architecture="armv7"
elif [[ $osCheck =~ 'ppc64le' ]]; then
    architecture="ppc64le"
elif [[ $osCheck =~ 's390x' ]]; then
    architecture="s390x"
elif [[ $osCheck =~ 'riscv64' ]]; then
    architecture="riscv64"
else
    echo "[1Panel-Alpine Install Log]: 当前系统架构不支持。请参考官方文档选择支持的系统。" >&2
    exit 1
fi

# --- 安装模式设置 ---
if [[ ! ${INSTALL_MODE} ]]; then
    INSTALL_MODE="stable"
else
    if [[ ${INSTALL_MODE} != "dev" && ${INSTALL_MODE} != "stable" ]]; then
        echo "[1Panel-Alpine Install Log]: 请输入正确的安装模式 (dev 或 stable)。" >&2
        exit 1
    fi
fi

# --- 获取最新版本信息 ---
echo "[1Panel-Alpine Install Log]: 正在获取最新版本信息 (${INSTALL_MODE} 模式)..."
VERSION=$(curl -s https://resource.1panel.pro/${INSTALL_MODE}/latest)
HASH_FILE_URL="https://resource.1panel.pro/${INSTALL_MODE}/${VERSION}/release/checksums.txt"

if [[ "x${VERSION}" == "x" ]]; then
    echo "[1Panel-Alpine Install Log]: 获取最新版本失败，请稍后再试。" >&2
    exit 1
fi

# --- 准备下载信息 ---
PACKAGE_FILE_NAME="1panel-${VERSION}-linux-${architecture}.tar.gz"
PACKAGE_DOWNLOAD_URL="https://resource.1panel.pro/${INSTALL_MODE}/${VERSION}/release/${PACKAGE_FILE_NAME}"
EXPECTED_HASH=$(curl -s "$HASH_FILE_URL" | grep "$PACKAGE_FILE_NAME" | awk '{print $1}')

# --- 检查本地安装包并验证哈希 ---
if [[ -f ${PACKAGE_FILE_NAME} ]]; then
    echo "[1Panel-Alpine Install Log]: 本地发现安装包 '${PACKAGE_FILE_NAME}'，正在校验哈希..."
    actual_hash=$(sha256sum "$PACKAGE_FILE_NAME" | awk '{print $1}')
    if [[ "$EXPECTED_HASH" == "$actual_hash" ]]; then
        echo "[1Panel-Alpine Install Log]: 安装包哈希校验一致。跳过下载。"
        echo "[1Panel-Alpine Install Log]: 正在解压旧的安装目录 (如果存在)..."
        rm -rf 1panel-${VERSION}-linux-${architecture} # 清理旧目录，防止解压冲突
        tar zxf ${PACKAGE_FILE_NAME} || { echo "[1Panel-Alpine Install Log]: 解压现有安装包失败。" >&2; exit 1; }
        cd 1panel-${VERSION}-linux-${architecture} || { echo "[1Panel-Alpine Install Log]: 进入解压目录失败。" >&2; exit 1; }
        echo "[1Panel-Alpine Install Log]: 正在执行 1Panel 内部安装脚本..."
        /bin/bash install.sh
        exit 0
    else
        echo "[1Panel-Alpine Install Log]: 安装包哈希值不一致，重新下载。"
        rm -f ${PACKAGE_FILE_NAME} # 删除不一致的包
    fi
fi

# --- 下载安装包 ---
echo "[1Panel-Alpine Install Log]: 开始下载 1Panel ${VERSION} 安装包..."
echo "[1Panel-Alpine Install Log]: 安装包下载地址: ${PACKAGE_DOWNLOAD_URL}"

curl -LOk "${PACKAGE_DOWNLOAD_URL}" || { echo "[1Panel-Alpine Install Log]: 下载安装包失败。请检查网络连接或下载地址。" >&2; exit 1; }

if [[ ! -f ${PACKAGE_FILE_NAME} ]]; then
    echo "[1Panel-Alpine Install Log]: 下载的安装包文件不存在。" >&2
    exit 1
fi

# --- 解压并执行安装脚本 ---
echo "[1Panel-Alpine Install Log]: 正在解压安装包..."
tar zxf ${PACKAGE_FILE_NAME} || {
    echo "[1Panel-Alpine Install Log]: 解压安装包失败。文件可能损坏或下载不完整。" >&2
    rm -f ${PACKAGE_FILE_NAME}
    exit 1
}

# 进入解压后的目录
cd 1panel-${VERSION}-linux-${architecture} || { echo "[1Panel-Alpine Install Log]: 进入解压目录失败。" >&2; exit 1; }

echo "[1Panel-Alpine Install Log]: 正在执行 1Panel 内部安装脚本..."
/bin/bash install.sh

echo "[1Panel-Alpine Install Log]: ======================= 1Panel 安装流程结束 ======================="

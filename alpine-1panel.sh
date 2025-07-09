#!/bin/bash

# 安装必要的工具
# Alpine Linux 默认不包含 curl 和 sha256sum，需要先安装
if ! command -v curl &> /dev/null; then
    echo "curl command not found, installing..."
    apk add curl || { echo "Failed to install curl. Exiting."; exit 1; }
fi

if ! command -v sha256sum &> /dev/null; then
    echo "sha256sum command not found, installing..."
    apk add openssl || { echo "Failed to install openssl for sha256sum. Exiting."; exit 1; }
fi

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
    echo "当前系统架构不支持。请参考官方文档选择支持的系统。"
    exit 1
fi

if [[ ! ${INSTALL_MODE} ]]; then
    INSTALL_MODE="stable"
else
    if [[ ${INSTALL_MODE} != "dev" && ${INSTALL_MODE} != "stable" ]]; then
        echo "请输入正确的安装模式 (dev 或 stable)"
        exit 1
    fi
fi

VERSION=$(curl -s https://resource.1panel.pro/${INSTALL_MODE}/latest)
HASH_FILE_URL="https://resource.1panel.pro/${INSTALL_MODE}/${VERSION}/release/checksums.txt"

if [[ "x${VERSION}" == "x" ]]; then
    echo "获取最新版本失败，请稍后再试"
    exit 1
fi

PACKAGE_FILE_NAME="1panel-${VERSION}-linux-${architecture}.tar.gz"
PACKAGE_DOWNLOAD_URL="https://resource.1panel.pro/${INSTALL_MODE}/${VERSION}/release/${PACKAGE_FILE_NAME}"
# 在 Alpine 的 BusyBox awk 中，'print $1' 应该没问题，但为了稳妥，用 grep 再过滤一次
EXPECTED_HASH=$(curl -s "$HASH_FILE_URL" | grep "$PACKAGE_FILE_NAME" | awk '{print $1}')

if [[ -f ${PACKAGE_FILE_NAME} ]]; then
    # Alpine 的 sha256sum 来自 openssl，输出格式与 GNU sha256sum 相同，可以直接使用 awk
    actual_hash=$(sha256sum "$PACKAGE_FILE_NAME" | awk '{print $1}')
    if [[ "$EXPECTED_HASH" == "$actual_hash" ]]; then
        echo "安装包已存在，跳过下载。"
        rm -rf 1panel-${VERSION}-linux-${architecture}
        tar zxf ${PACKAGE_FILE_NAME}
        cd 1panel-${VERSION}-linux-${architecture}
        /bin/bash install.sh
        exit 0
    else
        echo "安装包已存在，但哈希值不一致。重新开始下载"
        rm -f ${PACKAGE_FILE_NAME}
    fi
fi

echo "开始下载 1Panel ${VERSION}"
echo "安装包下载地址: ${PACKAGE_DOWNLOAD_URL}"

curl -LOk ${PACKAGE_DOWNLOAD_URL}
if [[ ! -f ${PACKAGE_FILE_NAME} ]]; then
    echo "下载安装包失败"
    exit 1
fi

tar zxf ${PACKAGE_FILE_NAME}
if [[ $? != 0 ]]; then
    echo "下载安装包失败"
    rm -f ${PACKAGE_FILE_NAME}
    exit 1
fi
cd 1panel-${VERSION}-linux-${architecture}

/bin/bash install.sh
#!/bin/bash
# from
# https://github.com/oneclickvirt/pve
# 2025.05.09

# 打印信息
_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading() { read -rp "$(_green "$1")" "$2"; }
utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "UTF-8|utf8")
if [[ -z "$utf8_locale" ]]; then
    echo "No UTF-8 locale found"
else
    export LC_ALL="$utf8_locale"
    export LANG="$utf8_locale"
    export LANGUAGE="$utf8_locale"
    echo "Locale set to $utf8_locale"
fi

if [ -f "/usr/local/bin/build_backend_pve.txt" ]; then
    _green "You have already executed this script, if you have already rebooted your system, please execute the subsequent script commands to automatically configure the gateway, if you have not rebooted your system, please reboot your system"
    _green "Do not run this script repeatedly"
    _green "你已执行过本脚本，如果已重启过系统，请执行后续的自动配置网关的脚本命令，如果未重启过系统，请重启系统"
    _green "不要重复运行本脚本"
    exit 1
fi

# 创建资源池
POOL_ID="mypool"
if pvesh get /pools/$POOL_ID >/dev/null 2>&1; then
    _green "Resource pool $POOL_ID already exists!"
    _green "资源池 $POOL_ID 已经存在！"
else
    # 如果不存在则创建
    _green "Creating resource pool $POOL_ID..."
    _green "正在创建资源池 $POOL_ID..."
    pvesh create /pools --poolid $POOL_ID
    _green "Resource pool $POOL_ID has been created!"
    _green "资源池 $POOL_ID 已创建！"
fi

# 移除订阅弹窗
pve_version=$(dpkg-query -f '${Version}' -W proxmox-ve 2>/dev/null | cut -d'-' -f1)
cp -rf /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js.bak
sed -Ezi.bak "s/(Ext.Msg.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
sed -i.bak "s/data.status !== 'Active'/false/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js

# 开启硬件直通
if [ $(dmesg | grep -e DMAR -e IOMMU | wc -l) = 0 ]; then
    _yellow "Hardware does not support passthrough"
    _yellow "硬件不支持直通"
else
    if [ $(cat /proc/cpuinfo | grep Intel | wc -l) = 0 ]; then
        iommu="amd_iommu=on"
    else
        iommu="intel_iommu=on"
    fi
    if [ $(grep $iommu /etc/default/grub | wc -l) = 0 ]; then
        sed -i 's|quiet|quiet '$iommu'|' /etc/default/grub
        update-grub
        if [ $(grep "vfio" /etc/modules | wc -l) = 0 ]; then
            echo 'vfio
            vfio_iommu_type1
            vfio_pci
            vfio_virqfd' >>/etc/modules
        fi
    else
        _green "Hardware passthrough is set"
        _green "已设置硬件直通"
    fi
fi

# 检测固件安装
arch=$(uname -m)
if [[ "$arch" == "arm"* || "$arch" == "aarch64" ]]; then
    pve_version=$(pveversion | cut -d '/' -f 2)
    major=$(echo "$pve_version" | cut -d '.' -f 1)
    minor=$(echo "$pve_version" | cut -d '.' -f 2 | cut -d '-' -f 1)
    version=$(echo "$major.$minor" | bc)
    _green "Detected architecture: $arch"
    _green "Detected Proxmox VE version: $version"
    if (( $(echo "$version < 8.1" | bc -l) )); then
        _green "Installing pve-edk2-firmware for Proxmox VE < 8.1..."
        apt download pve-edk2-firmware=3.20220526-1
        dpkg -i pve-edk2-firmware_3.20220526-1_all.deb
    else
        _green "Installing pve-edk2-firmware-aarch64 for Proxmox VE >= 8.1..."
        apt download pve-edk2-firmware-aarch64=3.20220526-rockchip
        dpkg -i pve-edk2-firmware-aarch64_3.20220526-rockchip_all.deb
    fi
fi

# 检测AppArmor模块
if ! dpkg -s apparmor >/dev/null 2>&1; then
    _green "AppArmor is being installed..."
    _green "正在安装 AppArmor..."
    apt-get update
    apt-get install -y apparmor
fi
if [ $? -ne 0 ]; then
    apt-get install -y apparmor --fix-missing
fi
if ! systemctl is-active --quiet apparmor.service; then
    _green "Starting the AppArmor service..."
    _green "启动 AppArmor 服务..."
    systemctl enable apparmor.service
    systemctl start apparmor.service
fi
if ! lsmod | grep -q apparmor; then
    _green "Loading AppArmor kernel module..."
    _green "正在加载 AppArmor 内核模块..."
    modprobe apparmor
fi
sleep 3
installed_kernels=($(dpkg -l 'pve-kernel-*' | awk '/^ii/ {print $2}' | cut -d'-' -f3- | sort -V))
if [ ${#installed_kernels[@]} -gt 0 ]; then
    latest_kernel=${installed_kernels[-1]}
    _green "PVE latest kernel: $latest_kernel"
    _yellow "Please execute reboot to reboot the system to load the PVE kernel."
    _yellow "请执行 reboot 重新启动系统加载PVE内核"
else
    _yellow "The current kernel is already a PVE kernel, no need to reboot the system to update the kernel"
    _yellow "当前内核已是PVE内核，无需重启系统更新内核"
    _yellow "However, a reboot will ensure that some of the hidden settings are loaded successfully, so be sure to reboot the server once if you are in a position to do so."
    _yellow "但重启可以保证部分隐藏设置加载成功，有条件务必重启一次服务器"
fi
echo "1" >"/usr/local/bin/build_backend_pve.txt"

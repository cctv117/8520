#!/bin/bash

# =============================================================================
# Android内核构建脚本
# 版本: 1.0
# 功能: 支持AOSP/MIUI双版本构建，集成KernelSU和SUSFS补丁
# =============================================================================

# 颜色定义用于终端输出
yellow='\033[0;33m'
white='\033[0m'
red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
cyan='\033[0;36m'

# 输出带颜色的消息函数
color_echo() {
    local color=$1
    shift
    echo -e "${color}$*${white}"
}

# 打印分隔线
print_separator() {
    color_echo "$cyan" "=============================================="
}

# 打印步骤标题
print_step() {
    local step_name="$1"
    print_separator
    color_echo "$green" "$step_name"
    print_separator
}

# 错误处理函数
error_exit() {
    color_echo "$red" "错误: $1"
    exit 1
}

# 成功函数
print_success() {
    color_echo "$green" "✓ $1"
}

# 信息函数
print_info() {
    color_echo "$blue" "ℹℹ $1"
}

# 警告函数
print_warning() {
    color_echo "$yellow" "警告: $1"
}

# 确保脚本在遇到错误时退出
set -e

TOOLCHAIN_PATH=$HOME/zyc-clang/bin
GIT_COMMIT_ID=$(git rev-parse --short=8 HEAD)

# 参数解析
TARGET_DEVICE=$1
KSU_TYPE=$2
BUILD_TYPE=$3

# 显示实际接收到的参数
print_info "接收到的参数:"
print_info "参数1 (设备): '$TARGET_DEVICE'"
print_info "参数2 (KSU类型): '$KSU_TYPE'"
print_info "参数3 (构建类型): '$BUILD_TYPE'"

# 显示使用说明
show_usage() {
    color_echo "$yellow" "用法: $0 <设备名称> [SukiSU-Ultra|rksu|none] [--aosp|--miui|all]"
    color_echo "$yellow" "示例:"
    color_echo "$yellow" "  $0 lmi                     # 构建标准版本"
    color_echo "$yellow" "  $0 lmi SukiSU-Ultra        # 构建SukiSU-Ultra版本"
    color_echo "$yellow" "  $0 lmi SukiSU-Ultra --aosp # 仅构建AOSP版本"
    color_echo "$yellow" "  $0 lmi SukiSU-Ultra --miui # 仅构建MIUI版本"
    color_echo "$yellow" "  $0 lmi rksu                # 构建RKSU版本"
    color_echo "$yellow" "  $0 lmi rksu --aosp         # 构建AOSP+RKSU版本"
    color_echo "$yellow" "  $0 lmi rksu --miui         # 构建MIUI+RKSU版本"
    color_echo "$yellow" "  $0 lmi none --aosp         # 构建无KSU的AOSP版本"
    color_echo "$yellow" "  $0 lmi none --miui         # 构建无KSU的MIUI版本"
}

if [ -z "$TARGET_DEVICE" ]; then
    show_usage
    error_exit "设备名称不能为空"
fi

# 检查帮助参数
if [[ "$TARGET_DEVICE" == "--help" || "$TARGET_DEVICE" == "-h" ]]; then
    show_usage
    exit 0
fi

# 确定构建类型
BUILD_AOSP=true
BUILD_MIUI=true

case "$BUILD_TYPE" in
    "--aosp")
        BUILD_MIUI=false
        print_info "仅构建AOSP版本"
        ;;
    "--miui")
        BUILD_AOSP=false
        print_info "仅构建MIUI版本"
        ;;
    ""|"all")
        print_info "构建AOSP和MIUI版本（默认）"
        ;;
    *)
        print_warning "未知的构建类型: '$BUILD_TYPE'，使用默认设置（构建全部）"
        ;;
esac

# SukiSU-Ultra/RKSU支持
KSU_ENABLE=0
KSU_ZIP_STR=NoKernelSU
KPM_ENABLE=0

case "$KSU_TYPE" in
    "SukiSU-Ultra"|"ksu")
        KSU_ENABLE=1
        KPM_ENABLE=1
        KSU_ZIP_STR=SukiSU-Ultra
        print_info "启用SukiSU-Ultra (包含KPM功能)"
        ;;
    "rksu")
        KSU_ENABLE=1
        KSU_ZIP_STR=RKSU
        print_info "启用RKSU"
        ;;
    "none"|"")
        print_info "未启用KernelSU"
        ;;
    *)
        print_warning "未知的KSU类型: '$KSU_TYPE'，不使用KernelSU"
        ;;
esac

if [ ! -d $TOOLCHAIN_PATH ]; then
    error_exit "TOOLCHAIN_PATH [$TOOLCHAIN_PATH] 不存在"
fi

print_info "TOOLCHAIN_PATH: [$TOOLCHAIN_PATH]"
export PATH="$TOOLCHAIN_PATH:$PATH"

# 检查必要的工具
print_info "检查编译工具..."
if ! command -v aarch64-linux-gnu-ld >/dev/null 2>&1; then
    error_exit "[aarch64-linux-gnu-ld] 不存在"
fi

if ! command -v arm-linux-gnueabi-ld >/dev/null 2>&1; then
    error_exit "[arm-linux-gnueabi-ld] 不存在"
fi

if ! command -v clang >/dev/null 2>&1; then
    error_exit "[clang] 不存在"
fi

# Enable ccache for speed up compiling 
export CCACHE_DIR="$HOME/.cache/ccache_mikernel" 
export CC="ccache gcc"
export CXX="ccache g++"
export PATH="/usr/lib/ccache:$PATH"
print_info "CCACHE_DIR: [$CCACHE_DIR]"

MAKE_ARGS="ARCH=arm64 SUBARCH=arm64 O=out CC=clang CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- CROSS_COMPILE_COMPAT=arm-linux-gnueabi- CLANG_TRIPLE=aarch64-linux-gnu-"

if [ "$TARGET_DEVICE" == "j1" ]; then
    make $MAKE_ARGS -j1
    exit
fi

if [ "$TARGET_DEVICE" == "continue" ]; then
    make $MAKE_ARGS -j$(nproc)
    exit
fi

if [ ! -f "arch/arm64/configs/${TARGET_DEVICE}_defconfig" ]; then
    error_exit "未找到目标设备 [${TARGET_DEVICE}]"
fi

# Check clang is existing.
print_info "[clang --version]:"
clang --version

print_info "TARGET_DEVICE: $TARGET_DEVICE"

# =============================================================================
# 自定义版本信息处理
# 功能: 使用环境变量中的自定义版本信息
# =============================================================================
setup_custom_version() {
    print_info "设置自定义版本信息..."
    
    # 检查环境变量中的自定义版本信息
    if [ -n "$KSU_VERSION_FULL" ]; then
        print_info "检测到自定义KernelSU版本: $KSU_VERSION_FULL"
        export KSU_VERSION_FULL="$KSU_VERSION_FULL"
    else
        # 如果没有自定义版本，使用默认版本
        KSU_VERSION_FULL="v4.1.0-$(git rev-parse --short=8 HEAD)@ Or so. 左右-40221"
        print_info "使用默认KernelSU版本: $KSU_VERSION_FULL"
        export KSU_VERSION_FULL="$KSU_VERSION_FULL"
    fi
    
    if [ -n "$KSU_API_VERSION" ]; then
        print_info "检测到KernelSU API版本: $KSU_API_VERSION"
        export KSU_API_VERSION="$KSU_API_VERSION"
    else
        KSU_API_VERSION="4.1.0"
        print_info "使用默认KernelSU API版本: $KSU_API_VERSION"
        export KSU_API_VERSION="$KSU_API_VERSION"
    fi
    
    # 设置内核版本信息
    echo 1 > "out/.version"
    export KBUILD_BUILD_VERSION="1"
    export LOCALVERSION="-g92c089fc2d37"
    export KBUILD_BUILD_USER="xiaomi-builder"
    export KBUILD_BUILD_HOST="xiaomi-build-server"
    export KBUILD_BUILD_TIMESTAMP="Wed Oct 29 11:41:46 UTC 2025"
    
    print_success "自定义版本信息设置完成"
    print_info "KSU_VERSION_FULL: $KSU_VERSION_FULL"
    print_info "KSU_API_VERSION: $KSU_API_VERSION"
}

# =============================================================================
# SUSFS 2.0.00 补丁处理函数
# 功能: SUSFS补丁处理机制
# =============================================================================
apply_susfs_patch() {
    local PATCH_URL="https://github.com/JackA1ltman/NonGKI_Kernel_Build_2nd/raw/mainline/Patches/Patch/susfs_upgrade_to_2000_4.19.patch"
    local PATCH_FILE="susfs_upgrade_to_2000_4.19.patch"
    
    print_step "开始SUSFS 2.0.00补丁处理"
    
    # 检查是否已经应用过补丁
    print_info "检查SUSFS补丁状态..."
    if [ -f "fs/susfs.c" ]; then
        print_success "SUSFS补丁已经应用过，跳过"
        return 0
    fi
    
    # 下载补丁文件
    print_info "下载SUSFS补丁..."
    if ! curl -LSs "$PATCH_URL" -o "$PATCH_FILE"; then
        print_warning "SUSFS补丁下载失败，尝试备用URL..."
        # 尝试备用URL
        PATCH_URL="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/mainline/Patches/Patch/susfs_upgrade_to_2000_4.19.patch"
        if ! curl -LSs "$PATCH_URL" -o "$PATCH_FILE"; then
            print_warning "SUSFS补丁下载失败，跳过补丁"
            return 1
        fi
    fi

    # 检查补丁文件是否下载成功
    if [ ! -f "$PATCH_FILE" ]; then
        print_warning "SUSFS补丁文件不存在"
        return 1
    fi

    # 检查补丁文件内容
    if [ ! -s "$PATCH_FILE" ]; then
        print_warning "SUSFS补丁文件为空"
        rm -f "$PATCH_FILE"
        return 1
    fi

    # 应用补丁到内核源码
    print_info "应用SUSFS补丁..."
    if patch -p1 --batch --forward < "$PATCH_FILE" 2>/dev/null; then
        print_success "SUSFS补丁应用成功"
        # 验证补丁是否真正应用
        if [ -f "fs/susfs.c" ]; then
            print_success "SUSFS补丁验证成功"
        else
            print_warning "SUSFS补丁应用但文件未生成，可能补丁格式不匹配"
        fi
    else
        # 检查补丁状态
        if find . -name "*.rej" | grep -q .; then
            print_warning "SUSFS补丁有冲突，发现.rej文件"
            # 显示冲突文件
            find . -name "*.rej" -exec echo "冲突文件: {}" \;
        elif find . -name "*.orig" | grep -q .; then
            print_success "SUSFS补丁可能已经应用过（发现.orig备份文件）"
        else
            print_warning "SUSFS补丁应用失败"
        fi
    fi
    
    # 清理临时文件
    rm -f "$PATCH_FILE"
    find . -type f \( -name "*.rej" -o -name "*.orig" \) -delete 2>/dev/null || true
    
    return 0
}

# =============================================================================
# 补丁失败处理函数
# 功能: 当补丁应用失败时进行恢复操作
# =============================================================================
handle_patch_failure() {
    print_info "补丁处理失败，开始恢复..."
    # 恢复被修改的文件
    git checkout -- . || print_warning "部分文件恢复失败"
    rm -f "susfs_upgrade_to_2000_4.19.patch"
    find . -type f \( -name "*.rej" -o -name "*.orig" \) -delete 2>/dev/null || true
    
    print_success "文件恢复完成"
}

# =============================================================================
# KernelSU目录检查函数
# 功能: 验证KernelSU目录是否存在并显示版本信息
# =============================================================================
check_kernelsu() {
    if [ $KSU_ENABLE -eq 1 ]; then
        if [ -d "KernelSU" ]; then
            print_success "KernelSU目录已存在"
            if [ -n "$KSU_VERSION_FULL" ]; then
                print_info "KernelSU版本: $KSU_VERSION_FULL"
            fi
        else
            print_warning "KernelSU目录不存在，但KSU已启用"
        fi
    else
        print_info "未启用KernelSU"
    fi
}

# =============================================================================
# AnyKernel3准备函数
# 功能: 下载并准备刷机包打包环境
# =============================================================================
prepare_anykernel() {
    print_step "准备AnyKernel3"
    rm -rf anykernel/
    if git clone https://github.com/liyafe1997/AnyKernel3 -b kona --single-branch --depth=1 anykernel; then
        print_success "AnyKernel3下载成功"
    else
        error_exit "AnyKernel3下载失败"
    fi
}

# =============================================================================
# KernelSU配置函数
# 功能: 配置内核中的KernelSU相关选项
# =============================================================================
configure_kernelsu() {
    if [ $KSU_ENABLE -eq 1 ]; then
        # 检查KernelSU目录是否存在
        if [ ! -d "KernelSU" ]; then
            print_warning "KernelSU目录不存在，跳过KernelSU配置"
            return
        fi
        
        print_info "配置KernelSU选项"
        # 启用KernelSU相关配置选项
        scripts/config --file out/.config \
            -e KSU \
            -e KSU_SUSFS \
            -e KPM \
            -e KALLSYMS \
            -e KALLSYMS_ALL
        
        print_success "KernelSU配置完成"
    else
        scripts/config --file out/.config -d KSU
        print_info "禁用KernelSU"
    fi
}

# =============================================================================
# KPM补丁应用函数
# 功能: 下载并应用Kernel Patch Manager补丁到内核镜像
# =============================================================================
apply_kpm_patch() {
    if [[ $KSU_ENABLE -eq 1 && $KPM_ENABLE -eq 1 ]]; then
        # 检查KernelSU目录是否存在
        if [ ! -d "KernelSU" ]; then
            print_warning "KernelSU目录不存在，跳过KPM补丁"
            return
        fi
        
        print_step "应用KPM补丁"
        
        # 检查内核镜像是否存在
        if [ ! -f "out/arch/arm64/boot/Image" ]; then
            print_warning "内核镜像不存在，跳过KPM补丁"
            return
        fi
        
        cd out/arch/arm64/boot/
        
        # 下载KPM补丁工具
        if curl -LSs "https://github.com/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/download/0.12.2/patch_linux" -o patch_linux; then
            chmod +x patch_linux
            # 备份原始镜像
            cp Image Image.orig
            
            # 应用补丁到内核镜像
            if ./patch_linux; then
                if [ -f "oImage" ]; then
                    rm -f Image
                    mv oImage Image
                    print_success "KPM补丁应用成功"
                else
                    print_warning "KPM补丁应用但未生成oImage文件"
                    mv Image.orig Image
                fi
            else
                print_warning "KPM补丁应用失败，使用原始镜像"
                mv Image.orig Image
            fi
            rm -f patch_linux
        else
            print_warning "无法下载KPM补丁，使用原始镜像"
        fi
        cd -
    fi
}

# =============================================================================
# 镜像打包函数
# 功能: 将编译好的内核文件打包成刷机包
# =============================================================================
image_repack() {
    local system_type=$1
    print_step "打包${system_type}镜像"
    
    # 检查内核镜像是否生成成功
    if [ ! -f "out/arch/arm64/boot/Image" ]; then
        error_exit "内核构建失败，Image文件不存在"
    fi

    # 生成DTB设备树文件
    print_info "生成DTB文件"
    find out/arch/arm64/boot/dts -name '*.dtb' -exec cat {} + > out/arch/arm64/boot/dtb 2>/dev/null || {
        print_warning "DTB生成失败，创建空文件"
        touch out/arch/arm64/boot/dtb
    }

    # 应用KPM补丁到内核镜像
    apply_kpm_patch

    # 准备anykernel目录结构
    rm -rf anykernel/kernels/
    mkdir -p anykernel/kernels/

    # 复制内核文件到打包目录
    cp out/arch/arm64/boot/Image anykernel/kernels/
    print_success "已复制Image文件"

    if [ -f "out/arch/arm64/boot/dtb" ]; then
        cp out/arch/arm64/boot/dtb anykernel/kernels/
        print_success "已复制dtb文件"
    else
        print_warning "dtb文件不存在，跳过复制"
    fi

    # 创建刷机包
    cd anykernel
    local timestamp=$(date +'%Y%m%d_%H%M%S')
    local zip_filename="Kernel_${system_type}_${TARGET_DEVICE}_${KSU_ZIP_STR}_${timestamp}_anykernel3_${GIT_COMMIT_ID}.zip"

    # 使用zip命令打包所有必要文件
    zip -r9 "$zip_filename" ./* -x .git .gitignore out/ ./*.zip
    
    if [ $? -eq 0 ] && [ -f "$zip_filename" ]; then
        mv "$zip_filename" ../
        print_success "${system_type}刷机包创建成功: $zip_filename"
        print_info "文件大小: $(du -h "../$zip_filename" | cut -f1)"
    else
        error_exit "${system_type}刷机包创建失败"
    fi
    cd -
}

# =============================================================================
# AOSP版本构建函数
# 功能: 构建适用于AOSP系统的内核版本
# =============================================================================
build_aosp() {
    if [ "$BUILD_AOSP" = true ]; then
        print_step "开始构建AOSP内核"
        
        # 清理之前的构建输出
        rm -rf out/
        
        # 配置内核编译选项
        make $MAKE_ARGS ${TARGET_DEVICE}_defconfig
        
        # 设置自定义版本信息
        setup_custom_version
        
        # 检查并配置KernelSU
        check_kernelsu
        if [ $KSU_ENABLE -eq 1 ] && [ -d "KernelSU" ]; then
            configure_kernelsu
        fi
        
        # 开始编译内核
        local start_time=$(date +%s)
        print_info "开始编译AOSP内核..."
        make $MAKE_ARGS -j$(nproc)
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        # 检查编译结果
        if [ -f "out/arch/arm64/boot/Image" ]; then
            print_success "AOSP内核编译成功，耗时: $((duration / 60))分$((duration % 60))秒"
        else
            error_exit "AOSP内核编译失败"
        fi
        
        # 打包生成的内核文件
        image_repack "AOSP"
        print_success "AOSP内核构建完成"
    fi
}

# =============================================================================
# MIUI版本构建函数
# 功能: 构建适用于MIUI系统的内核版本，包含设备树修改
# =============================================================================
build_miui() {
    if [ "$BUILD_MIUI" = true ]; then
        print_step "开始构建MIUI内核"
        
        # 清理之前的构建输出
        rm -rf out/
        
        # 备份设备树文件
        dts_source=arch/arm64/boot/dts/vendor/qcom
        if [ -d "$dts_source" ]; then
            cp -a ${dts_source} .dts.bak
            print_success "设备树备份完成"
        else
            print_warning "设备树目录不存在，跳过备份"
        fi

        # =============================================================================
        # MIUI设备树修改部分
        # 功能: 修改设备树文件以适配MIUI系统的特殊需求
        # =============================================================================
        
        print_info "应用MIUI设备树修改..."
        
        # 面板尺寸修正
        sed -i 's/<154>/<1537>/g' ${dts_source}/dsi-panel-j1s*
        sed -i 's/<154>/<1537>/g' ${dts_source}/dsi-panel-j2*
        sed -i 's/<155>/<1544>/g' ${dts_source}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi
        sed -i 's/<155>/<1545>/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
        sed -i 's/<155>/<1546>/g' ${dts_source}/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi
        sed -i 's/<155>/<1546>/g' ${dts_source}/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
        sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
        sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi
        sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-k11a-38-08-0a-dsc-cmd.dtsi
        sed -i 's/<70>/<695>/g' ${dts_source}/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
        sed -i 's/<71>/<710>/g' ${dts_source}/dsi-panel-j1s*
        sed -i 's/<71>/<710>/g' ${dts_source}/dsi-panel-j2*

        # 启用智能FPS
        sed -i 's/\/\/ mi,mdss-dsi-pan-enable-smart-fps/mi,mdss-dsi-pan-enable-smart-fps/g' ${dts_source}/dsi-panel*
        sed -i 's/\/\/ mi,mdss-dsi-smart-fps-max_framerate/mi,mdss-dsi-smart-fps-max_framerate/g' ${dts_source}/dsi-panel*
        sed -i 's/\/\/ qcom,mdss-dsi-pan-enable-smart-fps/qcom,mdss-dsi-pan-enable-smart-fps/g' ${dts_source}/dsi-panel*
        sed -i 's/qcom,mdss-dsi-qsync-min-refresh-rate/\/\/qcom,mdss-dsi-qsync-min-refresh-rate/g' ${dts_source}/dsi-panel*

        # 刷新率支持
        sed -i 's/120 90 60/120 90 60 50 30/g' ${dts_source}/dsi-panel-g7a-36-02-0c-dsc-video.dtsi
        sed -i 's/120 90 60/120 90 60 50 30/g' ${dts_source}/dsi-panel-g7a-37-02-0a-dsc-video.dtsi
        sed -i 's/120 90 60/120 90 60 50 30/g' ${dts_source}/dsi-panel-g7a-37-02-0b-dsc-video.dtsi
        sed -i 's/144 120 90 60/144 120 90 60 50 48 30/g' ${dts_source}/dsi-panel-j3s-37-02-0a-dsc-video.dtsi

        # 亮度控制
        sed -i 's/\/\/39 00 00 00 00 00 03 51 03 FF/39 00 00 00 00 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j9-38-0a-0a-fhd-video.dtsi
        sed -i 's/\/\/39 00 00 00 00 00 03 51 0D FF/39 00 00 00 00 00 03 51 0D FF/g' ${dts_source}/dsi-panel-j2-p2-1-38-0c-0a-dsc-cmd.dtsi
        sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-dsc-cmd.dtsi
        sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-mp-dsc-cmd.dtsi
        sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j2-mp-42-02-0b-dsc-cmd.dtsi
        sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j2-p2-1-42-02-0b-dsc-cmd.dtsi
        sed -i 's/\/\/39 00 00 00 00 00 05 51 0F 8F 00 00/39 00 00 00 00 00 05 51 0F 8F 00 00/g' ${dts_source}/dsi-panel-j2s-mp-42-02-0a-dsc-cmd.dtsi
        sed -i 's/\/\/39 01 00 00 00 00 03 51 00 00/39 01 00 00 00 00 03 51 00 00/g' ${dts_source}/dsi-panel-j2-38-0c-0a-dsc-cmd.dtsi
        sed -i 's/\/\/39 01 00 00 00 00 03 51 00 00/39 01 00 00 00 00 03 51 00 00/g' ${dts_source}/dsi-panel-j2-38-0c-0a-dsc-cmd.dtsi
        sed -i 's/\/\/39 01 00 00 00 00 03 51 03 FF/39 01 00 00 00 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
        sed -i 's/\/\/39 01 00 00 00 00 03 51 03 FF/39 01 00 00 00 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j9-38-0a-0a-fhd-video.dtsi
        sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' ${dts_source}/dsi-panel-j1u-42-02-0b-dsc-cmd.dtsi
        sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' ${dts_source}/dsi-panel-j2-42-02-0b-dsc-cmd.dtsi
        sed -i 's/\/\/39 01 00 00 00 00 03 51 07 FF/39 01 00 00 00 00 03 51 07 FF/g' ${dts_source}/dsi-panel-j2-p1-42-02-0b-dsc-cmd.dtsi
        sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' ${dts_source}/dsi-panel-j1u-42-02-0b-dsc-cmd.dtsi
        sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' ${dts_source}/dsi-panel-j2-42-02-0b-dsc-cmd.dtsi
        sed -i 's/\/\/39 01 00 00 00 00 03 51 0F FF/39 01 00 00 00 00 03 51 0F FF/g' ${dts_source}/dsi-panel-j2-p1-42-02-0b-dsc-cmd.dtsi
        sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-dsc-cmd.dtsi
        sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j1s-42-02-0a-mp-dsc-cmd.dtsi
        sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j2-mp-42-02-0b-dsc-cmd.dtsi
        sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j2-p2-1-42-02-0b-dsc-cmd.dtsi
        sed -i 's/\/\/39 01 00 00 00 00 05 51 07 FF 00 00/39 01 00 00 00 00 05 51 07 FF 00 00/g' ${dts_source}/dsi-panel-j2s-mp-42-02-0a-dsc-cmd.dtsi
        sed -i 's/\/\/39 01 00 00 01 00 03 51 03 FF/39 01 00 00 01 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j11-38-08-0a-fhd-cmd.dtsi
        sed -i 's/\/\/39 01 00 00 11 00 03 51 03 FF/39 01 00 00 11 00 03 51 03 FF/g' ${dts_source}/dsi-panel-j2-p2-1-38-0c-0a-dsc-cmd.dtsi


        # 配置内核编译选项
        make $MAKE_ARGS ${TARGET_DEVICE}_defconfig
        
        # 设置自定义版本信息
        setup_custom_version
        
        # 检查并配置KernelSU
        check_kernelsu
        if [ $KSU_ENABLE -eq 1 ] && [ -d "KernelSU" ]; then
            configure_kernelsu
        fi
        
        # MIUI特定配置
        print_info "应用MIUI特定配置..."
        scripts/config --file out/.config \
            -e PERF_CRITICAL_RT_TASK \
            -e SF_BINDER \
            -e OVERLAY_FS \
            -d DEBUG_FS \
            -e MIGT \
            -e MIGT_ENERGY_MODEL \
            -e MIHW \
            -e PACKAGE_RUNTIME_INFO \
            -e BINDER_OPT \
            -e KPERFEVENTS \
            -e MILLET \
            -e PERF_HUMANTASK \
            -d LTO_CLANG \
            -d LOCALVERSION_AUTO \
            -e XIAOMI_MIUI \
            -d MI_MEMORY_SYSFS \
            -e TASK_DELAY_ACCT \
            -e MIUI_ZRAM_MEMORY_TRACKING \
            -d MODULE_SIG_SHA512 \
            -d MODULE_SIG_HASH \
            -e MI_FRAGMENTION \
            -e PERF_HELPER \
            -e BOOTUP_RECLAIM \
            -e MI_RECLAIM \
            -e RTMM
        
        # 开始编译内核
        local start_time=$(date +%s)
        print_info "开始编译MIUI内核..."
        make $MAKE_ARGS -j$(nproc)
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        # 检查编译结果
        if [ -f "out/arch/arm64/boot/Image" ]; then
            print_success "MIUI内核编译成功，耗时: $((duration / 60))分$((duration % 60))秒"
        else
            error_exit "MIUI内核编译失败"
        fi
        
        # 恢复设备树文件
        if [ -d ".dts.bak" ]; then
            rm -rf $dts_source
            mv .dts.bak $dts_source
            print_success "设备树恢复完成"
        fi
        
        # 打包生成的内核文件
        image_repack "MIUI"
        print_success "MIUI内核构建完成"
    fi
}

# =============================================================================
# 主构建流程函数
# 功能: 协调整个构建流程，处理错误和信号
# =============================================================================
main_build() {
    local start_time=$(date +%s)
    
    print_step "开始内核构建流程"
    print_info "目标设备: $TARGET_DEVICE"
    print_info "KernelSU: $KSU_ZIP_STR"
    print_info "构建类型: AOSP=$BUILD_AOSP, MIUI=$BUILD_MIUI"
    print_info "Git提交ID: $GIT_COMMIT_ID"
    
    # 检查环境变量
    if [ -n "$KSU_VERSION_FULL" ]; then
        print_info "检测到自定义KernelSU版本: $KSU_VERSION_FULL"
    fi
    if [ -n "$KSU_API_VERSION" ]; then
        print_info "检测到KernelSU API版本: $KSU_API_VERSION"
    fi
    
    # 应用SUSFS补丁
    print_info "开始SUSFS补丁处理..."
    if ! apply_susfs_patch; then
        print_warning "SUSFS补丁应用失败，尝试恢复..."
        handle_patch_failure
    fi
    
    # 准备AnyKernel3打包环境
    prepare_anykernel
    
    # 检查KernelSU状态
    check_kernelsu
    
    # 执行AOSP版本构建
    build_aosp
    
    # 执行MIUI版本构建
    build_miui
    
    # 计算总构建时间
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    print_step "构建完成"
    print_success "所有构建任务完成! 总耗时: $((total_duration / 60))分$((total_duration % 60))秒"
    
    # 显示生成的刷机包
    print_info "生成的文件:"
    find . -name "Kernel_*.zip" -exec echo "  - {}" \; 2>/dev/null || echo "  未找到刷机包"
    
    # 显示构建摘要
    echo
    color_echo "$green" "=============================================="
    color_echo "$green" "构建摘要"
    color_echo "$green" "=============================================="
    color_echo "$green" "设备: $TARGET_DEVICE"
    color_echo "$green" "KernelSU: $KSU_ZIP_STR"
    color_echo "$green" "Git提交: $GIT_COMMIT_ID"
    color_echo "$green" "构建时间: $(date)"
    
    if [ -n "$KSU_VERSION_FULL" ]; then
        color_echo "$green" "KernelSU版本: $KSU_VERSION_FULL"
    fi
    
    # 统计生成的zip文件
    local zip_count=$(find . -name "Kernel_*.zip" -type f 2>/dev/null | wc -l)
    color_echo "$green" "生成的刷机包数量: $zip_count"
    
    if [ $zip_count -gt 0 ]; then
        find . -name "Kernel_*.zip" -type f -exec echo "  - {}" \; 2>/dev/null
    fi
}

# =============================================================================
# 错误处理陷阱
# 功能: 捕获脚本执行过程中的错误和中断信号
# =============================================================================

# 错误处理陷阱 - 捕获脚本执行错误
trap 'error_exit "脚本在行数 $LINENO 处发生错误"' ERR

# 信号处理 - 捕获用户中断信号
trap '
    echo
    color_echo "$red" "=============================================="
    color_echo "$red" "脚本被用户中断"
    color_echo "$red" "=============================================="
    exit 1
' INT TERM

# =============================================================================
# 脚本主入口
# 功能: 执行主构建流程
# =============================================================================

# 执行主构建流程
main_build

# =============================================================================
# 构建完成输出
# 功能: 显示最终完成信息
# =============================================================================
echo
color_echo "$green" "=============================================="
color_echo "$green" "内核构建脚本执行完成!"
color_echo "$green" "=============================================="

# 退出脚本
exit 0

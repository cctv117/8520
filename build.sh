#!/bin/bash

# =============================================================================
# Android内核构建脚本
# 1.5
# =============================================================================

# 颜色定义
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
    color_echo "$blue" "ℹℹℹℹℹℹℹℹℹℹℹℹℹℹℹℹ $1"
}

# 警告函数
print_warning() {
    color_echo "$yellow" "警告: $1"
}

# Ensure the script exits on error
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
    echo
    color_echo "$yellow" "可用设备:"
    if [[ -d "arch/arm64/configs" ]]; then
        ls arch/arm64/configs/*_defconfig 2>/dev/null | 
            sed "s|.*/||; s|_defconfig||" | xargs printf "  %s\n" || 
            color_echo "$red" "  无法读取设备配置目录"
    else
        color_echo "$red" "  配置目录不存在"
    fi
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
        print_info "启用SukiSU-Ultra"
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

# 配置ccache优化
setup_ccache() {
    print_step "配置ccache缓存优化"
    
    # 设置ccache环境变量
    export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache_kernel_4.19}"
    export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-5G}"
    export CCACHE_COMPRESS=true
    export CCACHE_COMPRESSLEVEL=6
    export CCACHE_HARDLINK=true
    
    # 创建ccache目录
    mkdir -p "$CCACHE_DIR"
    
    # 配置ccache参数
    if command -v ccache >/dev/null 2>&1; then
        ccache -o max_size="$CCACHE_MAXSIZE" 2>/dev/null || true
        ccache -o compression=true 2>/dev/null || true
        ccache -o compression_level=6 2>/dev/null || true
        ccache -o hard_link=true 2>/dev/null || true
        ccache -o sloppiness=file_macro,locale,time_macros 2>/dev/null || true
        ccache -o hash_dir=false 2>/dev/null || true
        print_success "ccache参数配置完成"
    else
        print_warning "ccache命令未找到，但构建将继续进行"
    fi
    
    print_info "CCACHE_DIR: $CCACHE_DIR"
    print_info "CCACHE_MAXSIZE: $CCACHE_MAXSIZE"
    
    # 初始统计
    print_info "ccache初始状态:"
    if command -v ccache >/dev/null 2>&1; then
        ccache -s 2>/dev/null | head -10 || echo "ccache统计信息暂时不可用"
    else
        echo "ccache命令未找到"
    fi
    
    # 设置编译器包装
    export CC="ccache clang"
    export CXX="ccache clang++"
    export PATH="/usr/lib/ccache:$PATH"
    
    print_success "ccache配置完成"
}

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

# 配置ccache
setup_ccache

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

# ==========================================
# KSU补丁脚本处理
# ==========================================
execute_ksu_patch_scripts() {
    local INLINE_HOOK_SCRIPT_URL="https://github.com/JackA1ltman/NonGKI_Kernel_Build_2nd/blob/mainline/Patches/susfs_inline_hook_patches.sh?raw=true"
    local BACKPORT_SCRIPT_URL="https://github.com/JackA1ltman/NonGKI_Kernel_Build_2nd/blob/mainline/Patches/backport_patches.sh?raw=true"
    local INLINE_HOOK_SCRIPT="susfs_inline_hook_patches.sh"
    local BACKPORT_SCRIPT="backport_patches.sh"

    print_step "开始KSU补丁脚本执行"

    # 1. 下载susfs_inline_hook_patches.sh
    print_info "下载 ${INLINE_HOOK_SCRIPT}..."
    if ! curl -LSs --connect-timeout 10 "${INLINE_HOOK_SCRIPT_URL}" -o "${INLINE_HOOK_SCRIPT}"; then
        error_exit "下载 ${INLINE_HOOK_SCRIPT} 失败"
    fi

    # 执行susfs_inline_hook_patches.sh
    print_info "执行 ${INLINE_HOOK_SCRIPT}..."
    if ! bash "${INLINE_HOOK_SCRIPT}"; then
        error_exit "执行 ${INLINE_HOOK_SCRIPT} 失败"
    fi

    # 2. 下载backport_patches.sh
    print_info "下载 ${BACKPORT_SCRIPT}..."
    if ! curl -LSs --connect-timeout 10 "${BACKPORT_SCRIPT_URL}" -o "${BACKPORT_SCRIPT}"; then
        error_exit "下载 ${BACKPORT_SCRIPT} 失败"
    fi

    # 执行backport_patches.sh
    print_info "执行 ${BACKPORT_SCRIPT}..."
    if ! bash "${BACKPORT_SCRIPT}"; then
        error_exit "执行 ${BACKPORT_SCRIPT} 失败"
    fi

    rm -f "${INLINE_HOOK_SCRIPT}" "${BACKPORT_SCRIPT}"
    print_success "KSU补丁脚本执行完成"
}

# ==========================================
# SUSFS 2.0.00补丁处理
# ==========================================
apply_susfs_patch() {
    local PATCH_URL="https://github.com/JackA1ltman/NonGKI_Kernel_Build_2nd/blob/mainline/Patches/Patch/susfs_upgrade_to_2000_4.19.patch"
    local PATCH_FILE="susfs_upgrade_to_2000_4.19.patch"
    
    print_info "开始SUSFS 2.0.00补丁处理"

    # 下载补丁
    print_info "下载SUSFS补丁..."
    if ! curl -LSs "${PATCH_URL}?raw=true" -o "$PATCH_FILE"; then
        print_warning "补丁文件下载失败"
        return 1
    fi

    # 应用补丁
    print_info "应用SUSFS补丁..."
    if ! patch -p1 --batch --forward --quiet < "$PATCH_FILE"; then
        print_warning "补丁应用失败"
        return 2
    fi
    
    print_success "SUSFS补丁应用成功"
    rm -f "$PATCH_FILE"
    find . -type f \( -name "*.rej" -o -name "*.orig" \) -delete
    return 0
}

# SUSFS补丁处理主流程
handle_susfs_patch() {
    print_step "SUSFS补丁处理流程"
    
    # 应用补丁
    apply_susfs_patch
    local PATCH_EXIT_CODE=$?
    
    # 补丁失败处理
    if [ "$PATCH_EXIT_CODE" -eq 1 ] || [ "$PATCH_EXIT_CODE" -eq 2 ]; then
        print_warning "补丁处理失败，启动恢复机制"
        
        # 恢复所有修改
        print_info "恢复文件修改..."
        git checkout -- . || print_warning "部分文件恢复失败"
        
        # 清理临时文件
        rm -f "susfs_upgrade_to_2000_4.19.patch"
        find . -type f \( -name "*.rej" -o -name "*.orig" \) -delete
        
        # cherry-pick
        print_info "尝试cherry-pick提交 7de1989..."
        if git cherry-pick 7de1989; then
            print_success "cherry-pick成功"
        else
            error_exit "cherry-pick失败！请检查提交7de1989是否存在"
        fi
    else
        print_success "SUSFS补丁处理完成"
    fi
}

# 设置版本信息函数
setup_version_info() {
    echo 1 > "out/.version"
    export KBUILD_BUILD_VERSION="1"
    export LOCALVERSION="-g92c089fc2d37"
    export KBUILD_BUILD_USER="xiaomi-builder"
    export KBUILD_BUILD_HOST="xiaomi-build-server"
    export KBUILD_BUILD_TIMESTAMP="Wed Oct 29 11:41:46 UTC 2025"
   
    # 使用环境变量中的KernelSU版本信息（如果存在）
    if [ -n "$KSU_VERSION_FULL" ]; then
        print_info "使用自定义KernelSU版本: $KSU_VERSION_FULL"
        export KSU_VERSION_FULL="$KSU_VERSION_FULL"
    else
        print_info "使用默认KernelSU版本"
    fi
    
    if [ -n "$KSU_API_VERSION" ]; then
        export KSU_API_VERSION="$KSU_API_VERSION"
    fi
    
    print_success "版本信息设置完成"
}

# 配置KernelSU函数
configure_kernelsu() {
    if [ $KSU_ENABLE -eq 1 ]; then
        print_info "配置KernelSU选项"
        scripts/config --file out/.config \
            -e KSU \
            -e KSU_SUSFS \
            -e KSU_SUSFS_SUS_PATH \
            -e KSU_SUSFS_SUS_MOUNT \
            -e KSU_SUSFS_SUS_KSTAT \
            -e KSU_SUSFS_SPOOF_UNAME \
            -e KSU_SUSFS_ENABLE_LOG \
            -e KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
            -e KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
            -e KSU_SUSFS_OPEN_REDIRECT \
            -e KSU_SUSFS_SUS_MAP \
            -e THREAD_INFO_IN_TASK
            
        # 根据KSU类型配置KPM
        if [ "$KPM_ENABLE" -eq 1 ]; then
            scripts/config --file out/.config \
                -e KPM \
                -e KALLSYMS \
                -e KALLSYMS_ALL
            print_info "已启用KPM支持"
        else
            scripts/config --file out/.config \
                -d KPM \
                -d KALLSYMS \
                -d KALLSYMS_ALL
        fi
    else
        scripts/config --file out/.config -d KSU
        scripts/config --file out/.config -d KSU_SUSFS
        print_info "已禁用KernelSU"
    fi
}

# 应用KPM补丁函数
apply_kpm_patch() {
    if [[ "$KPM_ENABLE" -eq 1 && "$KSU_TYPE" == "SukiSU-Ultra" ]]; then
        print_step "应用KPM补丁"
        cd out/arch/arm64/boot/
        
        if curl -LSs "https://github.com/SukiSU-Ultra/SukiSU_KernelPatch_patch/releases/download/0.12.2/patch_linux" -o patch; then
            chmod +x patch
            if ./patch; then
                rm -f Image
                mv oImage Image
                print_success "KPM补丁应用成功"
            else
                print_warning "KPM补丁应用失败，使用原始镜像"
            fi
            rm -f patch
        else
            print_warning "无法下载KPM补丁，使用原始镜像"
        fi
        cd -
    fi
}

# 准备AnyKernel3函数
prepare_anykernel() {
    print_step "准备AnyKernel3"
    rm -rf anykernel/
    if git clone https://github.com/liyafe1997/AnyKernel3 -b kona --single-branch --depth=1 anykernel; then
        print_success "AnyKernel3下载成功"
    else
        error_exit "AnyKernel3下载失败"
    fi
}

# 镜像打包函数
image_repack() {
    local system_type=$1
    print_step "打包${system_type}镜像"
    
    # 检查构建是否成功
    if [ ! -f "out/arch/arm64/boot/Image" ]; then
        error_exit "内核构建失败，Image文件不存在"
    fi

    # 应用KPM补丁
    apply_kpm_patch

    # 生成DTB
    print_info "生成DTB文件"
    find out/arch/arm64/boot/dts -name '*.dtb' -exec cat {} + > out/arch/arm64/boot/dtb 2>/dev/null || {
        print_warning "DTB生成失败，创建空文件"
        touch out/arch/arm64/boot/dtb
    }

    # 清理并准备anykernel目录
    rm -rf anykernel/kernels/
    mkdir -p anykernel/kernels/

    # 复制必要的内核文件
    if [ -f "out/arch/arm64/boot/Image" ]; then
        cp out/arch/arm64/boot/Image anykernel/kernels/
        print_success "已复制Image文件"
    else
        error_exit "Image文件不存在"
    fi

    if [ -f "out/arch/arm64/boot/dtb" ]; then
        cp out/arch/arm64/boot/dtb anykernel/kernels/
        print_success "已复制dtb文件"
    else
        print_warning "dtb文件不存在，跳过复制"
    fi

    # 恢复MIUI构建的设备树修改
    if [ "$system_type" == "MIUI" ]; then
        if [ -d ".dts.bak" ]; then
            rm -rf arch/arm64/boot/dts/vendor/qcom
            mv .dts.bak arch/arm64/boot/dts/vendor/qcom
            print_success "设备树恢复完成"
        fi
    fi

    # 创建刷机包
    cd anykernel
    local timestamp=$(date +'%Y%m%d_%H%M%S')
    local zip_filename="Kernel_${system_type}_${TARGET_DEVICE}_${KSU_ZIP_STR}_${timestamp}_anykernel3_${GIT_COMMIT_ID}.zip"

    # 打包
    zip -r9 "$zip_filename" ./* -x .git .gitignore out/ ./*.zip
    
    if [ $? -eq 0 ] && [ -f "$zip_filename" ]; then
        mv "$zip_filename" ../
        print_success "${system_type}刷机包创建成功: $zip_filename"
        print_info "文件大小: $(du -h "../$zip_filename" | cut -f1)"
    else
        error_exit "${system_type}刷机包创建失败"
    fi
    cd ..
}

# AOSP构建函数
build_aosp() {
    if [ "$BUILD_AOSP" = true ]; then
        print_step "开始构建AOSP内核"
        
        # 清理
        rm -rf out/
        
        # 配置
        make $MAKE_ARGS ${TARGET_DEVICE}_defconfig
        setup_version_info
        configure_kernelsu
        
        # 编译 - 使用ccache加速
        local start_time=$(date +%s)
        print_info "开始编译AOSP内核（使用ccache加速）..."
        make $MAKE_ARGS -j$(nproc)
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        # 检查结果
        if [ -f "out/arch/arm64/boot/Image" ]; then
            print_success "AOSP内核编译成功，耗时: $((duration / 60))分$((duration % 60))秒"
            
            # 显示ccache统计
            print_info "AOSP编译ccache统计:"
            if command -v ccache >/dev/null 2>&1; then
                ccache -s 2>/dev/null | grep -E "(hit rate|cache hit|cache miss)" || echo "无法获取ccache统计"
            fi
        else
            error_exit "AOSP内核编译失败"
        fi
        
        # 打包
        image_repack "AOSP"
        print_success "AOSP内核构建完成"
    fi
}

# MIUI构建函数
build_miui() {
    if [ "$BUILD_MIUI" = true ]; then
        print_step "开始构建MIUI内核"
        
        # 清理
        rm -rf out/
        
        dts_source=arch/arm64/boot/dts/vendor/qcom

        # 备份dts
        cp -a ${dts_source} .dts.bak

        print_info "MIUI设备树修改"
        
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

        # 配置
        make $MAKE_ARGS ${TARGET_DEVICE}_defconfig
        setup_version_info
        configure_kernelsu
        
        # MIUI特定配置
        print_info "应用MIUI特定配置..."
        scripts/config --file out/.config \
            --set-str STATIC_USERMODEHELPER_PATH /system/bin/micd \
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

        # 编译 - 使用ccache加速
        local start_time=$(date +%s)
        print_info "开始编译MIUI内核（使用ccache加速）..."
        make $MAKE_ARGS -j$(nproc)
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        # 检查结果
        if [ -f "out/arch/arm64/boot/Image" ]; then
            print_success "MIUI内核编译成功，耗时: $((duration / 60))分$((duration % 60))秒"
            
            # 显示ccache统计
            print_info "MIUI编译ccache统计:"
            if command -v ccache >/dev/null 2>&1; then
                ccache -s 2>/dev/null | grep -E "(hit rate|cache hit|cache miss)" || echo "无法获取ccache统计"
            fi
        else
            error_exit "MIUI内核编译失败"
        fi
        
        # 打包
        image_repack "MIUI"
        
        # 恢复设备树
        if [ -d ".dts.bak" ]; then
            rm -rf arch/arm64/boot/dts/vendor/qcom
            mv .dts.bak arch/arm64/boot/dts/vendor/qcom
            print_success "设备树恢复完成"
        fi
        
        print_success "MIUI内核构建完成"
    fi
}

# 主构建函数
main_build() {
    local start_time=$(date +%s)
    
    print_step "开始内核构建流程"
    print_info "目标设备: $TARGET_DEVICE"
    print_info "KernelSU: $KSU_ZIP_STR"
    print_info "构建类型: AOSP=$BUILD_AOSP, MIUI=$BUILD_MIUI"
    print_info "Git提交ID: $GIT_COMMIT_ID"
    
    # 1. 执行KSU补丁脚本
    if [ $KSU_ENABLE -eq 1 ]; then
        execute_ksu_patch_scripts
    else
        print_info "跳过KSU补丁脚本（KSU未启用）"
    fi
    
    # 2. 执行SUSFS补丁处理
    handle_susfs_patch

    # 准备AnyKernel3
    prepare_anykernel
    
    # 执行构建
    build_aosp
    build_miui
    
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    print_step "构建完成"
    print_success "所有构建任务完成! 总耗时: $((total_duration / 60))分$((total_duration % 60))秒"
    
    # 显示ccache最终统计
    print_step "ccache最终统计"
    if command -v ccache >/dev/null 2>&1; then
        ccache -s 2>/dev/null || echo "无法获取ccache统计信息"
    else
        echo "ccache命令未安装"
    fi
    
    # 显示生成的刷机包
    print_info "生成的刷机包:"
    ls -la Kernel_*.zip 2>/dev/null || print_warning "未找到刷机包文件"
    
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
    
    # 显示ccache命中率
    if command -v ccache >/dev/null 2>&1; then
        local hit_rate=$(ccache -s 2>/dev/null | grep "hit rate" | awk '{print $4}' || echo "N/A")
        color_echo "$green" "ccache命中率: $hit_rate"
    fi
}

# 错误处理陷阱
trap 'error_exit "脚本在行数 $LINENO 处发生错误"' ERR

# 信号处理
trap '
    echo
    color_echo "$red" "=============================================="
    color_echo "$red" "脚本被用户中断"
    color_echo "$red" "=============================================="
    exit 1
' INT TERM

# --- 执行主流程 ---
main_build

echo
color_echo "$green" "=============================================="
color_echo "$green" "内核构建脚本执行完成!"
color_echo "$green" "=============================================="

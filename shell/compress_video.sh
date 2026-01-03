#!/bin/zsh

# 视频压缩脚本
# 功能：递归查找并压缩目标目录下所有大于100MB的视频文件，压缩后替换源文件
# 环境：macOS + zsh

# 设置UTF-8编码以支持中文文件名和目录名
# export LANG=zh_CN.UTF-8
# export LC_ALL=zh_CN.UTF-8
# export LC_CTYPE=zh_CN.UTF-8

# 错误处理：即使某个文件失败也继续处理
set -eo pipefail  # 允许管道失败，但保持错误退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $*" | tee -a "$LOG_FILE"
}

log_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] ${RED}ERROR: $*${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] ${GREEN}SUCCESS: $*${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] ${YELLOW}WARNING: $*${NC}" | tee -a "$LOG_FILE"
}

# 使用说明
usage() {
    echo "用法: $0 <目标目录>"
    echo ""
    echo "参数说明:"
    echo "  目标目录    - 要搜索并压缩视频文件的目录"
    echo ""
    echo "注意: 压缩后的视频会直接替换原文件"
    echo ""
    echo "示例:"
    echo "  $0 /path/to/videos"
    exit 1
}

# 检查参数
if [ $# -lt 1 ]; then
    usage
fi

TARGET_DIR="$1"
# 转换为绝对路径
TARGET_DIR=$(cd "$TARGET_DIR" && pwd)
MIN_SIZE=$((100 * 1024 * 1024))  # 100MB in bytes

# 创建日志文件（使用绝对路径）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$SCRIPT_DIR"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/compress-videos.log"
if [ -f "$LOG_FILE" ]; then
    rm -f "$LOG_FILE"
fi

# 清理旧的压缩相关临时文件
log "清理旧的临时文件..."
cleanup_temp_files() {
    rm -f /tmp/video-compress-* 2>/dev/null || true
    find "$TARGET_DIR" -type f -name ".tmp_*_compressed.*" -delete 2>/dev/null || true
}
cleanup_temp_files
log "临时文件清理完成"

log "视频压缩脚本启动"
log "目标目录: $TARGET_DIR"
log "最小文件大小: 100MB"
log "日志文件: $LOG_FILE"

# 检查目标目录是否存在
if [ ! -d "$TARGET_DIR" ]; then
    log_error "目标目录 '$TARGET_DIR' 不存在"
    exit 1
fi

# 检查是否安装了ffmpeg
if ! command -v ffmpeg &> /dev/null; then
    log_error "未找到 ffmpeg"
    log "请先安装 ffmpeg: brew install ffmpeg"
    exit 1
fi
log "ffmpeg 版本: $(ffmpeg -version | head -n 1)"

# 支持的视频扩展名
VIDEO_EXTENSIONS=("mp4" "mov" "mkv" "avi" "flv" "wmv" "webm" "m4v" "ts" "mts" "m2ts")

# 查找所有大于100MB的视频文件
log "开始搜索大于 100MB 的视频文件..."
echo -e "${GREEN}正在搜索大于 100MB 的视频文件...${NC}"
echo ""

FOUND_FILES=0
COMPRESSED=0
FAILED=0
TOTAL_ORIGINAL_SIZE=0
TOTAL_COMPRESSED_SIZE=0

# 创建临时文件存储找到的视频文件列表（明确指定在/tmp目录下）
TEMP_FILE="/tmp/video-compress-files-$$"
rm -f "$TEMP_FILE" 2>/dev/null || true
log "临时文件: $TEMP_FILE"

# 递归查找视频文件并筛选大于100MB的
find "$TARGET_DIR" -type f \( \
    -iname "*.mp4" -o \
    -iname "*.mov" -o \
    -iname "*.mkv" -o \
    -iname "*.avi" -o \
    -iname "*.flv" -o \
    -iname "*.wmv" -o \
    -iname "*.webm" -o \
    -iname "*.m4v" -o \
    -iname "*.ts" -o \
    -iname "*.mts" -o \
    -iname "*.m2ts" \
\) -size +100M > "$TEMP_FILE"

# 显示找到的视频文件列表
log "${YELLOW}找到以下文件:${NC}"
while IFS= read -r file; do
    size=$(stat -f%z "$file")
    size_mb=$((size / 1024 / 1024))
    # echo "  - $file (${size_mb}MB)"
    log "待处理文件: $file (${size_mb}MB)"
done < "$TEMP_FILE"

# 统计文件数量
FOUND_FILES=$(wc -l < "$TEMP_FILE" | tr -d ' ')

log "找到 $FOUND_FILES 个视频文件"
if [ "$FOUND_FILES" -eq 0 ]; then
    log "未找到大于 100MB 的视频文件"
    echo -e "${YELLOW}未找到大于 100MB 的视频文件${NC}"
    rm -f "$TEMP_FILE"
    exit 0
fi

# 计算原始文件总大小
log "计算原始文件总大小"
TOTAL_ORIGINAL_SIZE=0
while IFS= read -r file; do
    size=$(stat -f%z "$file")
    TOTAL_ORIGINAL_SIZE=$((TOTAL_ORIGINAL_SIZE + size))
done < "$TEMP_FILE"

log "找到 $FOUND_FILES 个视频文件，原始总大小: $((TOTAL_ORIGINAL_SIZE / 1024 / 1024))MB"
echo ""
echo "=========================================="
echo "压缩计划"
echo "=========================================="
echo "目标目录: $TARGET_DIR"
echo "文件数量: $FOUND_FILES"
echo "最小文件大小: 100MB"
echo "原始总大小: $((TOTAL_ORIGINAL_SIZE / 1024 / 1024))MB"
echo "压缩参数: H.264 (CRF 23), AAC (128kbps)"
echo "=========================================="
echo ""
echo -e "${YELLOW}将压缩以下文件:${NC}"
while IFS= read -r file; do
    size=$(stat -f%z "$file")
    size_mb=$((size / 1024 / 1024))
    echo "  - $file (${size_mb}MB)"
done < "$TEMP_FILE"
echo ""
echo "=========================================="
echo ""
echo "开始压缩..."
echo ""

# 调试：显示临时文件内容
log "=== 调试：显示临时文件内容 ==="
log "临时文件: $TEMP_FILE"
log "临时文件行数: $(wc -l < "$TEMP_FILE" | tr -d ' ')"
log "临时文件内容（前5行）:"
head -5 "$TEMP_FILE" | while IFS= read -r line; do
    log "  [$line]"
done
log "=== 调试结束 ==="
log "=== 开始压缩处理 ==="

# 压缩函数
compress_video() {
    local input_file="$1"

    log "压缩函数接收到的参数: [$input_file]"
    log "参数长度: ${#input_file}"

    # 验证文件存在性
    if [ ! -f "$input_file" ]; then
        log_error "文件不存在或路径错误: $input_file"
        echo -e "${RED}错误: 文件不存在或路径错误${NC}"
        echo "  输入路径: $input_file"
        ((FAILED++))
        return 1
    fi

    local file_size=$(stat -f%z "$input_file")
    local file_size_mb=$((file_size / 1024 / 1024))

    log "开始压缩: $input_file (${file_size_mb}MB)"
    echo -e "${YELLOW}正在压缩: $input_file (${file_size_mb}MB)${NC}"
    log "原始大小: ${file_size_mb}MB"

    # 切换到文件所在目录
    local file_dir=$(dirname "$input_file")
    local file_name=$(basename "$input_file")
    local file_ext="${file_name##*.}"

    # 验证目录存在
    log "切换到目录 $file_dir"
    log "文件名: [$file_name]"
    log "文件扩展名: [$file_ext]"

    if [ ! -d "$file_dir" ]; then
        log_error "目录不存在: $file_dir"
        ((FAILED++))
        return 1
    fi

    cd "$file_dir" || {
        log_error "无法切换到目录: $file_dir"
        echo -e "${RED}无法切换到目录: $file_dir${NC}"
        ((FAILED++))
        return 1
    }

    log "cd后的当前目录: $(pwd)"

    # 验证文件在当前目录
    if [ ! -f "$file_name" ]; then
        log_error "cd后在当前目录找不到文件: $file_name"
        log_error "当前目录文件列表: $(ls -la | head -5)"
        ((FAILED++))
        return 1
    fi

    # 创建临时输出文件（放在/tmp目录下）
    local temp_output="/tmp/video-compress-${RANDOM}.${file_ext}"
    local start_time=$(date +%s)

    # 使用ffmpeg压缩视频
    # 编码选项说明：
    # -c:v libx264: 使用H.264编码器
    # -crf 23: 质量参数（18-28，值越小质量越好，文件越大）
    # -preset medium: 编码速度与压缩率的平衡（ultrafast/fast/medium/slow/veryslow）
    # -c:a aac: 使用AAC音频编码
    # -b:a 128k: 音频比特率
    # -movflags +faststart: 优化MP4播放，让视频可以边下载边播放

    log "开始压缩文件 ${file_name}"

    # 构建单行命令用于日志
    local ffmpeg_cmd="ffmpeg -i \"${file_name}\" -hide_banner -loglevel error -c:v libx264 -crf 23 -preset medium -c:a aac -b:a 128k -movflags +faststart -y \"${temp_output}\""
    log "执行压缩命令: $ffmpeg_cmd"

    # 执行ffmpeg命令进行视频压缩
    # 需要特别注意:
    #   ffmpeg命令会读取标准输入,因此要在命令后添加< /dev/null,以防止ffmpeg命令读取标准输入
    #   如果不添加< /dev/null,ffmpeg命令会读取标准输入,导致ffmpeg命令无法正常执行
    #
    #   ffmpeg 正在读取标准输入，这导致 while 循环读取到的文件路径被 ffmpeg "吃掉"了！
    #   当 ffmpeg 命令在 while 循环中执行时，如果没有明确指定输入源，它会尝试从标准输入读取。
    #   由于 while 循环正在从 $TEMP_FILE 读取，ffmpeg 就会把剩余的行都读走，导致下一次迭代时读取不到正确的路径。
    ffmpeg -i "${file_name}" \
        -hide_banner \
        -loglevel error \
        -c:v libx264 \
        -crf 23 \
        -preset medium \
        -c:a aac \
        -b:a 128k \
        -movflags +faststart \
        -y "$temp_output" < /dev/null \
        2>&1 | tee -a "$LOG_FILE"

    # ffmpeg命令是否执行成功
    if [ $? -eq 0 ]; then
    
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        # 验证输出文件是否有效
        if [ -s "$temp_output" ]; then
            local output_size=$(stat -f%z "$temp_output")
            local output_size_mb=$((output_size / 1024 / 1024))
            local reduction=$(( (file_size - output_size) * 100 / file_size ))

            # 用临时文件替换原文件
            if mv "$temp_output" "$file_name"; then
                log_success "压缩成功: $input_file"
                log "  原始大小: ${file_size_mb}MB"
                log "  压缩后大小: ${output_size_mb}MB"
                log "  压缩率: ${reduction}%"
                log "  耗时: ${duration}秒"
                echo -e "${GREEN}  ✓ 压缩成功${NC}: ${output_size_mb}MB (节省 ${reduction}%, 耗时 ${duration}秒)"
                ((COMPRESSED++))
                # 累加压缩后文件大小
                TOTAL_COMPRESSED_SIZE=$((TOTAL_COMPRESSED_SIZE + output_size))
            else
                log_error "压缩成功但无法替换文件: $input_file"
                echo -e "${RED}  ✗ 压缩成功但无法替换文件，保留原文件${NC}"
                ((FAILED++))
                rm -f "$temp_output"
            fi
        else
            log_error "压缩失败: $input_file - 输出文件无效"
            echo -e "${RED}  ✗ 压缩失败: 输出文件无效，保留源文件${NC}"
            ((FAILED++))
            rm -f "$temp_output"
        fi
    else
        log_error "压缩失败: $input_file"
        echo -e "${RED}  ✗ 压缩失败，保留源文件${NC}"
        ((FAILED++))
        # 删除可能损坏的临时输出文件
        rm -f "$temp_output"
    fi

    # 切换回原目录
    cd - >/dev/null || true
}

# 导出函数以便在子shell中使用
export -f compress_video


# 串行处理
while IFS= read -r file; do
    # 添加调试日志
    log "从TEMP_FILE读取到: [$file]"
    log "读取到的路径长度: ${#file}"

    # 直接使用读取的文件路径，不做任何处理
    [ -z "$file" ] && continue

    # 验证文件路径
    if [ ! -f "$file" ]; then
        log_warning "跳过不存在的文件: $file"
        continue
    fi

    compress_video "$file" || true  # 即使失败也继续
done < "$TEMP_FILE"

# 清理临时文件
rm -f "$TEMP_FILE"

# 清理所有压缩相关的临时文件
log "清理压缩临时文件..."
cleanup_temp_files
log "临时文件清理完成"

# 输出统计信息
echo ""
echo "=========================================="
echo -e "${GREEN}压缩完成！${NC}"
echo "=========================================="
echo "总体统计:"
echo "  找到文件: $FOUND_FILES"
echo -e "  成功压缩: ${GREEN}$COMPRESSED${NC}"
echo -e "  失败文件: ${RED}$FAILED${NC}"
echo ""
echo "大小统计:"
if [ $COMPRESSED -gt 0 ]; then
    local total_saved=$((TOTAL_ORIGINAL_SIZE - TOTAL_COMPRESSED_SIZE))
    local saved_mb=$((total_saved / 1024 / 1024))
    local saved_percent=$(( total_saved * 100 / TOTAL_ORIGINAL_SIZE ))
    echo "  原始总大小: $((TOTAL_ORIGINAL_SIZE / 1024 / 1024))MB"
    echo "  压缩后大小: $((TOTAL_COMPRESSED_SIZE / 1024 / 1024))MB"
    echo -e "  节省空间: ${GREEN}${saved_mb}MB (${saved_percent}%)${NC}"
fi
echo ""
echo "日志文件: $LOG_FILE"
echo "=========================================="

log "=== 压缩完成 ==="
log "找到文件: $FOUND_FILES"
log "成功压缩: $COMPRESSED"
log "失败文件: $FAILED"
if [ $COMPRESSED -gt 0 ]; then
    local total_saved=$((TOTAL_ORIGINAL_SIZE - TOTAL_COMPRESSED_SIZE))
    local saved_mb=$((total_saved / 1024 / 1024))
    local saved_percent=$(( total_saved * 100 / TOTAL_ORIGINAL_SIZE ))
    log "原始总大小: $((TOTAL_ORIGINAL_SIZE / 1024 / 1024))MB"
    log "压缩后大小: $((TOTAL_COMPRESSED_SIZE / 1024 / 1024))MB"
    log "节省空间: ${saved_mb}MB (${saved_percent}%)"
fi
log "日志文件: $LOG_FILE"
log "=== 脚本执行完成 ==="


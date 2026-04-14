#!/bin/bash
#
# 将 TAN_Android_SDK_Release 的 aar 产物复制到 TAN_Android_Maven 仓库并推送
#
# 用法:
#   ./publish_aar.sh <分支名> <release路径> <maven路径>
#
# 示例:
#   ./publish_aar.sh "1.5.3" "/path/to/TAN_Android_SDK_Release" "/path/to/TAN_Android_Maven"
#   ./publish_aar.sh "adapt/1.5.3.1-Wetv" "/path/to/TAN_Android_SDK_Release" "/path/to/TAN_Android_Maven"
#   ./publish_aar.sh "adapt/1.5.3.1-Joox" "/path/to/TAN_Android_SDK_Release" "/path/to/TAN_Android_Maven"
#   ./publish_aar.sh "adapt/1.5.3.1-Wesing" "/path/to/TAN_Android_SDK_Release" "/path/to/TAN_Android_Maven"

set -e

BRANCH_NAME="$1"
RELEASE_DIR="$2"
MAVEN_DIR="$3"

if [ -z "$BRANCH_NAME" ] || [ -z "$RELEASE_DIR" ] || [ -z "$MAVEN_DIR" ]; then
    echo "错误: 参数不足"
    echo "用法: $0 <分支名> <release路径> <maven路径>"
    exit 1
fi

PACKAGE_DIR="$RELEASE_DIR/package"

if [ ! -d "$PACKAGE_DIR" ]; then
    echo "错误: package 目录不存在: $PACKAGE_DIR"
    exit 1
fi

# ============================================================
# 分支名 → Maven 版本目录名 映射
#
# 规则:
#   "1.5.3"                  → "1.5.3"
#   "adapt/1.5.3.1-Wetv"     → "1.5.3-WeTV"
#   "adapt/1.5.3.1-Joox"     → "1.5.3-Joox"
#   "adapt/1.5.3.1-Wesing"   → "1.5.3-Wesing"
# ============================================================

map_branch_to_version() {
    local branch="$1"

    # 主版本分支: 纯版本号，如 "1.5.3"
    if [[ "$branch" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$branch"
        return
    fi

    # adapt 分支: "adapt/1.5.3.1-Wetv" → "1.5.3-WeTV"
    if [[ "$branch" =~ ^adapt/([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+-(.+)$ ]]; then
        local base_version="${BASH_REMATCH[1]}"
        local suffix="${BASH_REMATCH[2]}"

        # 后缀名大小写映射（分支名可能大小写不规范，统一映射到标准名）
        case "${suffix,,}" in
            wetv)    suffix="WeTV" ;;
            joox)    suffix="Joox" ;;
            wesing)  suffix="Wesing" ;;
            *)
                # 未知后缀，首字母大写
                suffix="$(echo "${suffix:0:1}" | tr '[:lower:]' '[:upper:]')${suffix:1}"
                ;;
        esac

        echo "${base_version}-${suffix}"
        return
    fi

    echo "错误: 无法识别的分支格式: $branch" >&2
    exit 1
}

VERSION_DIR_NAME=$(map_branch_to_version "$BRANCH_NAME")
TARGET_DIR="$MAVEN_DIR/$VERSION_DIR_NAME"

echo "========================================="
echo "分支名:       $BRANCH_NAME"
echo "映射目录名:   $VERSION_DIR_NAME"
echo "源目录:       $PACKAGE_DIR"
echo "目标目录:     $TARGET_DIR"
echo "========================================="

# 创建目标目录（如果已存在则先清空旧 aar）
mkdir -p "$TARGET_DIR"
rm -f "$TARGET_DIR"/*.aar

# 复制所有 aar 文件
AAR_COUNT=$(ls "$PACKAGE_DIR"/*.aar 2>/dev/null | wc -l | tr -d ' ')
if [ "$AAR_COUNT" -eq 0 ]; then
    echo "错误: package 目录下没有 aar 文件"
    exit 1
fi

cp "$PACKAGE_DIR"/*.aar "$TARGET_DIR/"

echo "已复制 ${AAR_COUNT} 个 aar 文件:"
ls -la "$TARGET_DIR"/*.aar

# Git 提交并推送
cd "$MAVEN_DIR"
git add .
git commit -m "Add version $VERSION_DIR_NAME"
git push

echo "========================================="
echo "完成! 版本 $VERSION_DIR_NAME 已推送到 Maven 仓库"
echo "========================================="

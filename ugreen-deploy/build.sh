#!/bin/sh
# 绿联 NAS 部署包构建脚本：构建 api + web 两个 linux/amd64 镜像并导出 tar。
# 在仓库任意位置运行均可：./ugreen-deploy/build.sh
#
# 它保证 web 镜像一定使用本目录的 nginx.conf.template（修正版，根路径 308 跳转）：
#   1. 构建前先校验修正版确实带着修正标记（防止被原版意外覆盖回去）；
#   2. 构建前自动用它覆盖 web/nginx.conf.template，构建结束（无论成败）自动还原，
#      仓库不留任何改动；
#   3. 构建后从镜像里把模板读回来逐字节比对，不一致直接报错、绝不导出 tar；
#   4. 若上游 web/nginx.conf.template 与上次记录的基线不同（升级了源码），先停下来，
#      要求把三处改动重新套用到新版模板（清单在修正版文件头），再带 --refresh-baseline
#      重跑，更新基线。
#
# 版本号自动取自 frontend/package.json；版本变化后记得同步改 compose 里的 image 两行。
set -eu

KIT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$KIT_DIR/.." && pwd)
UPSTREAM="$ROOT_DIR/web/nginx.conf.template"
MODIFIED="$KIT_DIR/nginx.conf.template"
BASELINE="$KIT_DIR/template-baseline.sha"

REFRESH=0
case "${1-}" in
    --refresh-baseline) REFRESH=1 ;;
    "") ;;
    *) echo "用法：$0 [--refresh-baseline]" >&2; exit 2 ;;
esac

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        echo "需要 sha256sum 或 shasum 来校验模板" >&2; return 1
    fi
}

V=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$ROOT_DIR/frontend/package.json" | head -n 1)
if [ -z "$V" ]; then echo "无法从 frontend/package.json 读取版本号" >&2; exit 1; fi
API_TAG="opengym-api:$V-amd64"
WEB_TAG="opengym-web:$V-amd64"
TAR="$KIT_DIR/opengym-$V-amd64.tar"

echo "== 版本 ${V}，镜像 ${API_TAG} / ${WEB_TAG} =="

# 1. 修正版必须真的是修正版（含修正标记），否则后面全部白做
if ! grep -q 'NAS 直连修正 1/3' "$MODIFIED"; then
    echo "错误：${MODIFIED} 缺少修正标记（NAS 直连修正 1/3）。" >&2
    echo "它可能被上游原版覆盖了。按其文件头的三处改动清单重新套用后再构建。" >&2
    exit 1
fi

# 2. 上游模板漂移检测：基线记录的是「修正版派生自哪个上游版本」
ORIG_SHA=$(sha256_of "$UPSTREAM")
if [ -f "$BASELINE" ] && [ "$(cat "$BASELINE")" != "$ORIG_SHA" ] && [ "$REFRESH" != "1" ]; then
    echo "错误：上游 web/nginx.conf.template 与上次构建时不同（源码升级过？）。" >&2
    echo "请对照新版上游模板，把三处改动重新套用到 ${MODIFIED}（清单在其文件头），" >&2
    echo "然后运行：$0 --refresh-baseline" >&2
    exit 1
fi

# 3. 换模板 → 构建 → 还原（trap 保证失败也还原）
BACKUP=$(mktemp)
cp "$UPSTREAM" "$BACKUP"
restore() { cp "$BACKUP" "$UPSTREAM"; rm -f "$BACKUP"; }
trap restore EXIT INT TERM
cp "$MODIFIED" "$UPSTREAM"

echo "== 构建 api =="
docker build --pull --platform linux/amd64 -t "$API_TAG" "$ROOT_DIR/api"
echo "== 构建 web（用修正版模板）=="
docker build --pull --platform linux/amd64 -t "$WEB_TAG" -f "$ROOT_DIR/web/Dockerfile" "$ROOT_DIR"

restore
trap - EXIT INT TERM

# 4. 硬校验：从镜像里读回模板，逐字节比对
if ! docker run --rm --platform linux/amd64 --entrypoint sh "$WEB_TAG" \
        -c 'cat /etc/nginx/templates/default.conf.template' \
        | diff -q - "$MODIFIED" >/dev/null; then
    echo "错误：镜像里的 nginx 模板与 $MODIFIED 不一致，拒绝导出。" >&2
    exit 1
fi
echo "== 校验通过：web 镜像内嵌的正是修正版模板 =="

# 5. 记录基线（修正版当前派生自的上游版本），下次构建做漂移检测
printf '%s\n' "$ORIG_SHA" > "$BASELINE"

# 6. 导出 tar
docker save "$API_TAG" "$WEB_TAG" -o "$TAR"
echo "== 完成 =="
echo "tar：${TAR}"
echo "镜像：${API_TAG}、${WEB_TAG}"
echo "导入 NAS 后若版本号有变，记得更新 docker-compose.yml 里的 image 两行。"

#!/usr/bin/env bash
# 测试 update-base-image workflow 的核心 bash/python 逻辑
# 运行方式：bash scripts/test-update-logic.sh

set -euo pipefail

PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

WORKFLOW=".github/workflows/update-base-image.yml"

# ── 测试 0：workflow 文件存在 ────────────────────────────────────────────────
if [[ -f "$WORKFLOW" ]]; then
    pass "workflow 文件存在: $WORKFLOW"
else
    fail "workflow 文件不存在: $WORKFLOW"
fi

# ── 测试 1：Python 排序逻辑能从 mock JSON 中取最新 F44 tag（FVER 驱动）────────
MOCK_JSON='{"Tags": ["44.20251224.91.0", "45.20260226.91.1", "44.20260301.92.1", "44.20260218.91.1", "next", "stable"]}'
RESULT=$(export FVER=44; echo "$MOCK_JSON" | python3 -c "
import json, sys, re, os
fver = os.environ['FVER']
tags = json.load(sys.stdin)['Tags']
pattern = re.compile(rf'^{re.escape(fver)}\.\d+\.\d+\.\d+$')
candidates = sorted(
    [t for t in tags if pattern.match(t)],
    key=lambda t: [int(x) for x in t.split('.')],
    reverse=True
)
if not candidates:
    raise SystemExit(f'ERROR: No F{fver} numeric version tags found')
# 模拟：取排序后第一个（实际 workflow 中此处还会验证 arm64 可用性）
print(candidates[0])
")
if [[ "$RESULT" == "44.20260301.92.1" ]]; then
    pass "Python 排序逻辑（FVER=44）：从 mock JSON 取最新 F44 tag ($RESULT)"
else
    fail "Python 排序逻辑（FVER=44）：期望 44.20260301.92.1，实际得到 $RESULT"
fi

# ── 测试 2：Python 脚本在无 F44 tag 时应报错退出 ─────────────────────────────
EMPTY_JSON='{"Tags": ["45.20260226.91.1", "next", "stable", "testing"]}'
if export FVER=44; echo "$EMPTY_JSON" | python3 -c "
import json, sys, re, os
fver = os.environ['FVER']
tags = json.load(sys.stdin)['Tags']
pattern = re.compile(rf'^{re.escape(fver)}\.\d+\.\d+\.\d+$')
candidates = [t for t in tags if pattern.match(t)]
if not candidates:
    raise SystemExit(f'ERROR: No F{fver} numeric version tags found')
print(candidates[0])
" 2>/dev/null; then
    fail "Python 无 F44 tag 场景：应报错退出但未报错"
else
    pass "Python 无 F44 tag 场景：正确报错退出"
fi

# ── 测试 3：grep 能正确从临时 Dockerfile 提取当前 tag ───────────────────────
TMPDIR_TEST=$(mktemp -d)
FAKE_DOCKERFILE="$TMPDIR_TEST/Dockerfile"
cat > "$FAKE_DOCKERFILE" <<'EOF'
FROM quay.io/fedora/fedora-coreos:44.20251224.91.0

ADD configs/overrides.yaml /etc/rpm-ostree/origin.d/overrides.yaml
EOF
CURRENT=$(grep -oP 'fedora-coreos:\K\S+' "$FAKE_DOCKERFILE")
if [[ "$CURRENT" == "44.20251224.91.0" ]]; then
    pass "grep 提取 tag：从临时 Dockerfile 正确提取 ($CURRENT)"
else
    fail "grep 提取 tag：期望 44.20251224.91.0，实际得到 $CURRENT"
fi

# ── 测试 4：sed 替换能正确更新临时 Dockerfile 中的 tag ──────────────────────
NEW_TAG="45.20260226.91.1"
sed -i "s|fedora-coreos:${CURRENT}|fedora-coreos:${NEW_TAG}|" "$FAKE_DOCKERFILE"
UPDATED=$(grep -oP 'fedora-coreos:\K\S+' "$FAKE_DOCKERFILE")
if [[ "$UPDATED" == "$NEW_TAG" ]]; then
    pass "sed 替换 tag：临时 Dockerfile 已更新为 ($UPDATED)"
else
    fail "sed 替换 tag：期望 $NEW_TAG，实际得到 $UPDATED"
fi

# 清理临时文件
rm -rf "$TMPDIR_TEST"

# ── 测试 5：skopeo inspect --raw 输出能被解析为含 arm64 的 manifest ──────────
MOCK_RAW='{"manifests": [{"platform": {"architecture": "amd64"}}, {"platform": {"architecture": "arm64"}}, {"platform": {"architecture": "s390x"}}]}'
ARCH_RESULT=$(echo "$MOCK_RAW" | python3 -c "
import json, sys
data = json.load(sys.stdin)
archs = [m.get('platform', {}).get('architecture') for m in data.get('manifests', [])]
print('arm64' in archs)
")
if [[ "$ARCH_RESULT" == "True" ]]; then
    pass "skopeo --raw manifest 解析：正确识别含 arm64 的 manifest"
else
    fail "skopeo --raw manifest 解析：期望 True，实际得到 $ARCH_RESULT"
fi

# ── 汇总 ─────────────────────────────────────────────────────────────────────
echo ""
echo "结果：$PASS 通过，$FAIL 失败"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi

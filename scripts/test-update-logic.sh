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

# ── 测试 1：Python 脚本能从 mock JSON 中找到最新 F45 tag ─────────────────────
MOCK_JSON='{"Tags": ["44.20251224.91.0", "45.20260101.91.0", "45.20260226.91.1", "45.20260115.91.0", "next", "stable"]}'
RESULT=$(echo "$MOCK_JSON" | python3 -c "
import json, sys
tags = json.load(sys.stdin)['Tags']
f45 = [t for t in tags if t.startswith('45.')]
if not f45:
    raise SystemExit('ERROR: No 45.* tags found')
latest = sorted(f45, key=lambda t: [int(x) for x in t.split('.')], reverse=True)[0]
print(latest)
")
if [[ "$RESULT" == "45.20260226.91.1" ]]; then
    pass "Python 排序逻辑：从 mock JSON 找到最新 F45 tag ($RESULT)"
else
    fail "Python 排序逻辑：期望 45.20260226.91.1，实际得到 $RESULT"
fi

# ── 测试 2：Python 脚本在无 45.* tag 时应报错退出 ────────────────────────────
EMPTY_JSON='{"Tags": ["44.20251224.91.0", "next", "stable"]}'
if echo "$EMPTY_JSON" | python3 -c "
import json, sys
tags = json.load(sys.stdin)['Tags']
f45 = [t for t in tags if t.startswith('45.')]
if not f45:
    raise SystemExit('ERROR: No 45.* tags found')
latest = sorted(f45, key=lambda t: [int(x) for x in t.split('.')], reverse=True)[0]
print(latest)
" 2>/dev/null; then
    fail "Python 无 45.* tag 场景：应报错退出但未报错"
else
    pass "Python 无 45.* tag 场景：正确报错退出"
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

# ── 汇总 ─────────────────────────────────────────────────────────────────────
echo ""
echo "结果：$PASS 通过，$FAIL 失败"
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi

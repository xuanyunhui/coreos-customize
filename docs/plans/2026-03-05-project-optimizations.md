# Project Optimizations Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 对项目进行 8 项优化，涵盖性能、自动化、可维护性、可观测性四个维度。

**Architecture:** 涉及三个文件：`.github/workflows/update-base-image.yml`、`.github/workflows/build.yml`、`scripts/build.sh`。各任务相互独立，可按序执行。

**Tech Stack:** GitHub Actions YAML, bash, Python 3（内联脚本）, skopeo

**设计文档：** `docs/plans/2026-03-05-project-optimizations-design.md`

---

### Task 1：优化 update-base-image.yml（项 1、4、3）

**Files:**
- Modify: `.github/workflows/update-base-image.yml`
- Modify: `scripts/test-update-logic.sh`

**Step 1: 验证 skopeo inspect --raw 能解析 arm64 信息**

```bash
skopeo inspect --raw docker://quay.io/fedora/fedora-coreos:44.20260301.92.1 | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
archs = [m.get('platform', {}).get('architecture') for m in data.get('manifests', [])]
print('architectures:', archs)
print('arm64 available:', 'arm64' in archs)
"
```

预期输出：包含 `arm64 available: True`

**Step 2: 验证从 Dockerfile 提取主版本号**

```bash
grep -oP 'fedora-coreos:\K\d+' Dockerfile
```

预期输出：`44`

**Step 3: 更新 `获取最新支持 arm64 的 tag` 步骤**

将 Python 内联脚本改为：
1. 从环境变量 `FVER` 接收主版本号（bash 传入）
2. 用 `skopeo inspect --raw` 替代 `skopeo inspect --override-arch arm64`

完整步骤改为：

```yaml
      - name: 获取最新支持 arm64 的 tag
        id: get_tag
        run: |
          FVER=$(grep -oP 'fedora-coreos:\K\d+' Dockerfile)
          LATEST=$(skopeo list-tags docker://quay.io/fedora/fedora-coreos | \
            python3 -c "
          import json, sys, re, subprocess, os
          fver = os.environ['FVER']
          tags = json.load(sys.stdin)['Tags']
          pattern = re.compile(rf'^{re.escape(fver)}\.\d+\.\d+\.\d+$')
          candidates = sorted(
              [t for t in tags if pattern.match(t)],
              key=lambda t: [int(x) for x in t.split('.')],
              reverse=True
          )
          for tag in candidates:
              r = subprocess.run(
                  ['skopeo', 'inspect', '--raw',
                   f'docker://quay.io/fedora/fedora-coreos:{tag}'],
                  capture_output=True
              )
              if r.returncode != 0:
                  continue
              try:
                  data = json.loads(r.stdout)
              except json.JSONDecodeError:
                  continue
              archs = [m.get('platform', {}).get('architecture')
                       for m in data.get('manifests', [])]
              if 'arm64' in archs:
                  print(tag)
                  sys.exit(0)
          raise SystemExit(f'ERROR: No F{fver} arm64-compatible tag found')
          " FVER="$FVER")
          echo "latest=${LATEST}" >> "$GITHUB_OUTPUT"
```

**Step 4: 更新 `提交更改` 步骤以使用 PAT**

将"提交更改"步骤改为：

```yaml
      - name: 提交更改
        if: steps.get_tag.outputs.latest != steps.current_tag.outputs.current
        env:
          LATEST: ${{ steps.get_tag.outputs.latest }}
          # AUTO_UPDATE_TOKEN 需在仓库 Settings → Secrets → Actions 中手动创建
          # 该 PAT 需具备 contents: write 权限
          # 使用 PAT 推送使 GitHub 将本次 commit 视为普通用户操作，从而触发 build.yml
          GH_TOKEN: ${{ secrets.AUTO_UPDATE_TOKEN }}
        run: |
          git remote set-url origin https://x-access-token:${GH_TOKEN}@github.com/${{ github.repository }}
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add Dockerfile
          git commit -m "Update base image to fedora-coreos:${LATEST}"
          git push
```

**Step 5: 更新测试脚本以反映新逻辑**

在 `scripts/test-update-logic.sh` 中：
- Test 1 的 Python 脚本改用 `FVER` 环境变量驱动的 pattern（用 `export FVER=44` mock）
- 添加 Test 5：验证 `skopeo inspect --raw` 输出能被正确解析为含 arm64 的 manifest

**Step 6: 验证 YAML 语法和测试脚本**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/update-base-image.yml'))" && echo "YAML OK"
bash scripts/test-update-logic.sh
```

**Step 7: 提交**

```bash
git add .github/workflows/update-base-image.yml scripts/test-update-logic.sh
git commit -m "Optimize update-base-image: raw manifest arm64 check, dynamic fver, PAT push"
```

---

### Task 2：优化 build.yml（项 2、6、7、8）

**Files:**
- Modify: `.github/workflows/build.yml`

**Step 1: 升级 Action 版本**

- `actions/checkout@v3` → `actions/checkout@v4`
- `docker/setup-qemu-action@v2` → `docker/setup-qemu-action@v3`

**Step 2: 删除 --log-level debug**

将 `extra-args` 块整个删除或改为空：

```yaml
      extra-args: |
```
（删除 `--log-level debug` 行）

**Step 3: 在推送成功后添加 GHCR 清理步骤**

在"推送到GitHub容器注册表"步骤之后添加：

```yaml
      - name: 清理旧版本镜像
        if: github.event_name != 'pull_request'
        uses: actions/delete-package-versions@v5
        with:
          package-name: ${{ env.IMAGE_NAME }}
          package-type: container
          min-versions-to-keep: 5
          token: ${{ secrets.GITHUB_TOKEN }}
```

**Step 4: 在末尾添加构建失败摘要步骤**

```yaml
      - name: 构建失败摘要
        if: failure()
        run: |
          echo "## ❌ 构建失败" >> $GITHUB_STEP_SUMMARY
          echo "- 时间: $(date)" >> $GITHUB_STEP_SUMMARY
          echo "- 触发事件: ${{ github.event_name }}" >> $GITHUB_STEP_SUMMARY
          echo "- Commit: ${{ github.sha }}" >> $GITHUB_STEP_SUMMARY
```

**Step 5: 验证 YAML 语法**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build.yml'))" && echo "YAML OK"
```

**Step 6: 提交**

```bash
git add .github/workflows/build.yml
git commit -m "Upgrade action versions, remove debug log, add GHCR cleanup and failure summary"
```

---

### Task 3：修复 scripts/build.sh（项 9）

**Files:**
- Modify: `scripts/build.sh`

**Step 1: 添加平台参数逻辑**

在 `$CONTAINER_ENGINE build ...` 行之前插入：

```bash
ARCH=$(uname -m)
PLATFORM_ARGS=""
if [[ "$ARCH" != "aarch64" ]]; then
    echo "检测到非 arm64 主机 (${ARCH})，追加 --platform linux/arm64"
    PLATFORM_ARGS="--platform linux/arm64"
fi
```

将构建命令改为：

```bash
$CONTAINER_ENGINE build $PLATFORM_ARGS -t $TAG .
```

**Step 2: 验证脚本语法**

```bash
bash -n scripts/build.sh && echo "语法正确"
```

**Step 3: 提交**

```bash
git add scripts/build.sh
git commit -m "Add --platform linux/arm64 for non-arm64 hosts in build.sh"
```

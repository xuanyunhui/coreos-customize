# Auto Update Base Image Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 新增 GitHub Actions workflow，每周自动检测 `quay.io/fedora/fedora-coreos` 的 F45 最新 tag，发现新版本时自动更新 `Dockerfile` 并提交到 main 分支。

**Architecture:** 单独一个新 workflow 文件 `.github/workflows/update-base-image.yml`，不修改任何现有文件。workflow 通过 `skopeo list-tags` 获取 tag 列表，用内联 Python 脚本排序取最新 F45 tag，与当前 Dockerfile 对比，有差异时用 `sed` 替换并 git commit & push。

**Tech Stack:** GitHub Actions, skopeo（ubuntu-latest 预装）, Python 3（内联脚本）, bash, git

---

### Task 1: 创建 update-base-image workflow 文件

**Files:**
- Create: `.github/workflows/update-base-image.yml`

**Step 1: 验证 skopeo 在 ubuntu-latest 上是否预装**

在本地运行以下命令确认 tag 获取逻辑可正常工作：

```bash
skopeo list-tags docker://quay.io/fedora/fedora-coreos | \
  python3 -c "
import json, sys
tags = json.load(sys.stdin)['Tags']
f45 = [t for t in tags if t.startswith('45.')]
if not f45:
    raise SystemExit('ERROR: No 45.* tags found')
latest = sorted(f45, key=lambda t: [int(x) for x in t.split('.')], reverse=True)[0]
print(latest)
"
```

预期输出：一行版本号，如 `45.20260226.91.1`

**Step 2: 验证 Dockerfile tag 提取命令**

```bash
grep -oP 'fedora-coreos:\K\S+' Dockerfile
```

预期输出：当前版本号，如 `44.20251224.91.0`

**Step 3: 创建 workflow 文件**

创建 `.github/workflows/update-base-image.yml`，内容如下：

```yaml
name: 自动更新基础镜像 Tag

on:
  schedule:
    - cron: '0 0 * * 1'  # 每周一 UTC 00:00
  workflow_dispatch:       # 支持手动触发

jobs:
  update:
    name: 检测并更新基础镜像
    runs-on: ubuntu-latest
    permissions:
      contents: write

    steps:
      - name: 检出代码
        uses: actions/checkout@v4

      - name: 获取最新 F45 tag
        id: get_tag
        run: |
          LATEST=$(skopeo list-tags docker://quay.io/fedora/fedora-coreos | \
            python3 -c "
          import json, sys
          tags = json.load(sys.stdin)['Tags']
          f45 = [t for t in tags if t.startswith('45.')]
          if not f45:
              raise SystemExit('ERROR: No 45.* tags found in quay.io/fedora/fedora-coreos')
          latest = sorted(f45, key=lambda t: [int(x) for x in t.split('.')], reverse=True)[0]
          print(latest)
          ")
          echo "latest=${LATEST}" >> "$GITHUB_OUTPUT"

      - name: 获取当前 Dockerfile tag
        id: current_tag
        run: |
          CURRENT=$(grep -oP 'fedora-coreos:\K\S+' Dockerfile)
          echo "current=${CURRENT}" >> "$GITHUB_OUTPUT"

      - name: 比较版本并更新
        if: steps.get_tag.outputs.latest != steps.current_tag.outputs.current
        run: |
          CURRENT="${{ steps.current_tag.outputs.current }}"
          LATEST="${{ steps.get_tag.outputs.latest }}"
          echo "发现新版本: ${CURRENT} → ${LATEST}"
          sed -i "s|fedora-coreos:${CURRENT}|fedora-coreos:${LATEST}|" Dockerfile

      - name: 提交更改
        if: steps.get_tag.outputs.latest != steps.current_tag.outputs.current
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add Dockerfile
          git commit -m "Update base image to fedora-coreos:${{ steps.get_tag.outputs.latest }}"
          git push

      - name: 无更新报告
        if: steps.get_tag.outputs.latest == steps.current_tag.outputs.current
        run: echo "当前已是最新版本 ${{ steps.current_tag.outputs.current }}，无需更新。"
```

**Step 4: 验证 YAML 语法**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/update-base-image.yml'))" && echo "YAML 语法正确"
```

预期输出：`YAML 语法正确`

**Step 5: 提交**

```bash
git add .github/workflows/update-base-image.yml
git commit -m "Add workflow to auto-update fedora-coreos base image tag weekly"
```

---

### Task 2: 手动触发验证（推荐）

**Files:**
- 无新增文件，仅验证步骤

**Step 1: 推送到远端后手动触发**

推送代码后，在 GitHub 仓库页面：
`Actions` → `自动更新基础镜像 Tag` → `Run workflow`

**Step 2: 检查 workflow 运行日志**

确认以下步骤均通过：
- `获取最新 F45 tag` → 输出形如 `latest=45.XXXXXXXX.XX.X`
- `获取当前 Dockerfile tag` → 输出当前版本
- 若版本不同：`比较版本并更新` 和 `提交更改` 均为绿色
- 若版本相同：`无更新报告` 输出"当前已是最新版本"

**Step 3: 若触发了更新，确认构建 workflow 也自动运行**

`Actions` 页面中应出现一个新的 `构建自定义CoreOS镜像` 运行记录，由 `github-actions[bot]` 的 commit 触发。

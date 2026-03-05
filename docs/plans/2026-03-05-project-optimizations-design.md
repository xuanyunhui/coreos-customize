# 设计文档：项目全面优化

**日期：** 2026-03-05  
**状态：** 已批准

## 背景

在自动更新基础镜像功能完成后，对项目进行全面审查，发现 8 项可优化点，涵盖性能、安全、可维护性、自动化程度四个维度。

## 优化清单

| 编号 | 文件 | 类型 | 描述 |
|------|------|------|------|
| 1 | `update-base-image.yml` | 性能 | arm64 验证：串行 inspect → 单次 raw manifest 解析 |
| 2 | `build.yml` | 维护性 | Action 版本升级（checkout v3→v4, setup-qemu v2→v3）|
| 3 | `update-base-image.yml` | 自动化 | 使用 PAT 推送，使 build.yml 自动被触发 |
| 4 | `update-base-image.yml` | 维护性 | 消除 F44 硬编码，从 Dockerfile 动态提取主版本号 |
| 6 | `build.yml` | 可读性 | 去掉 `--log-level debug`，减少 CI 日志噪音 |
| 7 | `build.yml` | 可观测性 | 构建失败时生成清晰的 Step Summary |
| 8 | `build.yml` | 存储 | 构建推送后清理 GHCR 旧版本，保留最近 5 个 |
| 9 | `scripts/build.sh` | 一致性 | 非 arm64 本机构建时自动追加 `--platform linux/arm64` |

> 项 5（rpm-ostree 层缓存）因工具本身约束跳过。

---

## 详细设计

### 项 1：arm64 验证性能优化

**文件：** `.github/workflows/update-base-image.yml`

用 `skopeo inspect --raw` 获取 OCI manifest index，解析 `manifests[].platform.architecture`，一次请求判断 arm64 可用性，替代原来的串行 `skopeo inspect --override-arch arm64`：

```python
r = subprocess.run(['skopeo', 'inspect', '--raw',
                    f'docker://quay.io/fedora/fedora-coreos:{tag}'], capture_output=True)
data = json.loads(r.stdout)
archs = [m.get('platform', {}).get('architecture') for m in data.get('manifests', [])]
if 'arm64' in archs:
    print(tag); sys.exit(0)
```

---

### 项 2：Action 版本升级

**文件：** `.github/workflows/build.yml`

| Action | 当前 | 升级后 |
|--------|------|--------|
| `actions/checkout` | `@v3` | `@v4` |
| `docker/setup-qemu-action` | `@v2` | `@v3` |

其余 redhat-actions 保持不变（已是最新稳定版）。

---

### 项 3：PAT 自动触发 build.yml

**文件：** `.github/workflows/update-base-image.yml`

**前置条件（手动操作）：** 在 GitHub → Settings → Secrets → Actions 中创建 `AUTO_UPDATE_TOKEN`，该 PAT 需具备 `contents: write` 权限。

workflow 在推送时使用 PAT，使 commit 被识别为普通用户操作，触发 `build.yml` 的 `push` 事件：

```yaml
- name: 提交更改
  env:
    GH_TOKEN: ${{ secrets.AUTO_UPDATE_TOKEN }}
  run: |
    git remote set-url origin https://x-access-token:${GH_TOKEN}@github.com/${{ github.repository }}
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git add Dockerfile
    git commit -m "Update base image to fedora-coreos:${LATEST}"
    git push
```

---

### 项 4：消除 F44 硬编码

**文件：** `.github/workflows/update-base-image.yml`

从 Dockerfile FROM 行动态提取主版本号，用于构造候选 tag 的正则匹配，升级 Fedora 大版本时无需修改 workflow：

```bash
FVER=$(grep -oP 'fedora-coreos:\K\d+' Dockerfile)
# 传入 python 脚本：pattern = re.compile(rf'^{fver}\.\d+\.\d+\.\d+$')
```

---

### 项 6：去掉 `--log-level debug`

**文件：** `.github/workflows/build.yml`

删除 `buildah-build` 步骤的 `extra-args: --log-level debug`，减少 CI 日志量。

---

### 项 7：构建失败摘要

**文件：** `.github/workflows/build.yml`

在 job 末尾添加 `if: failure()` 步骤，写入 GitHub Step Summary：

```yaml
- name: 构建失败摘要
  if: failure()
  run: |
    echo "## ❌ 构建失败" >> $GITHUB_STEP_SUMMARY
    echo "- 时间: $(date)" >> $GITHUB_STEP_SUMMARY
    echo "- 触发事件: ${{ github.event_name }}" >> $GITHUB_STEP_SUMMARY
    echo "- Commit: ${{ github.sha }}" >> $GITHUB_STEP_SUMMARY
```

---

### 项 8：GHCR 旧版本清理

**文件：** `.github/workflows/build.yml`

推送成功后调用 `actions/delete-package-versions@v5` 保留最近 5 个版本：

```yaml
- name: 清理旧版本镜像
  if: github.event_name != 'pull_request'
  uses: actions/delete-package-versions@v5
  with:
    package-name: custom-coreos
    package-type: container
    min-versions-to-keep: 5
    token: ${{ secrets.GITHUB_TOKEN }}
```

---

### 项 9：`scripts/build.sh` 平台参数

**文件：** `scripts/build.sh`

非 arm64 主机构建时自动追加 `--platform linux/arm64`，保持与 CI 一致：

```bash
ARCH=$(uname -m)
PLATFORM_ARGS=""
if [[ "$ARCH" != "aarch64" ]]; then
    PLATFORM_ARGS="--platform linux/arm64"
fi
$CONTAINER_ENGINE build $PLATFORM_ARGS -t $TAG .
```

---

## 不在范围内

- 项 5：rpm-ostree 层缓存（工具约束，无法优化）
- `AUTO_UPDATE_TOKEN` secret 的创建（需手动在 GitHub 设置）

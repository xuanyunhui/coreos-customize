# 设计文档：自动检测并更新基础镜像 tag

**日期：** 2026-03-05  
**状态：** 已批准

## 背景

`Dockerfile` 中的基础镜像 `quay.io/fedora/fedora-coreos:<tag>` 目前为硬编码版本号，每次上游发布新版本都需要手动修改并提交。历史提交记录显示这是一项频繁的重复工作。

## 目标

新增一个独立的 GitHub Actions workflow，每周自动检测 `quay.io/fedora/fedora-coreos` 仓库中 Fedora 45 系列的最新 tag，发现新版本时自动更新 `Dockerfile` 并提交到 `main` 分支，触发已有的构建流程。

## 需求汇总

| 项目 | 决策 |
|------|------|
| 触发方式 | 每周定时（每周一 UTC 00:00）+ 支持手动触发 |
| 更新方式 | 直接 commit 到 main 分支 |
| tag 获取方法 | `skopeo list-tags` |
| 跟踪范围 | `45.*` 全系列最新 tag |
| 幂等性 | 无新版本时不产生任何 commit |

## 架构

### 数据流

```
[每周 cron / 手动触发]
  → skopeo list-tags docker://quay.io/fedora/fedora-coreos
  → 过滤 45.* 标签，按四段版本号数值排序，取最大值
  → 与 Dockerfile 当前 FROM tag 对比
  ├─ 有新版本 → sed 替换 Dockerfile → git commit & push → 触发 build.yml
  └─ 无新版本 → 跳过，退出 0
```

### 新增文件

- `.github/workflows/update-base-image.yml` — 唯一改动，不修改现有文件

## 关键实现细节

### Tag 排序逻辑

tag 格式为 `45.YYYYMMDD.XX.Y`，按四个数字字段排序取最大值：

```python
tags_f45 = [t for t in tags if t.startswith('45.')]
latest = sorted(tags_f45, key=lambda t: [int(x) for x in t.split('.')], reverse=True)[0]
```

### 提取与替换当前 tag

```bash
CURRENT=$(grep -oP 'fedora-coreos:\K\S+' Dockerfile)
sed -i "s|fedora-coreos:${CURRENT}|fedora-coreos:${LATEST}|" Dockerfile
```

### Git 提交配置

- committer：`github-actions[bot]`
- commit message：`Update base image to fedora-coreos:<新版本号>`

## 错误处理

| 场景 | 处理方式 |
|------|----------|
| `skopeo` 网络失败 | workflow 报错退出，不修改任何文件 |
| 未找到 `45.*` tag | 报错退出并输出提示 |
| 解析/排序失败 | 报错退出 |

## 不在范围内

- 不修改 `build.yml` 或其他现有文件
- 不自动创建 PR（直接 commit）
- 不跟踪 F44 或更早版本

# 用 GitHub 管理 ChessCards 项目 — 使用指南

## 一、前置准备

### 1. 确认已安装 Git

在终端执行：

```bash
git --version
```

若未安装：

- **macOS**：`xcode-select --install`，或从 [git-scm.com](https://git-scm.com/) 下载安装
- 安装后重新打开终端

---

## 二、在项目里启用 Git

在项目根目录（`chess-cards`）下执行：

```bash
cd /Users/bobbyszhang/chess-cards   # 或你实际的项目路径
git init
```

会生成 `.git` 目录，表示该文件夹已是 Git 仓库。

### 配置本项目的 Git 用户信息（仅首次，仅对本仓库生效）

在**同一项目目录下**执行（不加 `--global`，只影响当前项目）：

```bash
git config user.name "你的名字或昵称"
git config user.email "你的GitHub登录邮箱"
```

邮箱建议与 GitHub 账号一致，便于识别提交者。这样配置后，只有在这个仓库里的提交会使用这里的姓名和邮箱，其他项目不受影响。

---

## 三、第一次提交（本地）

### 1. 查看会被跟踪的文件

```bash
git status
```

红色 = 未跟踪，绿色 = 已暂存。确认没有不该提交的文件（如 `.godot/` 已被 `.gitignore` 忽略）。

### 2. 全部加入暂存区并提交

```bash
git add .
git commit -m "Initial commit: Godot 4.6 ChessCards project"
```

`-m` 后面是本次提交的说明，建议简短、说清做了什么。

---

## 四、在 GitHub 上创建仓库并关联

### 1. 在 GitHub 创建新仓库

1. 登录 [github.com](https://github.com/)
2. 右上角 **+** → **New repository**
3. 填写：
   - **Repository name**：例如 `chess-cards`
   - **Description**：可选，如 "Godot 4 棋牌项目"
   - **Public** 或 **Private** 按需选择
   - **不要**勾选 "Add a README"（本地已有项目）
4. 点击 **Create repository**

### 2. 把本地仓库连到 GitHub

创建后 GitHub 会给出命令，通常类似（把 `你的用户名` 和 `chess-cards` 换成你的）：

```bash
git remote add origin https://github.com/你的用户名/chess-cards.git
```

若用 SSH（需先配置 SSH key）：

```bash
git remote add origin git@github.com:你的用户名/chess-cards.git
```

检查是否添加成功：

```bash
git remote -v
```

应看到 `origin` 对应你刚填的地址。

### 3. 推送到 GitHub

首次推送并设置上游分支：

```bash
git branch -M main
git push -u origin main
```

若 GitHub 提示用 `master`，则把上面两处的 `main` 改成 `master` 即可。之后只需执行 `git push`。

---

## 五、日常使用流程

### 推荐节奏：小步提交、经常推送

```
改代码 → 暂存 → 提交 → （可选）推送
```

### 1. 做完一小块功能或修完一个 bug

```bash
git status                  # 看改了哪些文件
git add .                   # 或只加部分：git add res://scenes/xxx.tscn
git commit -m "添加主菜单场景"
git push                    # 推到 GitHub 备份/协作
```

### 2. 写提交信息的习惯

- 用中文或英文都可以，保持项目内统一
- 第一行简短总结，可再空一行写细节，例如：

  ```
  实现玩家移动逻辑

  - 键盘 WASD 控制
  - 与碰撞体检测
  ```

### 3. 从 GitHub 拉取更新（多人或换电脑时）

```bash
git pull
```

若你只在当前电脑开发，且没有别人改同一仓库，可以少用 `pull`，但习惯性每天拉一次也没问题。

---

## 六、常用命令速查

| 操作           | 命令 |
|----------------|------|
| 看当前状态     | `git status` |
| 暂存全部       | `git add .` |
| 暂存指定文件   | `git add 路径/文件` |
| 提交           | `git commit -m "说明"` |
| 推送到 GitHub  | `git push` |
| 从 GitHub 拉取 | `git pull` |
| 看提交历史     | `git log --oneline` |
| 看远程地址     | `git remote -v` |

---

## 七、Godot 项目注意点

- **不要提交**：`.godot/`（引擎缓存）、`export_presets.cfg`（导出配置里可能有本机路径）已写在 `.gitignore` 里。
- **建议提交**：所有 `.gd`、`.tscn`、`.tres`、资源文件、`project.godot`，以及 `.cursor/rules/` 等项目配置。
- 若在 Godot 里改了 `project.godot` 或资源，记得 `git add` 后一起提交。

---

## 八、遇到问题时的排查

- **推送被拒绝**：先执行 `git pull`（必要时 `git pull origin main`），解决冲突后再 `git push`。
- **忘记提交就改了别的**：可先 `git stash`，再提交，再 `git stash pop` 把改动取回。
- **想撤销最后一次提交**：`git reset --soft HEAD~1`（保留改动，只撤销提交）。

按上面步骤做完「二、三、四」，你的 ChessCards 就已经在用 GitHub 做版本管理和备份了。之后按「五、六」做日常提交和推送即可。有需要可以再一起细化分支策略或协作流程。

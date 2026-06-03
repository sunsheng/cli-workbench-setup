# windows-cli-setup

一套用于快速搭建现代命令行环境的脚本与配置，覆盖 **Windows Server / Windows** 和 **Ubuntu Server**：

- Windows：基于 [Scoop](https://scoop.sh) 安装常用 CLI 工具，配置 PowerShell profile、`fzf` 快捷键、`zoxide`、Vim 和 OpenSSH Server。
- Ubuntu Server：基于 apt 安装常用 CLI 工具，配置 bash profile、`fzf` 快捷键、`zoxide`、Vim 和 OpenSSH Server。

> Windows 路径在 Windows Server 2025 / PowerShell 7 上验证；Ubuntu 路径面向 Ubuntu Server 24.04 LTS 及更新版本，并在 GitHub Actions 的 `ubuntu-latest` 上测试。

## 包含的工具

| 工具 | 命令 | Windows | Ubuntu Server | 说明 |
|------|------|---------|---------------|------|
| Scoop | `scoop` | 安装 | 不需要 | Windows 包管理器 |
| apt | `apt` / `apt-get` | 不需要 | 系统自带 | Ubuntu 包管理器 |
| git | `git` | 安装 | 安装 | 版本控制 |
| GitHub CLI | `gh` | 安装 | 安装 | GitHub 命令行工具 |
| ripgrep | `rg` | 安装 | 安装 | 极快的递归文本搜索 |
| fd | `fd` | 安装 | 安装 `fd-find` 并补 `fd` shim | 极快的文件查找 |
| bat | `bat` | 安装 | 安装 `bat` 并补 `bat` shim | 带语法高亮的 `cat` |
| fzf | `fzf` | 安装 | 安装 | 模糊查找器 |
| jq | `jq` | 安装 | 安装 | JSON 处理 |
| 7-Zip / p7zip | `7z` | 安装 | 安装 | 压缩/解压 |
| eza | `eza` | 安装 | apt 安装；必要时用上游二进制兜底 | 现代 `ls` / `tree` |
| vim | `vim` | 安装 | 安装 | 文本编辑器 |
| zoxide | `z` | 安装 | 安装 | 智能 `cd` |
| Node.js LTS | `node` / `npm` / `npx` | 安装或复用已有 24.x+ | 安装或复用已有 24.x+ | JavaScript/Node 开发运行时 |
| Codex CLI | `codex` | 官网脚本安装，npm 兜底 | 官网脚本安装，npm 兜底 | OpenAI Codex 命令行编码助手 |
| Claude Code CLI | `claude` | 官网脚本安装，npm 兜底 | 官网脚本安装，npm 兜底 | Anthropic Claude Code 命令行编码助手 |
| build-essential | `gcc` / `make` | 不需要 | 安装 | Ubuntu 常用 native build 工具 |
| PSFzf | PowerShell 模块 | 安装 | 不需要 | PowerShell 的 fzf/PSReadLine 集成 |
| PowerShell 7 | `pwsh` | **需预先安装** | 不安装 | Windows SSH 默认 shell 使用 |
| OpenSSH Server | `sshd` | 可配置 | 可配置 | 仅监听 58888，禁用密码登录 |

> 字体（Nerd Font）不在服务器上安装。图标由**客户端终端**渲染，客户端字体配置见[备注](#备注)。

## 快速安装

### Windows

在普通（非管理员）PowerShell 窗口运行：

```powershell
iwr -useb https://raw.githubusercontent.com/sunsheng/windows-cli-setup/main/install.ps1 | iex
```

或克隆仓库后本地执行：

```powershell
git clone https://github.com/sunsheng/windows-cli-setup.git
cd windows-cli-setup
.\install.ps1
```

常用开关：

```powershell
.\install.ps1 -NoProfile   # 只装工具，不安装 PowerShell profile / _vimrc
.\install.ps1 -NoSsh       # 不配置 OpenSSH Server
```

OpenSSH Server 步骤需要管理员权限；普通会话会自动跳过 SSH 配置，其余步骤照常执行。

### Ubuntu Server

在 bash 中运行：

```bash
curl -fsSL https://raw.githubusercontent.com/sunsheng/windows-cli-setup/main/install-ubuntu.sh | bash
```

或克隆仓库后本地执行：

```bash
git clone https://github.com/sunsheng/windows-cli-setup.git
cd windows-cli-setup
bash ./install-ubuntu.sh
```

常用开关：

```bash
bash ./install-ubuntu.sh --no-profile   # 只装工具，不安装 bash/vim 配置
bash ./install-ubuntu.sh --no-ssh       # 不安装/配置 OpenSSH Server
NODE_MAJOR=22 bash ./install-ubuntu.sh  # 如需固定到 Node.js 22.x
```

Ubuntu 脚本会使用 `sudo` 安装系统包。默认 Node.js 目标为 24.x LTS；如果系统已有 `node` + `npm` + `npx` 且主版本不低于 24，会直接复用。

## 脚本行为

### Windows 安装内容

1. 安装 Scoop（若未安装）
2. 安装 git（Scoop 添加 bucket 需要）
3. 添加 `extras` bucket
4. 安装常用 CLI 工具
5. 确保 Node.js LTS、`npm`、`npx` 可用
6. 安装 Codex CLI 与 Claude Code CLI：优先使用官网安装脚本，失败后使用 npm 包兜底
7. 安装 `PSFzf` 模块
8. 复制 `config/Microsoft.PowerShell_profile.ps1` 到 `$PROFILE`，已有文件自动备份为 `*.bak-<时间戳>`
9. 复制 `config/_vimrc` 到 `$HOME\_vimrc`，并创建 `vimfiles\undo`
10. 管理员会话下配置 OpenSSH Server：启用 `sshd`、仅监听 `58888`、禁用密码登录（仅密钥）、限制登录组、放行防火墙、把 SSH 默认 shell 设为 `pwsh`

### Ubuntu Server 安装内容

1. 启用 Ubuntu `universe` 源并安装 apt 依赖
2. 安装常用 CLI 工具、`build-essential`、`unzip`
3. 确保 Node.js 24.x LTS、`npm`、`npx` 可用
4. 安装 Codex CLI 与 Claude Code CLI：优先使用官网安装脚本，失败后使用 npm 包兜底
5. 为 Debian/Ubuntu 的 `fdfind` / `batcat` 创建用户级 `fd` / `bat` shim
6. 安装 `config/bashrc` 到 `~/.bashrc.d/cli-setup.bash`，并在 `~/.bashrc` 追加幂等 source 块
7. 安装 `config/vimrc` 到 `~/.vimrc`，并创建 `~/.vim/undo`
8. 默认安装并配置 OpenSSH Server：仅监听 `58888`、禁用密码登录（仅密钥，并中和 cloud-init 的 `PasswordAuthentication yes`），创建 `ssh-users` 组，把当前用户加入该组，写入 `/etc/ssh/sshd_config.d/99-cli-setup.conf`
9. 如果系统已有 `ufw`，为 `58888/tcp` 添加 allow 规则；不会主动安装或启用 `ufw`

## 使用说明

### 列表与树形（eza）

```bash
ls                 # 简洁列表（目录优先，带图标）
ll                 # 详细列表，含隐藏文件 + git 状态
la                 # 显示所有文件
lt                 # 树形，限 2 层
tree               # 完整树形
```

Windows PowerShell 与 Ubuntu bash 都提供同名快捷方式。

### 查看文件（bat）

```bash
cat <file>         # 语法高亮显示
bat -A <file>      # 显示不可见字符
```

### 搜索（ripgrep / fd）

```bash
rg "pattern"             # 在当前目录递归搜索文本
rg -i "pattern" -t py    # 忽略大小写，仅 Python 文件
fd "name"                # 按文件名模糊查找
fd -e log                # 查找所有 .log 文件
```

### 智能跳转（zoxide）

```bash
z project     # 跳到任意匹配 project 的常用目录
z -           # 回到上一个目录
zi            # 交互式选择历史目录（配合 fzf）
```

### 模糊快捷键（fzf）

| 快捷键 | Windows PowerShell | Ubuntu bash |
|--------|--------------------|-------------|
| Ctrl+R | 模糊搜索命令历史 | 模糊搜索命令历史 |
| Ctrl+T | 模糊查找当前目录文件 | 模糊查找当前目录文件 |
| Ctrl+D | 空命令行退出 shell | bash 默认 EOF 行为 |

Ubuntu 侧会在交互式 bash 中 source fzf 的 `key-bindings.bash` 与 `completion.bash`，为 Ctrl+R / Ctrl+T 提供和 Windows PowerShell 侧相同的模糊历史/文件选择体验。

### JSON / 压缩 / Node.js

```bash
something | jq '.key'
7z x archive.zip
node --version
npm --version
npx --version
codex --version
claude --version
```

### Git 别名（oh-my-zsh 风格，仅查看类）

这些是 shell 级快捷方式，不修改 `~/.gitconfig`：

| 别名 | 等价命令 | 说明 |
|------|----------|------|
| `gst` | `git status` | 工作区状态 |
| `gss` | `git status -s` | 精简状态 |
| `gd` | `git diff` | 查看未暂存改动 |
| `gdca` | `git diff --cached` | 查看已暂存改动 |
| `glog` | `git log --oneline --decorate --graph` | 紧凑提交图 |
| `glola` | `git log --graph --oneline --decorate --all` | 所有分支的紧凑提交图 |
| `gsh` | `git show` | 查看某次提交 |

## SSH 远程登录

### Windows

管理员 PowerShell 运行脚本时会启用 `sshd` 服务、仅监听 `58888`、禁用密码登录（仅密钥，公钥放在 `%ProgramData%\ssh\administrators_authorized_keys`）、限制登录组为 `administrators` / `openssh users`、放行防火墙，并把 SSH 默认 shell 设为 `pwsh`。

```powershell
ssh -p 58888 <用户名>@<主机>
Get-Service sshd
```

### Ubuntu Server

默认会安装并启用 OpenSSH Server，写入：

```text
/etc/ssh/sshd_config.d/99-cli-setup.conf
```

内容包含：

```text
Port 58888
AllowGroups sudo ssh-users
PasswordAuthentication no
```

脚本会创建 `ssh-users` 组，并把运行脚本的目标用户加入该组。已有其他非 `sudo` 用户如需 SSH 登录，需要手动加入：

```bash
sudo usermod -aG ssh-users <user>
sudo systemctl restart ssh
```

## 仓库结构

```text
windows-cli-setup/
├── install.ps1                              # Windows 一键安装脚本
├── install-ubuntu.sh                        # Ubuntu Server 一键安装脚本
├── config/
│   ├── Microsoft.PowerShell_profile.ps1     # PowerShell 配置
│   ├── _vimrc                               # Windows Vim 配置
│   ├── bashrc                               # Ubuntu bash 配置
│   └── vimrc                                # Ubuntu Vim 配置
├── .github/workflows/ci.yml                 # CI：Windows + Ubuntu lint/install 验证
└── README.md
```

## 维护

Windows：

```powershell
scoop update *
scoop list
scoop install <name>
scoop uninstall <name>
```

Ubuntu Server：

```bash
sudo apt update
sudo apt upgrade
apt list --installed
sudo apt install <name>
sudo apt remove <name>
```

## 备注

- **图标 / Nerd Font 装在客户端，不装在服务器**：`eza --icons` 需要客户端终端使用 Nerd Font。Windows Terminal 或 VS Code 集成终端中选择 FiraCode Nerd Font、JetBrainsMono Nerd Font 等即可。
- **Ubuntu 不安装 `pwsh`**：Ubuntu Server 默认使用 bash；`pwsh` 只用于 Windows OpenSSH 的默认 shell。
- **Node.js**：默认按 Node.js 24.x LTS 处理。Windows 使用 Scoop `nodejs-lts`；Ubuntu 使用 NodeSource apt 仓库。已有足够新的 `node` / `npm` / `npx` 会被复用。
- **Codex CLI / Claude Code CLI**：安装器优先使用官方脚本。Codex 使用 `https://chatgpt.com/codex/install.*`，Claude Code 使用 `https://claude.ai/install.*`；如果官网脚本不可用，会退回到 `npm install -g @openai/codex` 与 `npm install -g @anthropic-ai/claude-code`。
- **SSH 分组限制**：Ubuntu 侧会写入 `AllowGroups sudo ssh-users`。这和 Windows 侧限制管理员/openssh 用户组的思路一致，但会影响已有非 sudo 用户的 SSH 登录，需要把他们加入 `ssh-users`。

## 持续集成（CI）

仓库带有 GitHub Actions 工作流 `.github/workflows/ci.yml`：

1. Windows lint：解析 `install.ps1` 与 PowerShell profile，并运行 PSScriptAnalyzer。
2. Ubuntu lint：`bash -n` 检查 bash 脚本与配置，并运行 ShellCheck。
3. Windows install：在 `windows-latest` 上执行 `.\install.ps1 -NoSsh`，验证 CLI、Node.js、Codex CLI、Claude Code CLI、profile 和 git 快捷方式。
4. Ubuntu install：在 `ubuntu-latest` 上执行 `bash ./install-ubuntu.sh --no-ssh`，验证 CLI、Node.js、Codex CLI、Claude Code CLI、bash 配置、fzf Ctrl+R/Ctrl+T 绑定和 git 快捷方式。

## License

MIT

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
| Claude Code CLI | `claude` | 原生二进制优先，脚本/npm 兜底 | 原生二进制优先，脚本/npm 兜底 | Anthropic Claude Code 命令行编码助手 |
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

`claude --dangerously-skip-permissions` **拒绝以 root/sudo 身份运行**。`install-ubuntu.sh` 据此自适应：

- **以 root 运行**（很多云主机默认）：它**自动创建一个带免密 sudo 的普通用户**（默认 `dev`），再以该用户身份把整套环境（CLI 工具 + `claude` / `codex` + bash/vim 配置）装到其名下。
- **以普通 sudo 用户运行**：直接装到当前用户名下。

所以一条命令即可，不用区分身份：

```bash
curl -fsSL https://raw.githubusercontent.com/sunsheng/windows-cli-setup/main/install-ubuntu.sh | bash
```

或克隆仓库后本地执行：

```bash
git clone https://github.com/sunsheng/windows-cli-setup.git
cd windows-cli-setup
bash ./install-ubuntu.sh
```

root 自动建用户后，切过去即可使用：

```bash
sudo -iu dev
claude --dangerously-skip-permissions
```

常用开关与环境变量：

```bash
bash ./install-ubuntu.sh --no-profile    # 只装工具，不安装 bash/vim 配置
bash ./install-ubuntu.sh --no-ssh        # 不安装/配置 OpenSSH Server
CLI_USER=alice bash ./install-ubuntu.sh  # 以 root 运行时，指定自动创建的用户名（默认 dev）
NODE_MAJOR=22 bash ./install-ubuntu.sh   # 如需固定到 Node.js 22.x
```

关于 root 自动建用户的几点：

1. 用 `adduser --disabled-password` 创建用户（不存在才创建，默认禁用密码登录），加入 `sudo` 组。
2. 写入 `/etc/sudoers.d/90-<user>-nopasswd`（`NOPASSWD:ALL`，`0440`），落盘前后都用 `visudo` 校验，避免写坏锁死 sudo。
3. 以新用户身份重跑安装器，**此路径强制 `--no-ssh`**：脚本通常跑在远程 root 会话里，自动把 sshd 切到 58888、禁用密码登录有把自己锁在门外的风险。需要 SSH 加固时，切到该用户后**单独再跑一次** `bash ./install-ubuntu.sh`（以普通用户身份运行就会配置 SSH）。
4. 如需给新用户设密码，自行 `sudo passwd <user>`。

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

0. 生成 UTF-8 locale（消除 SSH `setlocale: cannot change locale` 警告）：安装 `locales`，确保生成 `en_US.UTF-8` 与 `zh_CN.UTF-8`，并把**本次 SSH 会话转发进来的任意 UTF-8 locale**（如客户端发来的 `LC_ALL=zh_CN.UTF-8`）一并生成；系统无默认 locale 时设 `LANG=en_US.UTF-8`（不覆盖已有值）
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
├── install-ubuntu.sh                        # Ubuntu Server 一键安装脚本（root 下自动建用户）
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

## macOS 客户端字体配置

如果你从 **macOS** 通过终端 SSH 登录上面配置好的服务器，图标（`eza --icons`、Vim/Codex/Claude 的图形符号等）由**本地终端**渲染，需要在 macOS 客户端装一款 Nerd Font。下面给出**不使用 Homebrew** 的手动安装方式。

### 1. 下载并安装 Nerd Font（无需 brew）

从 [Nerd Fonts 官方 Release](https://github.com/ryanoasis/nerd-fonts/releases/latest) 下载字体压缩包并复制到用户字体目录 `~/Library/Fonts`（仅当前用户，不需要管理员权限）：

```bash
cd ~/Downloads
# 以 JetBrainsMono 为例，可替换为 FiraCode、Hack、Meslo 等
curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
unzip -o JetBrainsMono.zip -d JetBrainsMono
mkdir -p ~/Library/Fonts
cp JetBrainsMono/*.ttf ~/Library/Fonts/
```

或图形化方式：下载并解压后，双击任意 `.ttf` 文件，在弹出的「字体册（Font Book）」中点击「安装字体」即可。

安装后可验证：

```bash
ls ~/Library/Fonts | grep -i nerd
```

### 2. 在客户端终端中选用该字体

- **Terminal.app（系统自带）**：菜单「终端 → 设置 → 描述文件 → 文本 → 字体」，点「更改…」选择 `JetBrainsMono Nerd Font`。
- **iTerm2**：「Settings → Profiles → Text → Font」，选择 `JetBrainsMono Nerd Font`（推荐勾选 "Use a different font for non-ASCII text" 时也设为同一 Nerd Font）。
- **VS Code 集成终端**：在 `settings.json` 中加入：

  ```json
  {
    "terminal.integrated.fontFamily": "JetBrainsMono Nerd Font"
  }
  ```

> 字体名以「`<字体> Nerd Font`」形式出现（如 `FiraCode Nerd Font`、`Hack Nerd Font`）；如需等宽对齐更稳妥，也可选用名称带 `Mono` 的变体（如 `JetBrainsMono Nerd Font Mono`）。

## 备注

- **图标 / Nerd Font 装在客户端，不装在服务器**：`eza --icons` 需要客户端终端使用 Nerd Font。Windows Terminal 或 VS Code 集成终端中选择 FiraCode Nerd Font、JetBrainsMono Nerd Font 等即可。macOS 客户端字体配置见下方[macOS 客户端字体配置](#macos-客户端字体配置)。
- **Ubuntu 不安装 `pwsh`**：Ubuntu Server 默认使用 bash；`pwsh` 只用于 Windows OpenSSH 的默认 shell。
- **Node.js**：默认按 Node.js 24.x LTS 处理。Windows 使用 Scoop `nodejs-lts`；Ubuntu 使用 NodeSource apt 仓库。已有足够新的 `node` / `npm` / `npx` 会被复用。
- **Codex CLI**：安装器优先使用官方脚本 `https://chatgpt.com/codex/install.*`，不可用时退回到 `npm install -g @openai/codex`。
- **Claude Code CLI**：采用三级兜底。① 优先**直接从 `https://downloads.claude.ai/claude-code-releases` 拉原生二进制**（取 `latest` 版本号 → 下载对应平台二进制 → 用 `manifest.json` 里的 SHA256 校验 → 运行内置 `claude install`）；② 失败时退回官方入口脚本 `https://claude.ai/install.*`；③ 再失败才用 `npm install -g @anthropic-ai/claude-code`。之所以原生优先，是因为入口脚本 `claude.ai/install.*` 挂在 Cloudflare 托管质询（managed challenge）后面，**数据中心/云主机 IP（如阿里云、各云厂商）裸 `curl` 会被 403 挡住**，而 `downloads.claude.ai` 没有这层质询，能直接下载。原生安装的另一个好处是会**后台自动更新**。
- **UTF-8 locale**：`setlocale: cannot change locale (zh_CN.UTF-8)` 这类警告，是 SSH **客户端把本地 `LC_*` 环境变量转发到了服务器**，而服务器没生成对应 locale 导致的。Ubuntu 脚本会在服务器上生成 `en_US.UTF-8`、`zh_CN.UTF-8` 以及本次会话转发进来的 UTF-8 locale，从根上消除警告（也可在客户端 `~/.ssh/config` 里去掉 `SendEnv LANG LC_*` 不转发，但那只是绕过）。
- **SSH 分组限制**：Ubuntu 侧会写入 `AllowGroups sudo ssh-users`。这和 Windows 侧限制管理员/openssh 用户组的思路一致，但会影响已有非 sudo 用户的 SSH 登录，需要把他们加入 `ssh-users`。

## 持续集成（CI）

仓库带有 GitHub Actions 工作流 `.github/workflows/ci.yml`：

1. Windows lint：解析 `install.ps1` 与 PowerShell profile，并运行 PSScriptAnalyzer。
2. Ubuntu lint：`bash -n` 检查 `install-ubuntu.sh` 与配置，并运行 ShellCheck。
2.5. Ubuntu root bootstrap：以 root 执行 `install-ubuntu.sh`，校验自动创建的用户、`sudo` 组、免密 sudo（`sudo -n`），以及 `claude` / `codex` 已装到新用户名下。
3. Windows install：在 `windows-latest` 上执行 `.\install.ps1 -NoSsh`，验证 CLI、Node.js、Codex CLI、Claude Code CLI、profile 和 git 快捷方式。
4. Ubuntu install：在 `ubuntu-latest` 上执行 `bash ./install-ubuntu.sh --no-ssh`，验证 CLI、Node.js、Codex CLI、Claude Code CLI、bash 配置、fzf Ctrl+R/Ctrl+T 绑定和 git 快捷方式。

## License

MIT

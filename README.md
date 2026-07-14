# cli-workbench-setup

一套可重复执行的命令行环境安装脚本，用于在 **Windows / Windows Server** 和 **Ubuntu Server** 上快速准备一致的现代 CLI 工作台。

它会安装常用工具、AI 编码 CLI、shell 配置、Vim 配置，并可选加固 OpenSSH Server：

- Windows：使用 [Scoop](https://scoop.sh) 安装工具，配置 PowerShell 7、PSFzf、zoxide、Vim 和 OpenSSH Server。
- Ubuntu Server：使用 apt 安装工具，以 root 一次执行，自动创建普通用户，把默认 shell 切到 zsh，并把环境安装到该用户下。
- 两端保持相同的日常命令体验：`ls`/`l`/`ll`/`tree`、`cat`、`rg`、`fd`、`z`、`fzf` 快捷键、git 查看类别名等。

> Windows 路径在 Windows Server 2025 / PowerShell 7 上验证；Ubuntu 路径面向 Ubuntu Server 24.04 LTS 及更新版本，并在 GitHub Actions 的 `ubuntu-latest` 上测试。

## 目录

- [快速开始](#快速开始)
- [安装内容](#安装内容)
- [Ubuntu 用户模型](#ubuntu-用户模型)
- [SSH 配置](#ssh-配置)
- [常用命令](#常用命令)
- [仓库结构](#仓库结构)
- [维护与验证](#维护与验证)
- [备注](#备注)
- [macOS 客户端字体配置](#macos-客户端字体配置)

## 快速开始

### Ubuntu Server

`install-ubuntu.sh` 必须以 root 运行。脚本会在同一次执行中创建普通用户（默认 `dev`），把 CLI 工具、`claude` / `codex`、zsh/bash/Vim 配置安装到这个用户下，同时把该用户默认 shell 设为 zsh；随脚本附带的公钥 `id_ed25519.pub` 会自动写入该用户的 `~/.ssh/authorized_keys`；脚本最后还会为该用户安装 Claude Code 的 `andrej-karpathy-skills` 插件（用户级）。

以 root 身份执行：

```bash
curl -fsSL https://raw.githubusercontent.com/sunsheng/cli-workbench-setup/main/install-ubuntu.sh | bash
```

或克隆仓库后执行：

```bash
git clone https://github.com/sunsheng/cli-workbench-setup.git
cd cli-workbench-setup
bash ./install-ubuntu.sh
```

安装后切换到目标用户：

```bash
sudo -iu dev
claude   # 已 alias 为 claude --dangerously-skip-permissions
codex    # 已 alias 为 codex --yolo
```

常用开关和环境变量：

```bash
bash ./install-ubuntu.sh --no-profile          # 只安装工具，不写入 shell/vim 配置，也不改默认 shell
bash ./install-ubuntu.sh --no-ssh              # 跳过 OpenSSH Server 配置
CLI_USER=alice bash ./install-ubuntu.sh        # 指定自动创建的普通用户，默认 dev
CLI_PASSWORD=secret bash ./install-ubuntu.sh   # 指定登录密码（控制台与 SSH 通用）
NODE_MAJOR=22 bash ./install-ubuntu.sh         # 指定 Node.js 主版本，默认 24
GIT_USER_NAME="Your Name" GIT_USER_EMAIL=you@example.com bash ./install-ubuntu.sh   # 指定 git 身份
```

如果未指定 `CLI_PASSWORD`，脚本会生成随机密码（8–10 位，大小写字母与数字，无特殊字符及易混淆字符 `0 1 O o I l i`）。该密码会在执行末尾打印一次，并保存到目标用户家目录下的 `~/.cli-setup-password`（权限 `0600`，属主为该用户），方便日后查看；建议用 `passwd` 修改。

> 脚本会为目标用户配置 git 身份（`~/.gitconfig` 的 `user.name` / `user.email`），默认 `sunsheng` / `sunsheng4214@gmail.com`，可用 `GIT_USER_NAME` / `GIT_USER_EMAIL` 覆盖。该步骤幂等：若已是目标值则跳过，否则写入。此处只配置身份，git 查看类快捷方式（`gst`、`gd` 等）仍是 shell 函数/别名，不写入 `~/.gitconfig`。

> 仓库根目录下的 `id_ed25519.pub` 是随脚本一起分发的管理公钥，会被自动追加到目标用户的 `authorized_keys`（已存在则跳过，不会重复添加）。如果不想让这把公钥获得访问权限，替换仓库中的 `id_ed25519.pub` 为你自己的公钥后再运行脚本。

### Windows

在普通 PowerShell 窗口运行：

```powershell
iwr -useb https://raw.githubusercontent.com/sunsheng/cli-workbench-setup/main/install-windows.ps1 | iex
```

或克隆仓库后执行：

```powershell
git clone https://github.com/sunsheng/cli-workbench-setup.git
cd cli-workbench-setup
.\install-windows.ps1
```

常用开关：

```powershell
.\install-windows.ps1 -NoProfile   # 只安装工具，不写入 PowerShell profile / Vim 配置
.\install-windows.ps1 -NoSsh       # 跳过 OpenSSH Server 配置
```

添加管理员 SSH 公钥：

```powershell
# 管理员 PowerShell 中执行；默认寻找 $HOME\.ssh\id_ed25519.pub / id_rsa.pub / id_ecdsa.pub
.\add-windows-admin-ssh-key.ps1

# 或指定公钥文件
.\add-windows-admin-ssh-key.ps1 -PublicKeyPath $HOME\.ssh\id_ed25519.pub

# 或直接传入公钥内容
.\add-windows-admin-ssh-key.ps1 -PublicKey 'ssh-ed25519 AAAA... user@host'
```

说明：

- 普通用户会话可以完成工具和配置安装。
- OpenSSH Server 配置需要管理员权限；非管理员会话会自动跳过 SSH 步骤。
- 安装完成后，打开新的 PowerShell 7 窗口，或运行 `. $PROFILE` 载入新配置。

## 安装内容

| 类别 | Windows | Ubuntu Server |
|------|---------|---------------|
| 包管理器 | Scoop | apt |
| Shell | PowerShell 7 (`pwsh`) | zsh（默认登录 shell），并保留 bash 配置 |
| 基础工具 | `git`, `gh`, `jq`, `7z` | `git`, `gh`, `jq`, `7z`, `unzip` |
| 搜索/浏览 | `rg`, `fd`, `bat`, `fzf`, `eza` | `rg`, `fd`, `bat`, `fzf`, `eza` |
| 编辑/跳转 | `vim`, `zoxide` | `vim`, `zoxide` |
| Node.js | Node.js LTS，默认目标 24.x | Node.js LTS，默认目标 24.x |
| AI CLI | `codex`, `claude` | `codex`, `claude` |
| Shell 配置 | PowerShell profile、PSFzf 快捷键、git 查看类函数 | `~/.zprofile`、`~/.zshrc`、`~/.bashrc.d/cli-setup.bash`、fzf 快捷键、git 查看类 alias、`codex`/`claude` 免确认 alias |
| Vim 配置 | `~/_vimrc`、持久 undo 目录 | `~/.vimrc`、持久 undo 目录 |
| SSH | 可配置 OpenSSH Server | 默认配置 OpenSSH Server，除非 `--no-ssh`；自动写入用户公钥 |
| Claude Code 插件 | — | `andrej-karpathy-skills`（用户级） |

脚本均设计为幂等执行：已存在的工具和配置会尽量复用或跳过；覆盖用户配置前会备份到带时间戳的 `.bak-*` 文件。

`add-windows-admin-ssh-key.ps1` 也是幂等的：同一把公钥已存在时不会重复追加，并会修正 `administrators_authorized_keys` 的 ACL。

### AI CLI 安装策略

`codex` 和 `claude` 都优先走官方安装方式，失败后使用 npm 兜底：

- Codex CLI：优先 `https://chatgpt.com/codex/install.*`，失败后 `npm install -g @openai/codex`。
- Claude Code CLI：优先从 `https://downloads.claude.ai/claude-code-releases` 下载原生二进制并校验 SHA256，再尝试 `https://claude.ai/install.*`，最后使用 `npm install -g @anthropic-ai/claude-code`。

Claude Code 原生二进制优先，是因为 `claude.ai/install.*` 在部分云主机或数据中心 IP 上可能被 Cloudflare 托管质询拦截，而 `downloads.claude.ai` 可直接下载。

## Ubuntu 用户模型

Ubuntu 安装器必须以 root 运行，但最终环境不会装到 root 下。它会创建或复用 `CLI_USER` 指定的普通用户（默认 `dev`），并执行这些操作：

1. 创建用户并加入 `sudo` 组。
2. 写入 `/etc/sudoers.d/90-<user>-nopasswd`，给该用户免密 sudo；写入前后都用 `visudo` 校验。
3. 设置登录密码（控制台与 SSH 通用），并保存到 `~/.cli-setup-password`（`0600`）。只在账户当前没有密码时设置，重复运行不会覆盖你改过的密码。
4. 创建 `~/.ssh` 和 `~/.ssh/authorized_keys`（权限分别为 `0700` 和 `0600`），并把仓库自带的 `id_ed25519.pub` 追加进去。该 key 已存在时会跳过，不会重复添加。
5. 以该普通用户身份安装用户级工具和配置，包括 `claude`、`codex`、npm 全局包、zsh/bash 配置、Vim 配置，以及 Claude Code 的 `andrej-karpathy-skills` 插件（用户级）。
6. 将该普通用户的默认登录 shell 设置为 `/usr/bin/zsh`；`claude`/`codex` 在该 shell 里被 alias 为 `claude --dangerously-skip-permissions` / `codex --yolo`。

这个模型是为了避免把 Claude Code 跑在 root 下；`claude --dangerously-skip-permissions` 会拒绝 root/sudo 身份运行。

## SSH 配置

两端共同的 SSH 加固：

- 只监听 `58888`，不保留 22 端口。
- 使用登录组限制可 SSH 登录的用户。
- 禁止 root 直接 SSH 登录。

密码登录策略两端不同：**Windows 仅允许密钥登录**；**Ubuntu 允许密码登录**（同时也支持密钥）。

### Windows

管理员 PowerShell 运行脚本时会：

- 安装并启用 `sshd`。
- 写入全局 sshd 配置，限制登录组为 `administrators` / `openssh users`。
- 禁用密码登录。
- 放行 Windows 防火墙 `58888/tcp`。
- 将 SSH 默认 shell 设为 PowerShell 7 (`pwsh`)。

连接示例：

```powershell
ssh -p 58888 <用户名>@<主机>
Get-Service sshd
```

管理员账户的公钥通常放在：

```text
%ProgramData%\ssh\administrators_authorized_keys
```

可以用仓库里的脚本自动追加公钥并修正权限：

```powershell
.\add-windows-admin-ssh-key.ps1 -PublicKeyPath $HOME\.ssh\id_ed25519.pub
```

### Ubuntu Server

默认会安装并配置 OpenSSH Server，写入：

```text
/etc/ssh/sshd_config.d/99-cli-setup.conf
```

核心配置：

```text
Port 58888
AllowGroups sudo ssh-users
PermitRootLogin no
PasswordAuthentication yes
```

脚本还会注释掉早先 drop-in（如 cloud-init 的 `50-*.conf`）里冲突的 `PasswordAuthentication` / `PermitRootLogin`，确保以上设置生效（sshd 取首个匹配，`50-` 排在 `99-` 前）。

脚本会创建 `ssh-users` 组，并把目标用户加入该组。已有非 `sudo` 用户如需 SSH 登录，需要手动加入：

```bash
sudo usermod -aG ssh-users <user>
sudo systemctl restart ssh
```

脚本会自动把仓库自带的 `id_ed25519.pub` 写入目标用户的 `~/.ssh/authorized_keys`，装好后即可用对应私钥直接连接，无需再手动拷贝公钥：

```bash
ssh -p 58888 dev@<主机>
```

## 常用命令

### 列表与树形

```bash
ls       # 简洁列表，目录优先，带图标
l        # 简洁列表短命令
ll       # 详细列表，包含隐藏文件和 git 状态
la       # 显示所有文件
lt       # 树形视图，默认 2 层
tree     # 完整树形视图
```

### 查看文件

```bash
cat <file>       # 使用 bat 高亮显示
bat -A <file>    # 显示不可见字符
```

### 搜索

```bash
rg "pattern"             # 递归搜索文本
rg -i "pattern" -t py    # 忽略大小写，仅搜索 Python 文件
fd "name"                # 按文件名查找
fd -e log                # 查找 .log 文件
```

### 智能跳转

```bash
z project     # 跳到常用目录中匹配 project 的路径
z -           # 回到上一个目录
zi            # 交互式选择历史目录
```

### fzf 快捷键

| 快捷键 | Windows PowerShell 7 | Ubuntu zsh |
|--------|----------------------|-------------|
| Ctrl+R | 模糊搜索历史命令 | 模糊搜索历史命令 |
| Ctrl+T | 模糊查找当前目录文件 | 模糊查找当前目录文件 |
| Ctrl+D | 删除光标处字符，空命令行时退出 shell | zsh 默认 EOF 行为：删除光标处字符，空命令行时退出 shell |

### Git 查看类快捷方式

这些是 shell 级别的函数或 alias，不会修改 `~/.gitconfig`（Ubuntu 安装脚本另外会向 `~/.gitconfig` 写入 git 身份 `user.name` / `user.email`，见「Ubuntu」安装说明）：

| 别名 | 等价命令 | 说明 |
|------|----------|------|
| `gst` | `git status` | 工作区状态 |
| `gss` | `git status -s` | 精简状态 |
| `gd` | `git diff` | 未暂存改动 |
| `gdca` | `git diff --cached` | 已暂存改动 |
| `glog` | `git log --oneline --decorate --graph` | 当前分支提交图 |
| `glola` | `git log --graph --oneline --decorate --all` | 所有分支提交图 |
| `gsh` | `git show` | 查看提交或对象 |

### AI CLI 免确认 alias（仅 Ubuntu）

Ubuntu 侧的 zsh/bash 配置额外把 `codex` / `claude` alias 成带免确认参数的调用，普通用户下直接执行即会跳过每次的权限确认：

| 别名 | 等价命令 |
|------|----------|
| `codex` | `codex --yolo` |
| `claude` | `claude --dangerously-skip-permissions` |

如果不想默认跳过确认，删除或注释掉 `~/.zshrc` / `~/.bashrc.d/cli-setup.bash` 里的这两行 alias 即可。

### 其他工具

```bash
something | jq '.key'
7z x archive.zip
node --version
npm --version
npx --version
codex --version
claude --version
```

## 仓库结构

```text
cli-workbench-setup/
├── install-windows.ps1                      # Windows 一键安装脚本
├── add-windows-admin-ssh-key.ps1            # Windows 管理员 SSH 公钥追加脚本
├── install-ubuntu.sh                        # Ubuntu Server 一键安装脚本
├── id_ed25519.pub                           # 随脚本分发的管理公钥，自动写入用户 authorized_keys
├── profiles/
│   ├── powershell-profile.ps1               # PowerShell 7 配置
│   ├── windows-vimrc                        # Windows Vim 配置
│   ├── ubuntu-bashrc                        # Ubuntu bash 配置
│   ├── ubuntu-zprofile                      # Ubuntu zsh 登录配置
│   ├── ubuntu-zshrc                         # Ubuntu zsh 交互配置
│   └── ubuntu-vimrc                         # Ubuntu Vim 配置
├── .github/workflows/ci.yml                 # CI：lint + 安装验证
├── CLAUDE.md                                # 给 Claude Code 的维护说明
├── LICENSE
└── README.md
```

## 维护与验证

### 更新已安装工具

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

### 本地检查

Bash/zsh：

```bash
bash -n install-ubuntu.sh profiles/ubuntu-bashrc
zsh -n profiles/ubuntu-zprofile
zsh -n profiles/ubuntu-zshrc
shellcheck -s bash install-ubuntu.sh profiles/ubuntu-bashrc
```

PowerShell：

```powershell
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path install-windows.ps1), [ref]$null, [ref]([ref]$null).Value)
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path add-windows-admin-ssh-key.ps1), [ref]$null, [ref]([ref]$null).Value)
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path profiles/powershell-profile.ps1), [ref]$null, [ref]([ref]$null).Value)
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error
```

### CI

GitHub Actions 会执行：

1. Windows lint：解析 `install-windows.ps1`、`add-windows-admin-ssh-key.ps1` 和 PowerShell profile，并运行 PSScriptAnalyzer。
2. Ubuntu lint：对 `install-ubuntu.sh` 和配置运行 `bash -n`、`zsh -n` 和 ShellCheck。
3. Windows install：在 `windows-latest` 上执行 `.\install-windows.ps1 -NoSsh`，验证工具、Node.js、AI CLI 在 PATH 上且 `--version` 可执行，并验证 profile 和 git 快捷方式。
4. Ubuntu install：在 `ubuntu-latest` 上从 `/root` 以 root 执行 `install-ubuntu.sh --no-ssh`，验证自动建用户、sudo、密码、SSH 文件权限、CLI、Node.js、AI CLI 在 PATH 上且 `--version` 可执行、默认 zsh、shell 配置、fzf 绑定、git 身份（`user.name` / `user.email`）和 git 快捷方式。

## 备注

- Nerd Font 装在客户端，不装在服务器。`eza --icons`、Vim、Codex、Claude 中的图标由本地终端渲染。
- Windows Terminal、VS Code 集成终端、iTerm2、Terminal.app 等客户端都需要选择 Nerd Font，例如 `JetBrainsMono Nerd Font`、`FiraCode Nerd Font` 或 `Hack Nerd Font`。
- Ubuntu 不安装 `pwsh`；PowerShell 7 只用于 Windows 侧，尤其是 Windows OpenSSH 默认 shell。
- Ubuntu 会生成 `en_US.UTF-8` 并设为系统默认，避免裸机停留在 C/POSIX 而导致 `setlocale: cannot change locale` 警告。
- Ubuntu 的 `fd` / `bat` 在 Debian 包中可能叫 `fdfind` / `batcat`；脚本会创建用户级 `fd` / `bat` shim。

## macOS 客户端字体配置

如果从 macOS SSH 到服务器，并希望图标正常显示，可以手动安装 Nerd Font。

下载并安装 JetBrainsMono Nerd Font：

```bash
cd ~/Downloads
curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
unzip -o JetBrainsMono.zip -d JetBrainsMono
mkdir -p ~/Library/Fonts
cp JetBrainsMono/*.ttf ~/Library/Fonts/
```

然后在终端中选择该字体：

- Terminal.app：`终端 -> 设置 -> 描述文件 -> 文本 -> 字体`
- iTerm2：`Settings -> Profiles -> Text -> Font`
- VS Code 集成终端：在 `settings.json` 中设置

```json
{
  "terminal.integrated.fontFamily": "JetBrainsMono Nerd Font"
}
```

## License

MIT

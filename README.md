# windows-cli-setup

一套用于快速搭建现代 Windows 命令行环境的脚本与配置：基于 [Scoop](https://scoop.sh) 包管理器安装一组常用 CLI 工具，并配置好 PowerShell 别名、`fzf` 快捷键与 `zoxide` 智能跳转。

> 在 Windows Server 2025 / PowerShell 7 上验证通过。

## 包含的工具

| 工具 | 命令 | 说明 |
|------|------|------|
| [Scoop](https://scoop.sh) | `scoop` | 包管理器 |
| [git](https://git-scm.com) | `git` | 版本控制 |
| [GitHub CLI](https://cli.github.com) | `gh` | GitHub 命令行工具 |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | `rg` | 极快的递归文本搜索 |
| [fd](https://github.com/sharkdp/fd) | `fd` | 极快的文件查找（`find` 替代） |
| [bat](https://github.com/sharkdp/bat) | `bat` | 带语法高亮的 `cat` |
| [fzf](https://github.com/junegunn/fzf) | `fzf` | 模糊查找器 |
| [jq](https://jqlang.github.io/jq/) | `jq` | JSON 处理 |
| [7-Zip](https://www.7-zip.org) | `7z` | 压缩/解压 |
| [eza](https://github.com/eza-community/eza) | `eza` | 现代 `ls` / `tree` |
| [vim](https://www.vim.org) | `vim` | 文本编辑器 |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | `z` | 智能 `cd` |
| [PSFzf](https://github.com/kelleyma49/PSFzf) | — | fzf 与 PSReadLine 集成（Ctrl+R / Ctrl+T） |
| [PowerShell 7](https://github.com/PowerShell/PowerShell) | `pwsh` | **需预先安装**；脚本只把它设为 SSH 默认 shell，不负责安装 |

> 字体（Nerd Font）不在服务器上安装——图标由**客户端终端**渲染。客户端安装方法见下方[「备注」](#备注)。

## 快速安装

在一个普通（非管理员）PowerShell 窗口运行（Scoop 官方推荐非管理员；若在管理员会话下脚本会自动加 `-RunAsAdmin`）：

```powershell
iwr -useb https://raw.githubusercontent.com/sunsheng/windows-cli-setup/main/install.ps1 | iex
```

或克隆仓库后本地执行：

```powershell
git clone https://github.com/sunsheng/windows-cli-setup.git
cd windows-cli-setup
.\install.ps1
```

脚本会：

1. 安装 Scoop（若未安装；在管理员会话下自动加 `-RunAsAdmin`）
2. 安装 git（Scoop 添加 bucket 需要它，故先装）
3. 添加 `extras` bucket
4. 安装上表中的所有 CLI 工具
5. 安装 `PSFzf` 模块
6. 把 `config/Microsoft.PowerShell_profile.ps1` 复制到你的 `$PROFILE`（已有的会自动备份为 `*.bak-<时间戳>`）——其中包含 oh-my-zsh 风格的 git 查看别名（`gst` / `gd` / `glog` / `gsh` ...）
7. 把 `config/_vimrc` 复制到 `$HOME\_vimrc` 并创建撤销目录 `vimfiles\undo`（已有的会自动备份）
8. **（需管理员）** 安装并配置 OpenSSH Server：启用 `sshd` 服务、监听 `22` + `58888` 端口、限制登录组为 `administrators` / `openssh users`、放行对应防火墙、把 SSH 默认 shell 设为 `pwsh`；非管理员或加 `-NoSsh` 时跳过此步

> 脚本可重复运行——每一步都会先检查是否已安装。
>
> 只想装工具、不动个人配置（profile / `_vimrc`，git 别名也在 profile 里）？加 `-NoProfile`：`.\install.ps1 -NoProfile`
>
> 不想配置 OpenSSH Server？加 `-NoSsh` 跳过那一步：`.\install.ps1 -NoSsh`（两个开关可同时用）。
>
> OpenSSH Server 那一步需要管理员权限——想启用就用**管理员** PowerShell 运行脚本；普通会话会自动跳过它（其余步骤照常）。

安装完成后**新开一个 PowerShell 窗口**（或运行 `. $PROFILE`）即可生效。

## 使用说明

### 列表与树形（eza）

```powershell
ls                 # 简洁列表（目录优先，带图标）
ll                 # 详细列表，含隐藏文件 + git 状态
la                 # 显示所有文件
lt                 # 树形，限 2 层（替代 tree）
tree               # 完整树形
```

> 以上函数已默认带 `--icons`，图标需**客户端终端**使用 Nerd Font 字体才能正常显示（脚本不在服务器装字体）。客户端安装方法见下方[「备注」](#备注)。

### 查看文件（bat）

```powershell
cat <file>         # 语法高亮显示
bat -A <file>      # 显示不可见字符
```

### 搜索（ripgrep / fd）

```powershell
rg "pattern"             # 在当前目录递归搜索文本
rg -i "pattern" -t py    # 忽略大小写，仅 Python 文件
fd "name"                # 按文件名模糊查找
fd -e log                # 查找所有 .log 文件
```

### 智能跳转（zoxide）

zoxide 会记住你 `cd` / `z` 走过的目录，之后只需输入部分名称即可跳转。

```powershell
z scoop      # 跳到任意匹配 "scoop" 的常用目录
z -          # 回到上一个目录
zi           # 交互式选择历史目录（配合 fzf）
```

> 数据库需要"养"——用得越多匹配越准。

### 模糊快捷键（fzf + PSFzf）

> 仅在交互式终端中生效。

| 快捷键 | 作用 |
|--------|------|
| **Ctrl+R** | 模糊搜索命令历史，回车填入命令行 |
| **Ctrl+T** | 模糊查找当前目录文件，选中后插入命令行 |
| **Ctrl+D** | 命令行为空时退出当前 shell（bash 风格 EOF；非空时不触发） |

### JSON / 压缩

```powershell
something | jq '.key'        # 提取 JSON 字段
7z x archive.zip             # 解压
7z a archive.7z folder\      # 压缩
```

### Git 别名（oh-my-zsh 风格，仅查看类）

profile 里定义了一组 oh-my-zsh `git` 插件风格的 **shell** 别名（函数），只覆盖**查看仓库状态**用的命令，不动 `~/.gitconfig`。额外参数会透传（例如 `gd HEAD~1`、`gsh <sha>`）：

| 别名 | 等价命令 | 说明 |
|------|----------|------|
| `gst` | `git status` | 工作区状态 |
| `gss` | `git status -s` | 精简状态 |
| `gd` | `git diff` | 查看**未暂存**改动 |
| `gdca` | `git diff --cached` | 查看**已暂存**改动 |
| `glog` | `git log --oneline --decorate --graph` | 紧凑提交图 |
| `glola` | `git log --graph --oneline --decorate --all` | 所有分支的紧凑提交图 |
| `gsh` | `git show` | 查看某次提交 |

### SSH 远程登录（OpenSSH Server）

用**管理员** PowerShell 运行脚本时会自动：启用 `sshd` 服务并设为开机自启、让 sshd 监听 **22 和 58888** 两个端口、把登录限制在 `administrators` 与 `openssh users` 组、放行两个端口的防火墙、把 SSH 默认 shell 设为 `pwsh`（这样 `ssh <主机>` 进来直接落在 PowerShell 7）。加 `-NoSsh` 可跳过整步。

```powershell
ssh <用户名>@<主机>              # 默认 22 端口，进来即是 pwsh
ssh -p 58888 <用户名>@<主机>     # 走 58888 端口
Get-Service sshd                # 在服务器上查看 sshd 状态
```

> **默认 shell**：写在机器级注册表 `HKLM:\SOFTWARE\OpenSSH\DefaultShell`，并设 `DefaultShellCommandOption = -c`。脚本按 `Program Files → WindowsApps 执行别名 → PATH` 顺序解析 `pwsh`，优先选稳定（不带版本号）的路径——以**运行脚本的那个用户**身份登录 SSH 时有效。
>
> **端口/分组**写入 `C:\ProgramData\ssh\sshd_config`（幂等地插在结尾 `Match` 块之前），改动后会自动 `Restart-Service sshd`。
>
> 图标字形由你敲字的那台**客户端终端**渲染，记得在客户端装并启用 Nerd Font（见下方"备注"）。

## 仓库结构

```
windows-cli-setup/
├── install.ps1                              # 一键安装脚本
├── config/
│   ├── Microsoft.PowerShell_profile.ps1     # PowerShell 配置（别名/快捷键/zoxide）
│   └── _vimrc                               # vim 基础配置（无插件）
├── .github/workflows/ci.yml                 # CI：lint + 在 Windows runner 上跑安装并验证
└── README.md
```

## 维护

```powershell
scoop update *          # 更新所有已安装软件
scoop list              # 查看已安装列表
scoop install <name>    # 安装新软件
scoop search <name>     # 搜索可装软件
scoop uninstall <name>  # 卸载
```

## 备注

- **图标 / Nerd Font（装在客户端，不装在服务器）**：图标已默认开启（profile 中各 eza 函数带 `--icons`），但字形由你**正在敲字的那台客户端终端**渲染，与服务器无关——所以脚本**不**在服务器装字体。要让图标正常显示（否则会看到方框/乱码），在**客户端**装一个 Nerd Font 并选用：
  - 装字体（客户端机器上任选其一）：
    - 客户端也用 Scoop：`scoop bucket add nerd-fonts; scoop install nerd-fonts/FiraCode-NF`
    - 或 winget：`winget install --id DEVCOM.JetBrainsMonoNerdFont`（或到 [nerdfonts.com](https://www.nerdfonts.com/) 直接下载安装）
  - 选用字体：
    - Windows Terminal：`设置 → 配置文件 → 外观 → 字体` 选 “FiraCode Nerd Font”
    - VS Code 集成终端：`"terminal.integrated.fontFamily": "FiraCode Nerd Font"`
  - profile 已强制 UTF-8 输出（`[Console]::OutputEncoding`），避免 SSH 会话以非 UTF-8 codepage 启动时把图标错码成 `?`。
- profile 使用 `function` 而非 `Set-Alias`，以便携带默认参数（如 `--icons`、`--git`、`--tree --level=2`）。
- `pwsh`（PowerShell 7）**需预先安装**——脚本只把它设为 SSH 默认 shell，不负责安装。可用 `winget install Microsoft.PowerShell` 装。

## 持续集成（CI）

仓库带了一个 GitHub Actions 工作流 [`​.github/workflows/ci.yml`](.github/workflows/ci.yml)，在 `push` / `pull_request` / 手动触发时于 **Windows runner** 上：

1. **lint**：解析 `install.ps1` 与 profile、跑 PSScriptAnalyzer（Error 级）；
2. **install**：执行 `.\install.ps1 -NoSsh`，然后校验所有 CLI 工具在 PATH 上、profile 能干净加载（含 git 查看别名 `gst` / `gd` / `glog` ...）。

## License

MIT

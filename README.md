# windows-cli-setup

一套用于快速搭建现代 Windows 命令行环境的脚本与配置：基于 [Scoop](https://scoop.sh) 包管理器安装一组常用 CLI 工具，并配置好 PowerShell 别名、`fzf` 快捷键与 `zoxide` 智能跳转。

> 在 Windows Server 2025 / PowerShell 7 上验证通过。

## 包含的工具

| 工具 | 命令 | 说明 |
|------|------|------|
| [Scoop](https://scoop.sh) | `scoop` | 包管理器 |
| [git](https://git-scm.com) | `git` | 版本控制 |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | `rg` | 极快的递归文本搜索 |
| [fd](https://github.com/sharkdp/fd) | `fd` | 极快的文件查找（`find` 替代） |
| [bat](https://github.com/sharkdp/bat) | `bat` | 带语法高亮的 `cat` |
| [fzf](https://github.com/junegunn/fzf) | `fzf` | 模糊查找器 |
| [jq](https://jqlang.github.io/jq/) | `jq` | JSON 处理 |
| [7-Zip](https://www.7-zip.org) | `7z` | 压缩/解压 |
| [eza](https://github.com/eza-community/eza) | `eza` | 现代 `ls` / `tree` |
| [lsd](https://github.com/lsd-rs/lsd) | `lsd` | 另一个现代 `ls` |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | `z` | 智能 `cd` |
| [PSFzf](https://github.com/kelleyma49/PSFzf) | — | fzf 与 PSReadLine 集成（Ctrl+R / Ctrl+T） |

## 快速安装

在一个普通（或管理员）PowerShell 窗口运行：

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
2. 添加 `extras` bucket
3. 安装上表中的所有工具
4. 安装 `PSFzf` 模块
5. 把 `config/Microsoft.PowerShell_profile.ps1` 复制到你的 `$PROFILE`（已有的会自动备份为 `*.bak-<时间戳>`）

> 脚本可重复运行——每一步都会先检查是否已安装。
>
> 只想装工具、不动 profile？加 `-NoProfile`：`.\install.ps1 -NoProfile`

安装完成后**新开一个 PowerShell 窗口**（或运行 `. $PROFILE`）即可生效。

## 使用说明

### 列表与树形（eza）

```powershell
ls                 # 简洁列表（目录优先）
ll                 # 详细列表，含隐藏文件 + git 状态
la                 # 显示所有文件
lt                 # 树形，限 2 层（替代 tree）
tree               # 完整树形
eza --icons -la    # 带图标（需安装 Nerd Font 字体）
```

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

### JSON / 压缩

```powershell
something | jq '.key'        # 提取 JSON 字段
7z x archive.zip             # 解压
7z a archive.7z folder\      # 压缩
```

## 仓库结构

```
windows-cli-setup/
├── install.ps1                              # 一键安装脚本
├── config/
│   └── Microsoft.PowerShell_profile.ps1     # PowerShell 配置（别名/快捷键/zoxide）
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

- 图标默认未开启（`--icons`），因为终端需使用 [Nerd Font](https://www.nerdfonts.com/) 字体才能正常显示图标。装好字体后可在 profile 各函数里加 `--icons` 参数。
- profile 使用 `function` 而非 `Set-Alias`，以便携带默认参数（如 `--git`、`--tree --level=2`）。

## License

MIT

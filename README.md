# dotfiles

[GNU Stow](https://www.gnu.org/software/stow/) で管理。

## Setup

```bash
git clone git@github.com:ShinoharaTa/dotfiles.git ~/dotfiles
cd ~/dotfiles
stow zsh git wezterm claude
```

## Structure

```
zsh/                    - Zsh設定
  .zshrc
git/                    - Git設定
  .gitconfig
wezterm/                - WezTerm設定
  .config/wezterm/
    wezterm.lua
    keybinds.lua
claude/                 - Claude Code設定
  .claude/
    settings.json           グローバル設定 (model, statusLine, plugins)
    statusline-command.sh   htop風Status Lineスクリプト
```

### Claude Code 補足

- `stow claude` で `~/.claude/settings.json` と `~/.claude/statusline-command.sh` がリンクされる
- `settings.local.json` (permissions) はマシン固有のためdotfiles管理外
- Status Lineの依存: `jq`, `git`, `curl`, macOS `security` コマンド
- 新PCでは `claude` コマンドで初回ログイン後に Status Line が動作する

## Usage

```bash
# パッケージの追加（シンボリックリンク作成）
stow <package>

# パッケージの削除（シンボリックリンク解除）
stow -D <package>

# パッケージの再適用
stow -R <package>
```

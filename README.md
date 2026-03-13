# dotfiles

[GNU Stow](https://www.gnu.org/software/stow/) で管理。

## Setup

```bash
git clone git@github.com:ShinoharaTa/dotfiles.git ~/dotfiles
cd ~/dotfiles
stow zsh git wezterm
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
```

## Usage

```bash
# パッケージの追加（シンボリックリンク作成）
stow <package>

# パッケージの削除（シンボリックリンク解除）
stow -D <package>

# パッケージの再適用
stow -R <package>
```

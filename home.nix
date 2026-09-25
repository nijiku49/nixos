{ pkgs, inputs, ... }:

{
  imports = [
    ./mango.nix
    ./desktop.nix
    ./quickshell.nix
    ./nvim.nix
    ./fastfetch.nix
    ./theme.nix
  ];

  home.username = "y";
  home.homeDirectory = "/home/y";
  home.stateVersion = "26.05";

  home.packages = with pkgs; [
    firefox
    pfetch
    eza
    gcc
    papirus-icon-theme
    wl-clipboard # wl-copy / wl-paste
  ];

  # xdg.configFile."wallpaper.png".source = ./wallpaper.png

  programs.foot = {
    enable = true;
    settings = {
      main = {
        font = "FiraCode Nerd Font:size=12";
        # отступ текста от краёв окна
        pad = "16x16";
        # цвета: include из theme.nix
      };
    };
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ls = "eza --icons --group-directories-first";
    };
    initContent = ''
      autoload -U colors && colors

      # цвета текущей схемы `theme` (новые окна foot-сервера иначе остаются со старыми)
      [ -f ~/.local/state/theme/sequences ] && cat ~/.local/state/theme/sequences

      # ansi-цвета: меняются вместе с `theme`
      PROMPT="%F{6}[%F{4}%n%F{2}@%F{5}%m %F{5}%~%F{6}]%f\$ "
    '';
  };
}

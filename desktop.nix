{ pkgs, lib, ... }:

let
  state = "$HOME/.local/state/theme";

  # скриншоты: `shot` - область, `shot full` - весь экран
  # сохраняются в ~/screenshots и сразу копируются в буфер обмена
  shot = pkgs.writeShellScriptBin "shot" ''
    export PATH=${lib.makeBinPath (with pkgs; [ grim slurp wl-clipboard libnotify jq coreutils ])}:$PATH
    dir="$HOME/screenshots"
    mkdir -p "$dir"
    file="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"

    if [ "$1" = full ]; then
      grim "$file" || exit 1
    else
      accent=$(jq -r '.c[12]' "${state}/current.json" 2>/dev/null)
      [ -n "$accent" ] && [ "$accent" != null ] || accent="#ffffff"
      region=$(slurp -d -w 2 -b "#00000066" -c "$accent"ff) || exit 0
      grim -g "$region" "$file" || exit 1
    fi

    wl-copy --type image/png < "$file"
    notify-send -a "screenshot" -i "$file" "Screenshot taken" "copied to clipboard · $(basename "$file")"
  '';

  # блокировка экрана в цветах текущей темы, фоном - текущие обои
  lock = pkgs.writeShellScriptBin "lock" ''
    export PATH=${lib.makeBinPath (with pkgs; [ swaylock jq coreutils gnused ])}:$PATH
    get() { jq -r "$1" "${state}/current.json" 2>/dev/null | sed 's/^#//'; }
    bg=$(get .bg); fg=$(get .fg); accent=$(get '.c[12]'); red=$(get '.c[9]'); green=$(get '.c[10]')
    [ -n "$bg" ] && [ "$bg" != null ] || { bg=161616; fg=f2f4f8; accent=78a9ff; red=ee5396; green=42be65; }

    set -- --color "$bg"
    wall=$(cat "${state}/wallpaper" 2>/dev/null)
    [ -f "$wall" ] && set -- "$@" --image "$wall" --scaling fill

    exec swaylock -f "$@" \
      --font "FiraCode Nerd Font" --font-size 20 \
      --indicator-idle-visible --indicator-radius 90 --indicator-thickness 8 \
      --inside-color "$bg"dd --inside-ver-color "$bg"dd --inside-wrong-color "$bg"dd --inside-clear-color "$bg"dd \
      --ring-color "$accent" --ring-ver-color "$accent" --ring-wrong-color "$red" --ring-clear-color "$green" \
      --key-hl-color "$green" --bs-hl-color "$red" \
      --line-color 00000000 --line-ver-color 00000000 --line-wrong-color 00000000 --line-clear-color 00000000 \
      --separator-color 00000000 \
      --text-color "$fg" --text-ver-color "$fg" --text-wrong-color "$red" --text-clear-color "$fg" \
      --ignore-empty-password --show-failed-attempts
  '';

  # простой: 5 мин - тусклый экран, 10 мин - блокировка, 20 мин - сон
  idle = pkgs.writeShellScriptBin "idle" ''
    export PATH=${lib.makeBinPath (with pkgs; [ swayidle brightnessctl systemd ])}:$PATH
    exec swayidle -w \
      timeout 300 'brightnessctl -s set 10%' resume 'brightnessctl -r' \
      timeout 600 'lock' \
      timeout 1200 'systemctl suspend' \
      before-sleep 'lock'
  '';

  # яркость с всплывающим индикатором: `bright +5%` / `bright 5%-`
  bright = pkgs.writeShellScriptBin "bright" ''
    export PATH=${lib.makeBinPath (with pkgs; [ brightnessctl coreutils ])}:$PATH
    pct=$(brightnessctl -m set "$1" | cut -d, -f4 | tr -d %)
    qs ipc call osd brightness "$pct" >/dev/null 2>&1
  '';

  # история буфера обмена (cliphist) для меню quickshell
  clip = pkgs.writeShellScriptBin "clip" ''
    export PATH=${lib.makeBinPath (with pkgs; [ cliphist wl-clipboard ])}:$PATH
    case "$1" in
      list) cliphist list ;;
      copy) printf '%s' "$2" | cliphist decode | wl-copy ;;
      delete) printf '%s' "$2" | cliphist delete ;;
      wipe) cliphist wipe ;;
    esac
  '';

  # запустить программу в терминале сразу в цветах темы: `trun btop`
  trun = pkgs.writeShellScriptBin "trun" ''
    exec footclient -e sh -c 'cat ~/.local/state/theme/sequences 2>/dev/null; exec "$@"' sh "$@"
  '';
in
{
  home.packages = [
    shot
    lock
    idle
    bright
    clip
    trun
  ]
  ++ (with pkgs; [
    grim
    slurp
    swaylock
    swayidle
    cliphist
    libnotify # notify-send
    imv # картинки
  ]);

  # ================= файловый менеджер =================
  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    # `y` - открыть yazi и после выхода остаться в той папке
    shellWrapperName = "y";
    settings = {
      mgr = {
        show_hidden = true;
        sort_dir_first = true;
        linemode = "size";
      };
    };
  };

  # ================= медиа =================
  programs.mpv = {
    enable = true;
    config = {
      # декодирование на видеокарте: меньше нагрузка и расход батареи
      hwdec = "auto-safe";
      vo = "gpu-next";
      keep-open = "yes";
      save-position-on-quit = "yes";
    };
  };

  programs.zathura = {
    enable = true;
    options = {
      selection-clipboard = "clipboard";
      adjust-open = "width";
      font = "FiraCode Nerd Font 11";
    };
  };

  # чем открывать файлы (yazi, браузер и т.д.)
  xdg.mimeApps = {
    enable = true;
    defaultApplications =
      let
        image = "imv.desktop";
        video = "mpv.desktop";
      in
      {
        "image/png" = image;
        "image/jpeg" = image;
        "image/webp" = image;
        "image/gif" = image;
        "image/bmp" = image;
        "image/svg+xml" = image;
        "video/mp4" = video;
        "video/x-matroska" = video;
        "video/webm" = video;
        "video/quicktime" = video;
        "audio/mpeg" = video;
        "audio/flac" = video;
        "audio/ogg" = video;
        "application/pdf" = "org.pwmt.zathura.desktop";
      };
  };
}

# команда `theme`: применяет цветовую схему и обои ко всей системе
#   theme list            - список схем
#   theme set <name>      - применить схему (сразу: терминалы, quickshell, neovim; btop - при запуске)
#   theme wall <file>     - поставить обои
#   theme walls           - список картинок из ~/images
#   theme reapply [quiet] - заново сгенерировать файлы текущей схемы
{ pkgs, lib, config }:

let
  home = config.home.homeDirectory;
  schemes = pkgs.writeText "schemes.json" (builtins.toJSON (import ./themes.nix));

  cmd = pkgs.writeShellScriptBin "theme" ''
    export PATH=${lib.makeBinPath [ pkgs.jq pkgs.coreutils pkgs.findutils ]}:$PATH

    schemes=${schemes}
    state="${home}/.local/state/theme"
    walldir="${home}/images"
    mkdir -p "$state" "${home}/.config/btop/themes"

    # сообщить quickshell, что файлы обновились
    notify() {
      if command -v qs >/dev/null; then qs ipc call theme reload >/dev/null 2>&1; fi
    }

    apply() {
      name=$1
      mode=$2
      if ! jq -e --arg n "$name" 'has($n)' "$schemes" >/dev/null; then
        echo "no such scheme: $name (see: theme list)" >&2
        exit 1
      fi

      jq --arg n "$name" '.[$n] + {name: $n}' "$schemes" > "$state/current.json"
      printf '%s\n' "$name" > "$state/name"
      [ -f "$state/wallpaper" ] || printf '%s\n' "$walldir/wall1.png" > "$state/wallpaper"

      # foot: цвета для новых окон
      jq -r --arg n "$name" '.[$n] as $t
        | "[colors-dark]",
          "background=" + ($t.bg | ltrimstr("#")),
          "foreground=" + ($t.fg | ltrimstr("#")),
          ($t.c | to_entries[]
            | (if .key < 8 then "regular" + (.key | tostring) else "bright" + (.key - 8 | tostring) end)
              + "=" + (.value | ltrimstr("#")))' \
        "$schemes" > "$state/foot.ini"

      # btop
      jq -r --arg n "$name" '.[$n] as $t | $t.c as $c | [
          ["main_bg", ""], ["main_fg", $t.fg], ["title", $t.fg], ["hi_fg", $c[12]],
          ["selected_bg", $c[8]], ["selected_fg", $t.fg], ["inactive_fg", $c[8]],
          ["graph_text", $t.fg], ["meter_bg", $c[8]], ["proc_misc", $c[14]],
          ["cpu_box", $c[12]], ["mem_box", $c[10]], ["net_box", $c[13]], ["proc_box", $c[14]],
          ["div_line", $c[8]], ["temp_start", $c[10]], ["temp_mid", $c[11]], ["temp_end", $c[9]],
          ["cpu_start", $c[12]], ["cpu_mid", $c[14]], ["cpu_end", $c[13]],
          ["free_start", $c[10]], ["free_mid", $c[10]], ["free_end", $c[10]],
          ["cached_start", $c[14]], ["cached_mid", $c[14]], ["cached_end", $c[14]],
          ["available_start", $c[11]], ["available_mid", $c[11]], ["available_end", $c[11]],
          ["used_start", $c[9]], ["used_mid", $c[9]], ["used_end", $c[9]],
          ["download_start", $c[12]], ["download_mid", $c[14]], ["download_end", $c[13]],
          ["upload_start", $c[13]], ["upload_mid", $c[11]], ["upload_end", $c[9]],
          ["process_start", $c[12]], ["process_mid", $c[14]], ["process_end", $c[13]]
        ] | .[] | "theme[" + .[0] + "]=\"" + .[1] + "\""' \
        "$schemes" > "${home}/.config/btop/themes/current.theme"

      # escape-последовательности с палитрой: ими перекрашиваются открытые терминалы,
      # а каждый новый zsh выводит их при старте (сервер foot сам цвета не перечитывает)
      seq=$(jq -j --arg n "$name" '.[$n] as $t
        | ($t.c | to_entries | map("\u001b]4;" + (.key | tostring) + ";" + .value + "\u0007") | join("")),
          "\u001b]10;" + $t.fg + "\u0007",
          "\u001b]11;" + $t.bg + "\u0007",
          "\u001b]12;" + $t.fg + "\u0007"' "$schemes")
      printf '%s' "$seq" > "$state/sequences"

      [ "$mode" = quiet ] && return

      # уже открытые терминалы
      for t in /dev/pts/[0-9]*; do
        if [ -O "$t" ] && [ -w "$t" ]; then printf '%s' "$seq" > "$t" 2>/dev/null; fi
      done

      # открытые neovim
      for s in "$XDG_RUNTIME_DIR"/nvim.*; do
        if [ -S "$s" ]; then
          timeout 2 nvim --server "$s" --remote-expr 'v:lua.ApplyTheme()' >/dev/null 2>&1
        fi
      done

      notify
    }

    case "$1" in
      list)
        jq -r 'keys[]' "$schemes"
        ;;
      set)
        apply "$2" live
        ;;
      reapply)
        current=$(cat "$state/name" 2>/dev/null)
        if [ -z "$current" ] || ! jq -e --arg n "$current" 'has($n)' "$schemes" >/dev/null; then
          current=oxocarbon
        fi
        apply "$current" "$2"
        ;;
      wall)
        if [ ! -f "$2" ]; then echo "no such file: $2" >&2; exit 1; fi
        realpath "$2" > "$state/wallpaper"
        notify
        ;;
      walls)
        find -L "$walldir" -maxdepth 2 -type f \
          \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) 2>/dev/null | sort
        ;;
      *)
        echo "theme list | theme set <name> | theme wall <file> | theme walls"
        ;;
    esac
  '';
in
{
  inherit cmd schemes;
  stateDir = "${home}/.local/state/theme";
}

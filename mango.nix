{ pkgs, lib, ... }:

let
  tags = lib.range 1 9;
  perTag = f: lib.concatMapStringsSep "\n" f tags;
in
{
  # конфиг mango (https://mangowm.github.io/docs), перечитать: Alt+R
  xdg.configFile."mango/config.conf".text = ''
    # ================= окружение =================
    env=XDG_CURRENT_DESKTOP,mango
    env=XDG_SESSION_DESKTOP,mango
    env=XDG_SESSION_TYPE,wayland
    env=QS_ICON_THEME,Papirus-Dark
    env=XCURSOR_SIZE,18
    cursor_size=18

    # ================= автозапуск =================
    # переменные для порталов и systemd-сервисов
    exec-once=${pkgs.dbus}/bin/dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE MANGO_INSTANCE_SIGNATURE
    # бар, меню и обои
    exec-once=qs
    # один процесс foot на все терминалы
    exec-once=foot --server
    # окно ввода пароля, когда программе нужны права администратора
    exec-once=${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1
    # история буфера обмена
    exec-once=wl-paste --watch cliphist store
    # блокировка и сон при простое
    exec-once=idle

    # ================= внешний вид =================
    # размытие и тени выключены: экономия памяти и батареи
    blur=0
    blur_layer=0
    shadows=0
    layer_shadows=0

    border_radius=12
    borderpx=0
    no_border_when_single=1

    gappih=6
    gappiv=6
    gappoh=12
    gappov=12

    # ================= анимации =================
    animations=1
    layer_animations=1
    animation_type_open=zoom
    animation_type_close=zoom
    animation_fade_in=1
    animation_fade_out=1
    zoom_initial_ratio=0.85
    animation_duration_open=220
    animation_duration_close=180
    animation_duration_move=220
    animation_duration_tag=250
    animation_curve_open=0.46,1.0,0.29,1
    animation_curve_close=0.08,0.92,0,1
    animation_curve_move=0.46,1.0,0.29,1
    animation_curve_tag=0.46,1.0,0.29,1

    # обои и бар без анимаций, меню quickshell плавно появляются
    layerrule=noanim:1,layer_name:quickshell-wallpaper
    layerrule=noanim:1,layer_name:^quickshell$
    layerrule=animation_type_open:fade,animation_type_close:fade,layer_name:quickshell-(launcher|style|wifi|clipboard|power|osd|notifications)
    # выделение области для скриншота - без анимаций, чтобы не попасть в кадр
    layerrule=noanim:1,noblur:1,layer_name:selection

    # ================= раскладка окон =================
    ${perTag (i: "tagrule=id:${toString i},layout_name:dwindle")}

    # ================= ввод =================
    xkb_rules_layout=us,ru
    repeat_rate=30
    repeat_delay=300
    sloppyfocus=1
    warpcursor=0

    tap_to_click=1
    trackpad_natural_scrolling=1
    trackpad_disable_while_typing=1

    # ================= клавиши =================
    # всё на Alt: клавиша Win (Super) на клавиатуре не работает.
    # Alt+цифры в браузере (вкладки) теперь перехватывает mango - вкладки листай Ctrl+Tab
    bind=ALT,Return,spawn,footclient
    bind=ALT,q,killclient,
    bind=ALT,d,spawn,qs ipc call launcher toggle
    bind=ALT,t,spawn,qs ipc call style themes
    bind=ALT,w,spawn,qs ipc call style walls
    bind=ALT,f,togglefloating,
    bind=ALT+SHIFT,f,togglefullscreen,
    bind=ALT,Tab,toggleoverview,
    bind=ALT,space,switch_keyboard_layout,
    bind=ALT,r,reload_config,
    bind=ALT+SHIFT,e,quit,
    bind=ALT,Escape,spawn,qs ipc call power toggle
    bind=ALT,l,spawn,lock
    bind=ALT,v,spawn,qs ipc call clipboard toggle
    bind=ALT,e,spawn,trun yazi

    # скриншоты: Print - область, Shift+Print - весь экран (или Alt+Shift+S)
    bind=NONE,Print,spawn,shot
    bind=SHIFT,Print,spawn,shot full
    bind=ALT+SHIFT,s,spawn,shot

    # фокус и перемещение окон
    bind=ALT,Left,focusdir,left
    bind=ALT,Right,focusdir,right
    bind=ALT,Up,focusdir,up
    bind=ALT,Down,focusdir,down
    bind=ALT+SHIFT,Left,exchange_client,left
    bind=ALT+SHIFT,Right,exchange_client,right
    bind=ALT+SHIFT,Up,exchange_client,up
    bind=ALT+SHIFT,Down,exchange_client,down

    # теги (рабочие столы): Alt+N - перейти, Alt+Shift+N - перенести окно
    ${perTag (i: "bind=ALT,${toString i},view,${toString i},0")}
    ${perTag (i: "bind=ALT+SHIFT,${toString i},tag,${toString i},0")}

    # мышь: Alt+ЛКМ - двигать, Alt+ПКМ - менять размер, колесо - теги
    mousebind=ALT,btn_left,moveresize,curmove
    mousebind=ALT,btn_right,moveresize,curresize
    axisbind=ALT,UP,viewtoleft_have_client
    axisbind=ALT,DOWN,viewtoright_have_client

    # жесты тачпада: 3 пальца - фокус, 4 пальца - теги и обзор
    gesturebind=none,left,3,focusdir,left
    gesturebind=none,right,3,focusdir,right
    gesturebind=none,right,4,viewprev_have_client
    gesturebind=none,left,4,viewnext_have_client
    gesturebind=none,up,4,enteroverview
    gesturebind=none,down,4,leaveoverview

    # яркость и звук
    bind=NONE,XF86MonBrightnessUp,spawn,bright +5%
    bind=NONE,XF86MonBrightnessDown,spawn,bright 5%-
    bind=NONE,XF86AudioRaiseVolume,spawn,wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+
    bind=NONE,XF86AudioLowerVolume,spawn,wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
    bind=NONE,XF86AudioMute,spawn,wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
  '';
}

{ config, pkgs, lib, inputs, ... }:

# пк: i3-10100F (без встроенной графики), ASUS GTX 1650 Phoenix, 16 ГБ, sata-диск 500 ГБ
let
  hasHardware = builtins.pathExists ./hardware-configuration.nix;
in
{
  # железо и диски генерируются на самой машине:
  #   sudo nixos-generate-config --show-hardware-config > /etc/nixos/hardware-configuration.nix
  # без файла сборка сразу останавливается с понятной подсказкой
  imports =
    if hasHardware then
      [ ./hardware-configuration.nix ./gaming.nix ]
    else
      throw ''

        нет /etc/nixos/hardware-configuration.nix, сгенерируй его:
          sudo nixos-generate-config --show-hardware-config > /etc/nixos/hardware-configuration.nix
        при установке с флешки:
          nixos-generate-config --root /mnt --show-hardware-config > /mnt/etc/nixos/hardware-configuration.nix
      '';

  networking.hostName = "nixbox";

  # ================= сеть по кабелю =================
  # wifi (iwd, ниже) тоже работает, если появится адаптер
  networking.useNetworkd = true;
  systemd.network.networks."10-wired" = {
    matchConfig.Name = "en*";
    networkConfig.DHCP = "yes";
  };
  # не ждать сеть при загрузке
  systemd.network.wait-online.enable = false;

  # ================= nvidia gtx 1650 (turing) =================
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    # открытые модули ядра nvidia: для turing (gtx 16xx) рекомендованы самой nvidia.
    # если будут артефакты или чёрный экран - поставь false
    open = true;
    # обязательно для wayland
    modesetting.enable = true;
    # сохраняет видеопамять при сне, без этого после пробуждения бывает мусор на экране
    powerManagement.enable = true;
    nvidiaSettings = false;
  };

  # аппаратное декодирование видео через nvidia
  hardware.graphics.extraPackages = with pkgs; [ nvidia-vaapi-driver ];

  environment.sessionVariables.LIBVA_DRIVER_NAME = "nvidia";
  environment.sessionVariables.NVD_BACKEND = "direct";
  environment.sessionVariables.GBM_BACKEND = "nvidia-drm";
  environment.sessionVariables.__GLX_VENDOR_LIBRARY_NAME = "nvidia";
  # у wlroots-композиторов (mango) аппаратный курсор на nvidia может пропадать
  environment.sessionVariables.WLR_NO_HARDWARE_CURSORS = "1";

	# Limine
  
  boot.loader.limine = {
    enable = true;
    efiSupport = true;
    maxGenerations = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # ядро zen: настроено на отзывчивость десктопа
  boot.kernelPackages = pkgs.linuxPackages_zen;
  # без watchdog и лишнего вывода: меньше пробуждений cpu, быстрее загрузка
  boot.kernelParams = [ "quiet" "loglevel=3" "nowatchdog" "nmi_watchdog=0" ];
  boot.blacklistedKernelModules = [ "iTCO_wdt" "iTCO_vendor_support" ];
  boot.initrd.systemd.enable = true;

	# iwd

  networking.useDHCP = false;
  networking.wireless.iwd = {
    enable = true;
    settings = {
      General.EnableNetworkConfiguration = true;
      Network.NameResolvingService = "systemd";
    };
  };
  services.resolved.enable = true;

	# графика

  hardware.graphics.enable = true;
  # прошивки для wifi, ethernet, видеокарт
  hardware.enableRedistributableFirmware = true;

	# some env shit

  # mango: лёгкий wayland-композитор на базе dwl
  programs.mango.enable = true;

  services.greetd = {
    enable = true;
    settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd mango";
  };

  environment.systemPackages = with pkgs; [
    git
    vim
    vis
    brightnessctl
    spotify
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

	# audio (pipewire) + battery for quickshell

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  services.upower.enable = true;

  nixpkgs.config.allowUnfree = true;

	# память и производительность

  # сжатая подкачка в оперативке: вмещает в 2-3 раза больше данных, чем обычная ram
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };
  boot.kernel.sysctl = {
    "vm.swappiness" = 180;
    "vm.page-cluster" = 0;
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 125;
  };

  # более лёгкая и быстрая реализация dbus
  services.dbus.implementation = "broker";

  # electron/chromium-приложения (spotify и т.п.) сразу под wayland, без xwayland
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # при нехватке памяти убивается самое прожорливое приложение, а не всё зависает
  systemd.oomd = {
    enable = true;
    enableRootSlice = true;
    enableUserSlices = true;
  };

  # диск: без записи времени доступа к файлам, регулярный trim для ssd
  fileSystems = lib.mkIf hasHardware { "/".options = [ "noatime" ]; };
  services.fstrim.enable = true;

  # журнал не разрастается
  services.journald.settings.Journal = {
    SystemMaxUse = "100M";
    RuntimeMaxUse = "30M";
  };

  # сборка nixos-rebuild не тормозит работу за компьютером
  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";

  # не собирать html-справку nixos при каждой пересборке
  documentation.nixos.enable = false;

  # чистка старых поколений и дедупликация store
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  fonts.packages = with pkgs; [
    nerd-fonts.hasklug
    comic-mono
    # основной шрифт системы: Fira Code с иконками nerd fonts ("FiraCode Nerd Font")
    nerd-fonts.fira-code
  ];

  programs.clash-verge = {
    enable = true;
    # системный сервис clash-verge: поднимает tun-интерфейс с нужными правами
    serviceMode = true;
    # права для tun (и его dns), rpfilter переводится в loose
    tunMode = true;
  };
  # модуль tun грузим заранее: сервис работает в песочнице и сам загрузить его не может
  boot.kernelModules = [ "tun" ];
  # раньше polkit включал модуль hyprland, clash-verge и другим программам он нужен
  security.polkit.enable = true;
  # swaylock проверяет пароль через pam
  security.pam.services.swaylock = { };

  networking.firewall = {
    trustedInterfaces = [ "Mihomo" ];
    extraReversePathFilterRules = ''iifname { "Mihomo" } accept comment "trusted interface"'';
  };

	# user

  users.users.y = {
    # пароль при первом входе - смени его командой `passwd`
    initialPassword = "nixos";
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" "video" "input" ];
  };

  programs.zsh.enable = true;
  
  security.sudo.enable = true;
  security.doas = {
    enable = true;
    extraRules = [ { groups = [ "wheel" ]; noPass = true; keepEnv = true; } ];
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  time.timeZone = "Europe/Samara";
  i18n.defaultLocale = "en_US.UTF-8";

  system.stateVersion = "26.11";
}

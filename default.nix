# основной пк: i3-10100F (без встроенной графики), ASUS GTX 1650 Phoenix, 16 ГБ, sata-диск 500 ГБ
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "nixbox";

  # ================= сеть по кабелю =================
  # wifi (iwd) остаётся из общего конфига, если появится адаптер
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

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    NVD_BACKEND = "direct";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    # у wlroots-композиторов (mango) аппаратный курсор на nvidia может пропадать
    WLR_NO_HARDWARE_CURSORS = "1";
  };
}

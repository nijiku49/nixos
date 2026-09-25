{ pkgs, ... }:

# игры: steam, proton, 32-битные драйверы, gamemode, mangohud
{
  # 32-битные библиотеки opengl/vulkan: без них steam и большинство игр не запустятся
  # (драйвер nvidia из configuration.nix подтягивает и свою 32-битную часть)
  hardware.graphics.enable32Bit = true;

  programs.steam = {
    enable = true;
    # порты для remote play и передачи игр по локальной сети
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    # proton-ge: часто лучше работает с играми, чем стандартный proton.
    # в свойствах игры: совместимость -> GE-Proton
    extraCompatPackages = with pkgs; [ proton-ge-bin ];
    # протонтрикс для установки библиотек windows внутрь префикса игры
    protontricks.enable = true;
    # отдельная сессия gamescope (как на steam deck), можно выбрать в tuigreet
    gamescopeSession.enable = true;
  };

  # gamescope: запуск игры в своём микрокомпозиторе, помогает с масштабированием и vsync
  programs.gamescope = {
    enable = true;
    capSysNice = true;
  };

  # gamemode: на время игры поднимает приоритет и включает производительный режим cpu
  # в параметрах запуска игры в steam: gamemoderun %command%
  programs.gamemode.enable = true;
  users.users.y.extraGroups = [ "gamemode" ];

  environment.systemPackages = with pkgs; [
    # оверлей с fps и загрузкой: mangohud %command%
    mangohud
    # проверка vulkan: vulkaninfo --summary
    vulkan-tools
    # запуск игр не из steam (epic, gog и т.п.), wine скачивает сам
    lutris
  ];
}

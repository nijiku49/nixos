{ pkgs, lib, config, ... }:

let
  theme = import ./theme-script.nix { inherit pkgs lib config; };
in
{
  home.packages = [ theme.cmd ];

  # при каждой пересборке заново генерируем файлы текущей схемы
  home.activation.theme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${theme.cmd}/bin/theme reapply quiet || true
  '';

  # foot берёт цвета из файла, который пишет `theme`
  programs.foot.settings.main.include = "${theme.stateDir}/foot.ini";

  programs.btop = {
    enable = true;
    settings = {
      color_theme = "current";
      theme_background = false;
      vim_keys = true;
      update_ms = 1500;
    };
  };
}

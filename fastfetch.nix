{ ... }:

# цвета - ansi, поэтому совпадают с промптом и меняются вместе с `theme`
{
  programs.fastfetch = {
    enable = true;
    settings = {
      logo = {
        source = "nixos_small";
        color = {
          "1" = "blue";
          "2" = "magenta";
        };
        padding = {
          top = 1;
          left = 2;
          right = 5;
        };
      };

      display = {
        separator = "   ";
      };

      modules = [
        "break"
        {
          type = "title";
          fqdn = false;
          color = {
            user = "blue";
            at = "green";
            host = "magenta";
          };
        }
        "break"
        {
          type = "os";
          key = "os    ";
          keyColor = "blue";
        }
        {
          type = "host";
          key = "host  ";
          keyColor = "green";
        }
        {
          type = "kernel";
          key = "kernel";
          keyColor = "magenta";
        }
        {
          type = "uptime";
          key = "uptime";
          keyColor = "cyan";
        }
        {
          type = "memory";
          key = "memory";
          keyColor = "blue";
        }
        {
          type = "packages";
          key = "pkgs  ";
          keyColor = "green";
        }
        "break"
        {
          # 7 основных цветов терминала
          type = "custom";
          format = "{#31}●  {#32}●  {#33}●  {#34}●  {#35}●  {#36}●  {#37}●";
        }
      ];
    };
  };
}

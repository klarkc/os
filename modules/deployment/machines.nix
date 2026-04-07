{ root ? ../.. }:
let
  rootPath = if builtins.isPath root then root else builtins.toPath root;
  modulesDir = rootPath + "/modules";
  moduleEntries = builtins.readDir modulesDir;
  domains = builtins.filter (domain:
    domain != "deployment" && domain != "shared" && moduleEntries.${domain}
    == "directory"
    && builtins.pathExists (modulesDir + "/${domain}/machines.nix"))
    (builtins.attrNames moduleEntries);
in builtins.foldl'
(acc: domain: acc // import (modulesDir + "/${domain}/machines.nix")) { }
domains

let klarkc = builtins.readFile ./klarkc.pub;
    cache-vultr = builtins.readFile ./cache-vultr.pub;
in
{
  "cache.age".publicKeys = [ cache-vultr ];
}

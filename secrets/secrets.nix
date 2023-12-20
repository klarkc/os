let klarkc = builtins.readFile ./klarkc.pub; in
{
  "cache.age".publicKeys = [ klarkc ];
}

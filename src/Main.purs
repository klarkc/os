module Main where

type Inputs a b c r0 r1 r2 r3 r4
  = { nixpkgs ::
        { lib ::
            { nixosSystem ::
                { system :: a
                , modules :: Array b
                } ->
                c
            | r0
            }
        | r1
        }
    , microvm ::
        { nixosModules ::
            { microvm :: b
            | r3
            }
        | r4
        }
    | r2
    }

type Context a b
  = { system :: a
    , pkgs :: { microvm :: { nixosModules :: { microvm :: b } } }
    }

main :: forall a b c r0 r1 r2 r3 r4. Inputs a b c r0 r1 r2 r3 r4 -> Context a b -> c
main inputs ctx =
  inputs.nixpkgs.lib.nixosSystem
    { system: ctx.system
    , modules:
        [ inputs.microvm.nixosModules.microvm
        ]
    }

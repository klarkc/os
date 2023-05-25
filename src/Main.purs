module Main where

type Inputs a r0 r1 r2 r3 r4
  = { nixpkgs ::
        { lib ::
            { nixosSystem ::
                { system :: System
                , modules :: Array Module
                } ->
                a
            | r0
            }
        | r1
        }
    , microvm ::
        { nixosModules ::
            { microvm :: MicrovmModule
            | r3
            }
        | r4
        }
    | r2
    }

type Context
  = { system :: System
    , pkgs :: { microvm :: { nixosModules :: { microvm :: MicrovmModule } } }
    }

data MicrovmModule

data System

type NetworkingModule
  = { networking :: { hostName :: String } }

type UsersModule
  = { users :: { users :: { root :: { password :: String } } } }

data Module
  = Microvm MicrovmModule
  | Networking NetworkingModule
  | Users UsersModule

fromModule :: forall a. Module -> a
fromModule (Microvm mod) = mod
fromModule (Networking mod) = mod
fromModule (Users mod) = mod

networking :: NetworkingModule
networking = { networking: { hostName: "klarkc-os" } }

users :: UsersModule
users = { users: { users: { root: { password: "1234" } } } }

main :: forall r0 r1 r2 r3 r4. Inputs a r0 r1 r2 r3 r4 -> Context -> a
main inputs ctx =
  inputs.nixpkgs.lib.nixosSystem
    { system: ctx.system
    , modules:
        [ fromModule (Microvm inputs.microvm.nixosModules.microvm)
        , fromModule (Networking networking)
        , fromModule (Users users)
        ]
    }

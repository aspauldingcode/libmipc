{
  description = "libmipc - High-performance Mach-based IPC library for macOS";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/24.11";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = forAllSystems (system: import nixpkgs { inherit system; });
    in
    {
      packages = forAllSystems (system: let pkgs = pkgsFor.${system}; arch = if system == "aarch64-darwin" then "arm64" else "x86_64"; in {
        default = pkgs.stdenvNoCC.mkDerivation {
          pname = "libmipc";
          version = "1.0.1";
          src = ./.;

          __noChroot = true;

          buildPhase = ''
            unset SDKROOT
            unset DEVELOPER_DIR
            unset NIX_APPLE_SDK_VERSION
            export PATH=/usr/bin:/bin:/usr/sbin
            
            echo "Compiling libmipc..."
            xcrun clang -arch ${arch} -c src/mipc.m \
              -fobjc-arc -Wall -Werror -Iinclude
            
            echo "Creating static library..."
            ar rcs libmipc.a mipc.o
          '';

          installPhase = ''
            mkdir -p $out/lib $out/include
            cp libmipc.a $out/lib/
            cp include/mipc.h $out/include/
          '';
        };
      });
      
      # Allow using as a flake input
      devShells = forAllSystems (system: let pkgs = pkgsFor.${system}; in {
        default = pkgs.mkShell {
          buildInputs = [ self.packages.${system}.default ];
        };
      });

      # Unit tests and Example compilation
      checks = forAllSystems (system: let pkgs = pkgsFor.${system}; arch = if system == "aarch64-darwin" then "arm64" else "x86_64"; in {
        test = pkgs.stdenvNoCC.mkDerivation {
          pname = "libmipc-tests";
          version = "1.0.0";
          src = ./.;
          __noChroot = true;
          buildPhase = ''
            unset SDKROOT
            unset DEVELOPER_DIR
            unset NIX_APPLE_SDK_VERSION
            export PATH=/usr/bin:/bin:/usr/sbin
            echo "Compiling tests..."
            xcrun clang -arch ${arch} -o tests_mipc \
              -fobjc-arc -Wall -Werror -Iinclude src/mipc.m src/tests_mipc.m \
              -framework Foundation -framework CoreFoundation
          '';
          installPhase = ''
            echo "Running tests..."
            ./tests_mipc
            mkdir $out
          '';
        };

        example = pkgs.stdenvNoCC.mkDerivation {
          pname = "libmipc-examples";
          version = "1.0.0";
          src = ./.;
          __noChroot = true;
          buildPhase = ''
            unset SDKROOT
            unset DEVELOPER_DIR
            unset NIX_APPLE_SDK_VERSION
            export PATH=/usr/bin:/bin:/usr/sbin
            
            echo "Compiling example server..."
            xcrun clang -arch ${arch} -o server \
              -fobjc-arc -Wall -Werror -Iinclude src/mipc.m example/server.m \
              -framework Foundation -framework CoreFoundation
              
            echo "Compiling example client..."
            xcrun clang -arch ${arch} -o client \
              -fobjc-arc -Wall -Werror -Iinclude src/mipc.m example/client.m \
              -framework Foundation -framework CoreFoundation
          '';
          installPhase = ''
            mkdir -p $out/bin
            cp server client $out/bin/
          '';
        };

        security = pkgs.stdenvNoCC.mkDerivation {
          pname = "libmipc-security";
          version = "1.0.0";
          src = ./.;
          __noChroot = true;
          buildPhase = ''
            unset SDKROOT
            unset DEVELOPER_DIR
            unset NIX_APPLE_SDK_VERSION
            export PATH=/usr/bin:/bin:/usr/sbin
            
            echo "Compiling security test runner..."
            xcrun clang -arch ${arch} -o tests_security \
              -fobjc-arc -Wall -Werror -Iinclude src/mipc.m src/tests_security.m \
              -framework Foundation -framework CoreFoundation
          '';
          installPhase = ''
            set -x
            echo "Running security tests..."
            ./tests_security
            mkdir $out
          '';
        };

        discovery = pkgs.stdenvNoCC.mkDerivation {
          pname = "libmipc-discovery";
          version = "1.0.0";
          src = ./.;
          __noChroot = true;
          buildPhase = ''
            unset SDKROOT
            unset DEVELOPER_DIR
            unset NIX_APPLE_SDK_VERSION
            export PATH=/usr/bin:/bin:/usr/sbin
            
            echo "Compiling discovery test runner..."
            xcrun clang -arch ${arch} -o tests_discovery \
              -fobjc-arc -Wall -Werror -Iinclude src/mipc.m src/tests_discovery.m \
              -framework Foundation -framework CoreFoundation
          '';
          installPhase = ''
            echo "Running discovery tests..."
            ./tests_discovery
            mkdir $out
          '';
        };
      });
    };
}

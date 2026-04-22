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
              -fobjc-arc -Wall -Werror -Wextra -Wpedantic -Iinclude
            
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

      checks = forAllSystems (system: let pkgs = pkgsFor.${system}; arch = if system == "aarch64-darwin" then "arm64" else "x86_64"; in
        let 
          # Unified test runner for all checks that need the daemon
          unifiedTestRunner = pkgs.stdenvNoCC.mkDerivation {
            pname = "libmipc-unified-tests";
            version = "1.0.0";
            src = ./.;
            __noChroot = true;
            buildPhase = ''
              unset SDKROOT
              unset DEVELOPER_DIR
              unset NIX_APPLE_SDK_VERSION
              export PATH=/usr/bin:/bin:/usr/sbin
              
              echo "Compiling daemon for test..."
              xcrun clang -arch ${arch} -o mipcd \
                -fobjc-arc -Wall -Werror -Wextra -Iinclude daemon/mipcd.m \
                -framework Foundation

              echo "Compiling all test runners..."
              for test_file in src/tests_*.m; do
                test_name=$(basename "$test_file" .m)
                echo "Compiling $test_name..."
                xcrun clang -arch ${arch} -o "$test_name" \
                  -fobjc-arc -Wall -Werror -Wextra -Wpedantic -Iinclude src/mipc.m "$test_file" \
                  -framework Foundation -framework CoreFoundation
              done
            '';
            installPhase = ''
              echo "Starting daemon in background..."
              ./mipcd &
              MIPCD_PID=$!
              sleep 2 # Give daemon time to start

              # The 'test' check is bootstrap-independent and doesn't need the daemon
              echo "--- Running Basic MIPC Test ---"
              ./tests_mipc

              # All other tests require the daemon
              echo "--- Running Sandbox Test ---"
              ./tests_sandbox

              echo "--- Running Security Test ---"
              ./tests_security

              echo "--- Running Discovery Test ---"
              ./tests_discovery

              echo "--- Running Stress Test ---"
              ./tests_stress

              echo "Cleaning up daemon..."
              kill $MIPCD_PID
              mkdir $out
            '';
          };
        in
        {
          # The main 'test' check now runs everything
          test = unifiedTestRunner;
          sandbox = unifiedTestRunner;
          security = unifiedTestRunner;
          stress = unifiedTestRunner;
          discovery = unifiedTestRunner;
        });
    };
}

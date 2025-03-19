{
  description = "3FS - File system for foundation models from deepseek-ai";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "3FS";
          version = "0.1.0";
          src = pkgs.fetchFromGitHub {
            owner = "deepseek-ai";
            repo = "3fs"; # Lowercase is correct
            rev = "f9a4291e693087946634432063aa2095f0aca45d";
            sha256 = "sha256-RF+IlkxRbJNX6Gmu55OCYqoYkjWJ1lfUNsAhUmNUkcI=";
            fetchSubmodules = true;
          };

          nativeBuildInputs = with pkgs; [
            git
            cmake
            ninja
            pkg-config
            clang_14
            python3
            rustc
            cargo
            rustfmt
            clippy
          ];

          buildInputs = with pkgs; [
            # Use boost 1.71 if available, otherwise fall back to another version
            (
              if pkgs.lib.hasAttr "boost171" pkgs
              then boost171
              else if pkgs.lib.hasAttr "boost172" pkgs
              then boost172
              else boost177
            )
            libuv
            lz4
            xz
            double-conversion
            libdwarf
            libunwind
            libaio
            gflags
            glog
            gtest
            lld_14
            gperftools
            openssl.dev
            libevent
            fmt

            # Additional dependencies from README
            fuse3
            foundationdb

            # Python dependencies
            python3
            python3Packages.pybind11

            # Ensure we have the C++ runtime libraries
            stdenv.cc.cc.lib
          ];

          # Helper function to get the appropriate Boost package
          passthru.getBoost = pkgs:
            if pkgs ? boost171
            then pkgs.boost171
            else if pkgs ? boost172
            then pkgs.boost172
            else pkgs.boost177;

          preConfigure = ''
            echo "Checking directory structure:"
            find . -type f -name "*.sh" | sort

            echo "Initializing git submodules manually:"
            git config --global --add safe.directory "*"
            git submodule update --init --recursive

            echo "Applying patches using the project's patch script:"
            if [ -f ./patches/apply.sh ]; then
              chmod +x ./patches/apply.sh
              ./patches/apply.sh
              echo "Patches applied successfully"
            else
              echo "Warning: patches/apply.sh not found!"
              find . -name "apply.sh" | while read patchfile; do
                echo "Found potential patch script at: $patchfile"
              done
            fi

            # Direct source code modification - the nuclear option
            echo "Directly patching CMakeLists.txt files:"

            # Find the main Boost find_package call and add our settings directly before it
            # We'll add a print statement so we can see it in the logs
            if grep -q "find_package(Boost" CMakeLists.txt; then
              echo "Found Boost package call, applying direct patch..."
              sed -i '/find_package(Boost/i # Force Boost settings - manually patched\nset(Boost_USE_STATIC_LIBS OFF CACHE BOOL "Use Boost static libs" FORCE)\nset(Boost_USE_SHARED_LIBS ON CACHE BOOL "Use Boost shared libs" FORCE)\nset(Boost_NO_BOOST_CMAKE OFF CACHE BOOL "Use Boost cmake" FORCE)\nmessage(STATUS "MANUALLY FORCING Boost_USE_STATIC_LIBS=OFF")' CMakeLists.txt
            fi

            # Patch all other files that might override our settings
            find . -type f \( -name "*.cmake" -o -name "CMakeLists.txt" \) -exec grep -l "Boost_USE_STATIC_LIBS" {} \; | while read file; do
              echo "Aggressive patching of $file"
              sed -i 's/set(Boost_USE_STATIC_LIBS *ON)/set(Boost_USE_STATIC_LIBS OFF)/g' "$file"
              sed -i 's/set(Boost_USE_STATIC_LIBS *TRUE)/set(Boost_USE_STATIC_LIBS FALSE)/g' "$file"
              sed -i 's/Boost_USE_STATIC_LIBS *ON/Boost_USE_STATIC_LIBS OFF/g' "$file"
              sed -i 's/Boost_USE_STATIC_LIBS *TRUE/Boost_USE_STATIC_LIBS FALSE/g' "$file"
            done

            # Create an initial cache file with our settings
            cat > initial-cache.cmake << 'EOF'
            set(Boost_USE_STATIC_LIBS OFF CACHE BOOL "Use Boost static libs" FORCE)
            set(Boost_USE_SHARED_LIBS ON CACHE BOOL "Use Boost shared libs" FORCE)
            set(Boost_USE_MULTITHREADED ON CACHE BOOL "Use Boost multithreaded libs" FORCE)
            set(Boost_NO_BOOST_CMAKE OFF CACHE BOOL "Do not use Boost's own CMake" FORCE)
            set(Boost_NO_SYSTEM_PATHS OFF CACHE BOOL "Do not search system for Boost" FORCE)
            EOF

            # Check our patching work
            echo "Modified CMakeLists.txt content around Boost:"
            grep -A 10 -B 10 "find_package(Boost" CMakeLists.txt || true
          '';

          # Clean up hooks we don't need
          postPatch = "";
          postFetch = "";

          configurePhase = ''
            # Define boost variable to make the script more readable
            export BOOST_PKG="${
              if pkgs ? boost171
              then pkgs.boost171
              else
                (
                  if pkgs ? boost172
                  then pkgs.boost172
                  else pkgs.boost177
                )
            }"

            export PYTHONPATH=${pkgs.python3}/lib/python3.10/site-packages:${pkgs.python3Packages.pybind11}/lib/python3.10/site-packages

            # Force shared libraries in the environment
            export Boost_USE_STATIC_LIBS=OFF
            export Boost_USE_SHARED_LIBS=ON
            export Boost_NO_BOOST_CMAKE=OFF
            export CMAKE_PREFIX_PATH=${pkgs.fmt}/lib/cmake/fmt

            # Create symbolic links for Boost libs to help CMake find them
            mkdir -p build/boost_libs
            echo "Creating symlinks for Boost libraries from: $BOOST_PKG/lib"
            for lib in $BOOST_PKG/lib/libboost_*.so*; do
              echo "Linking $lib"
              ln -sf $lib build/boost_libs/
            done
            export BOOST_LIBRARYDIR=$PWD/build/boost_libs

            # Define the main CMake command with all our settings
            echo "Running CMake configure..."
            CMAKE_COMMAND="cmake -B build -S . -G Ninja \
              -C initial-cache.cmake \
              -DCMAKE_BUILD_TYPE=RelWithDebInfo \
              -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
              -DCMAKE_INSTALL_PREFIX=$out \
              -DCMAKE_CXX_COMPILER=${pkgs.clang_14}/bin/clang++ \
              -DCMAKE_C_COMPILER=${pkgs.clang_14}/bin/clang \
              -DPYTHON_EXECUTABLE=${pkgs.python3}/bin/python3 \
              -DBoost_USE_STATIC_LIBS=OFF \
              -DBoost_USE_SHARED_LIBS=ON \
              -DBoost_NO_BOOST_CMAKE=OFF \
              -DBOOST_ROOT=$BOOST_PKG \
              -DBOOST_INCLUDEDIR=$BOOST_PKG/include \
              -DBOOST_LIBRARYDIR=$BOOST_LIBRARYDIR \
              -Dfmt_DIR=${pkgs.fmt}/lib/cmake/fmt"

            echo "CMake command: $CMAKE_COMMAND"
            eval "$CMAKE_COMMAND"

            # Post-configure: Check and possibly modify the CMake cache
            if [ -f build/CMakeCache.txt ]; then
              echo "CMake cache exists. Checking Boost settings:"
              grep -i "boost_.*static" build/CMakeCache.txt || echo "No Boost static settings found"

              # Force-modify the cache if needed
              if grep -q "Boost_USE_STATIC_LIBS:BOOL=ON" build/CMakeCache.txt; then
                echo "WARNING: Cache still has Boost_USE_STATIC_LIBS=ON, manually fixing..."
                sed -i 's/Boost_USE_STATIC_LIBS:BOOL=ON/Boost_USE_STATIC_LIBS:BOOL=OFF/g' build/CMakeCache.txt

                # Re-run CMake to apply the modified cache
                echo "Re-running CMake with patched cache..."
                cmake -B build
              fi
            else
              echo "ERROR: CMake cache not created!"
            fi
          '';

          buildPhase = ''
            echo "Building with $NIX_BUILD_CORES cores..."
            cmake --build build -j $NIX_BUILD_CORES
          '';

          installPhase = ''
            echo "Installing to $out..."
            cmake --install build
          '';

          # Boost-related environment variables
          BOOST_ROOT = let
            boost =
              if pkgs ? boost171
              then pkgs.boost171
              else
                (
                  if pkgs ? boost172
                  then pkgs.boost172
                  else pkgs.boost177
                );
          in "${boost}";
          BOOST_INCLUDEDIR = let
            boost =
              if pkgs ? boost171
              then pkgs.boost171
              else
                (
                  if pkgs ? boost172
                  then pkgs.boost172
                  else pkgs.boost177
                );
          in "${boost}/include";
          BOOST_LIBRARYDIR = let
            boost =
              if pkgs ? boost171
              then pkgs.boost171
              else
                (
                  if pkgs ? boost172
                  then pkgs.boost172
                  else pkgs.boost177
                );
          in "${boost}/lib";
          Boost_USE_STATIC_LIBS = "OFF";
          Boost_USE_SHARED_LIBS = "ON";
          Boost_NO_BOOST_CMAKE = "OFF";

          # Compiler settings
          CC = "${pkgs.clang_14}/bin/clang";
          CXX = "${pkgs.clang_14}/bin/clang++";
          CMAKE_PREFIX_PATH = "${pkgs.fmt}/lib/cmake/fmt";

          # Python settings
          PYTHON_EXECUTABLE = "${pkgs.python3}/bin/python3";
          PYTHONPATH = "${pkgs.python3}/lib/python3.10/site-packages:${pkgs.python3Packages.pybind11}/lib/python3.10/site-packages";

          meta = with pkgs.lib; {
            description = "3FS - File system for foundation models from deepseek-ai";
            homepage = "https://github.com/deepseek-ai/3fs";
            license = licenses.mit;
            platforms = platforms.unix;
            maintainers = [];
          };
        };

        # Development shell with necessary dependencies
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            git
            cmake
            ninja
            pkg-config
            clang_14
            (
              if pkgs.lib.hasAttr "boost171" pkgs
              then boost171
              else if pkgs.lib.hasAttr "boost172" pkgs
              then boost172
              else boost177
            )
            libuv
            lz4
            xz
            double-conversion
            libdwarf
            libunwind
            libaio
            gflags
            glog
            gtest
            lld_14
            gperftools
            openssl.dev
            libevent
            fmt

            # Python
            python3
            python3Packages.pybind11

            # Rust toolchain
            rustc
            cargo
            rustfmt
            clippy

            # Additional dependencies from README
            fuse3
            foundationdb
          ];

          # Boost environment settings
          BOOST_ROOT = let
            boost =
              if pkgs ? boost171
              then pkgs.boost171
              else
                (
                  if pkgs ? boost172
                  then pkgs.boost172
                  else pkgs.boost177
                );
          in "${boost}";
          BOOST_INCLUDEDIR = let
            boost =
              if pkgs ? boost171
              then pkgs.boost171
              else
                (
                  if pkgs ? boost172
                  then pkgs.boost172
                  else pkgs.boost177
                );
          in "${boost}/include";
          BOOST_LIBRARYDIR = let
            boost =
              if pkgs ? boost171
              then pkgs.boost171
              else
                (
                  if pkgs ? boost172
                  then pkgs.boost172
                  else pkgs.boost177
                );
          in "${boost}/lib";
          Boost_USE_STATIC_LIBS = "OFF";
          Boost_USE_SHARED_LIBS = "ON";
          Boost_NO_BOOST_CMAKE = "OFF";

          # Python settings
          PYTHON_EXECUTABLE = "${pkgs.python3}/bin/python3";
          PYTHONPATH = "${pkgs.python3}/lib/python3.10/site-packages:${pkgs.python3Packages.pybind11}/lib/python3.10/site-packages";

          # Compiler settings
          CC = "${pkgs.clang_14}/bin/clang";
          CXX = "${pkgs.clang_14}/bin/clang++";

          shellHook = ''
            echo "3FS development environment activated"
            echo "Boost root: $BOOST_ROOT"
            echo "Boost include dir: $BOOST_INCLUDEDIR"
            echo "Boost library dir: $BOOST_LIBRARYDIR"
            echo "Python executable: $PYTHON_EXECUTABLE"
            echo "C compiler: $CC"
            echo "C++ compiler: $CXX"

            # Create compile_commands.json symlink for IDE integration
            if [ -f build/compile_commands.json ]; then
              ln -sf build/compile_commands.json compile_commands.json
            fi

            # Helper function to build in dev shell
            function build3fs() {
              echo "Building 3FS with dev shell settings..."

              # Create a CMake initial cache file with our settings
              cat > initial-cache.cmake << 'EOF'
              set(Boost_USE_STATIC_LIBS OFF CACHE BOOL "Use Boost static libs" FORCE)
              set(Boost_USE_SHARED_LIBS ON CACHE BOOL "Use Boost shared libs" FORCE)
              set(Boost_USE_MULTITHREADED ON CACHE BOOL "Use Boost multithreaded libs" FORCE)
              set(Boost_NO_BOOST_CMAKE OFF CACHE BOOL "Do not use Boost's own CMake" FORCE)
              set(Boost_NO_SYSTEM_PATHS OFF CACHE BOOL "Do not search system for Boost" FORCE)
              EOF

              # Create symbolic links for Boost libs to help CMake find them
              mkdir -p build/boost_libs
              for lib in $BOOST_ROOT/lib/libboost_*.so*; do
                ln -sf $lib build/boost_libs/
              done
              export BOOST_LIBRARYDIR=$PWD/build/boost_libs

              # Run CMake with our settings
              cmake -B build -S . -G Ninja \
                -C initial-cache.cmake \
                -DCMAKE_BUILD_TYPE=RelWithDebInfo \
                -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
                -DCMAKE_CXX_COMPILER=$CXX \
                -DCMAKE_C_COMPILER=$CC \
                -DPYTHON_EXECUTABLE=$PYTHON_EXECUTABLE \
                -DBoost_USE_STATIC_LIBS=OFF \
                -DBoost_USE_SHARED_LIBS=ON \
                -DBoost_NO_BOOST_CMAKE=OFF \
                -DBOOST_ROOT=$BOOST_ROOT \
                -DBOOST_INCLUDEDIR=$BOOST_INCLUDEDIR \
                -DBOOST_LIBRARYDIR=$BOOST_LIBRARYDIR

              # Build the project
              cmake --build build -j $(nproc)
            }

            echo "Use 'build3fs' command to build the project"
          '';
        };
      }
    );
}

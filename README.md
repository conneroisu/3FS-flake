# 3FS Nix Flake

A Nix flake for building and deploying the Fire-Flyer File System (3FS), a high-performance distributed file system optimized for AI workloads.

## About 3FS

3FS (Fire-Flyer File System) is a distributed file system designed specifically for AI and machine learning workloads. It provides high-performance storage with features tailored for the needs of modern AI applications, including efficient handling of large datasets, parallel I/O operations, and seamless integration with AI frameworks.

## Features

This Nix flake provides:

- **Complete 3FS package build** with all dependencies
- **NixOS module** for easy system integration and service management
- **Development environment** with all necessary build tools
- **Automated testing** through NixOS VM integration tests
- **Multi-component deployment** including:
  - Metadata service (`meta`)
  - Storage service (`storage`) 
  - Management daemon (`mgmtd`)
  - Monitor collector (`monitor`)
  - FUSE client for filesystem mounting

## Quick Start

### Building 3FS

```bash
# Build the 3FS package
nix build

# Or specifically build the 3FS package
nix build .#3fs
```

### Development Environment

```bash
# Enter development shell with all dependencies
nix develop

# This provides access to:
# - Build tools (cmake, clang, rust toolchain)
# - Dependencies (FoundationDB, FUSE, RDMA, etc.)
# - Development utilities (gdb, valgrind, etc.)
```

### Using as a NixOS Module

Add this flake to your NixOS configuration:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    threefs-flake.url = "github:your-org/3FS-flake";
  };

  outputs = { nixpkgs, threefs-flake, ... }: {
    nixosConfigurations.your-host = nixpkgs.lib.nixosSystem {
      modules = [
        threefs-flake.nixosModules.default
        {
          services."3fs" = {
            enable = true;
            meta.enable = true;
            storage.enable = true;
            mgmtd.enable = true;
            fuse = {
              enable = true;
              mountPoint = "/mnt/3fs";
            };
          };
        }
      ];
    };
  };
}
```

## System Requirements

- **Linux only** - 3FS requires Linux-specific features (FUSE, RDMA, etc.)
- **FoundationDB** - Used as the underlying metadata store
- **RDMA support** (optional but recommended for high-performance networking)

## Architecture

3FS consists of several components that work together:

1. **Meta Service** - Manages filesystem metadata using FoundationDB
2. **Storage Service** - Handles data storage across distributed nodes
3. **Management Daemon** - Provides cluster management and monitoring
4. **Monitor Collector** - Collects performance and health metrics
5. **FUSE Client** - Provides POSIX filesystem interface

## Configuration

The NixOS module provides extensive configuration options:

- **Service-specific settings** for each component
- **Custom data directories** and storage targets
- **Network configuration** including ports and clustering
- **Performance tuning** options for AI workloads

See the NixOS module options in `flake.nix` for detailed configuration possibilities.

## Testing

Run integration tests using NixOS VMs:

```bash
# Run the full integration test suite
nix build .#checks.x86_64-linux.integration-test

# Run individual package tests
nix flake check
```

## Dependencies

Key dependencies automatically managed by this flake:

- **Core**: CMake, Clang, Rust toolchain
- **Storage**: FoundationDB, RocksDB, LevelDB
- **Networking**: gRPC, Thrift, RDMA-core
- **Performance**: jemalloc, mimalloc, liburing
- **Filesystem**: FUSE3, libaio
- **Compression**: LZ4, Zstd
- **Utilities**: Boost, Protocol Buffers, Arrow

## Development

For development and testing:

1. **Enter the development shell**: `nix develop`
2. **Configure FoundationDB**: Set up cluster configuration
3. **Build and test**: Use the provided build tools
4. **Run services**: Start individual 3FS components for testing

The development environment includes debugging tools, formatters, and language servers for productive development.

## License

See the upstream 3FS project for licensing information.

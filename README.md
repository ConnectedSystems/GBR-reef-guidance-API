# Reef Guidance API

API for supporting reef suitability assessments.

## Setup

Initialize the project the usual way:

```julia
]instantiate
```

A TOML file should be defined indicating location of the MPA dataset.
These are currently the files/data created in Step/Script 1a in https://github.com/open-AIMS/GBR-reef-guidance-assessment

```toml
[prepped_data]
PREPPED_DATA_DIR = "C:/some_path_to_data/MPA/"

[server_config]
CACHE_DIR = "<some location to cache geotiffs>"
DEBUG_MODE = "false"  # Optional, disables file caching and displays debug logs
COG_THREADS = "2"  # Optional, Number of threads to use when creating COGs (defaults to 1)
TILE_SIZE = "256"  # Optional, tile block size to use (defaults to 256)
```

By convention, this file is named `.config.toml` (note the leading `.`).

## Quickstart

```julia
using ReefGuideAPI

# To enable debug messages:
# ENV["JULIA_DEBUG"] = "ReefGuideAPI"

# If multiple threads are available, a parallel server will be spun up
ReefGuideAPI.start_server(".config.toml")
```

In its current state, the main page displays a simple form for dev/testing purposes.

## Dynamic COG generation

Example URL:

```code
http://127.0.0.1:8000/assess/Cairns-Cooktown/slopes?criteria_names=Depth,Slope&lb=-9.0,0.0&ub=-2.0,40.0
```

## Simple Slippy Tiles

Example URL:

```code
http://127.0.0.1:8000/tile/8/231/139?region=Cairns-Cooktown&rtype=slopes&criteria_names=Depth,Slope,Rugosity&lb=-9.0,0.0,0.0&ub=-2.0,40.0,0.0
```

## Development setup

The steps below assumes you are in the project root.

Create a sandbox enviroment:

```bash
$ mkdir sandbox
$ cd sandbox
$ julia --project=.
(sandbox) julia> ]add Revise Infiltrator
(sandbox) julia> ]dev ..
```

Copy the quickstart to a file (e.g., `dev_server.jl`).

Create the `.config.toml` file and save to the sandbox directory.

Assuming VS Code is configured to default to the sandbox environment and start the
Julia REPL at project root:

```julia
;cd sandbox
include("dev_server.jl")
```

Note that the server now caches the initially loaded spatial data in between server
launches to reduce downtime. It will be necessary to restart the Julia session to reload
spatial data.

## Performance notes

The config setting `COG_THREADS` controls how many threads should be requested when writing
out COGs. Ideally this will be set to at least 2 (preferably 4).
Higher values do seem to reduce write times but with diminishing returns (tested up to 8).
Locally, write times with four threads configured range from 10 to 15 seconds.

## Reef edge alignment for site searching

`identify_potential_sites_edges()` can be used to identify potential sites that only align with
the nearest reef edge (or specified rotations away from this angle).
This method works by identifying the closest edge of reef polygon geometries that have been
converted into lines.

The following processing is required before use:

- Reef polygons should be simplified (`GO.simplify()`) and buffered to avoid matching possibly inaccurate reef edges.
- Simplified reef polygons should be provided as vertex-vertex lines with `polygon_to_lines()`.
- Require raster of target pixels to search, and their indices (currently a vector of `CartesianIndices` for identifying search pixels). Use `findall(bool_search_raster)` to return pixel indices.
- Raster of search pixels should be masked by reef polygons or simplified reef polygons.
- The target region name should be specified in GBRMPA format.
  - E.g. "Townsville/Whitsunday Management Area" rather than "Townsville-Whitsunday".

### Parquet assessment additional setup
- A parquet GeoDataFrame must be loaded and filtered for unsuitable pixels based on user criteria thresholds using a Dict and `within_thresholds()`.
- `lon` and `lat` columns (FLoat64) must be added to the GeoDataFrame.
  - E.g. `valid_pixels.lon = first.(GI.coordinates.(valid_pixels.geometry))`
  The column used for masking should be the same as the column specified as geometry_col in
  `identify_potential_sites_edges` (default = `:geometry`).

## Docker build and run

The ReefGuideAPI.jl package has an associated `Dockerfile` and build/publish process. This means you can run an instance of the ReefGuideAPI.jl package without needing to compile/build it with a local `Julia` installation. You will be able to view the latest published versions of the Docker image on the repository packages page.

### Mounting files and required data

As mentioned above, the `ReefGuideAPI.jl` package currently requires

- a `config.toml` file and
- a set of input data files

Please include these in a folder called `data` in your working directory.

When running the below commands, it is assumed you have `data` available locally with the required files.

**Note**: Due to how Docker excludes `.` files, we have named the config file `config.toml` in the data folder. This is required to launch the server.

### To build from src files using Docker

```
docker build . --target reefguide-src -t reefguide
```

### To build from src files using Docker Compose

```
docker compose up --build reefguide-src
```

### To run with mounted files (launch server) using Docker

```
docker run -p 8000:8000 -v ./data:/data/reefguide reefguide
```

### To run with mounted files (launch server) using Docker Compose

```
docker compose up reefguide-src
```

### To run with mounted files (interactive shell) using Docker

This will start a Julia shell where `ReefGuideAPI` is compiled and ready for use e.g.

```
using ReefGuideAPI
ReefGuideAPI.start_server("/data/reefguide/config.toml")
```

```
docker run --rm --interactive --entrypoint="julia" --tty -v ./data:/data/reefguide reefguide
```

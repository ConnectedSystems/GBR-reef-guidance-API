module ReefGuideAPI

using Base.Threads
using
    Glob,
    TOML

using Serialization

using DataFrames
using OrderedCollections
using Memoization
using SparseArrays

import GeoDataFrames as GDF
using
    ArchGDAL,
    GeoParquet,
    Rasters

using
    HTTP,
    Oxygen

include("criteria_assessment/criteria.jl")
include("criteria_assessment/query_thresholds.jl")

include("site_assessment/common_functions.jl")
include("site_assessment/best_fit_polygons.jl")

include("Middleware.jl")

function get_regions()
    # TODO: Comes from config?
    regions = String[
        "Townsville-Whitsunday",
        "Cairns-Cooktown",
        "Mackay-Capricorn",
        "FarNorthern"
    ]

    return regions
end

"""
    setup_regional_data(config::Dict)

Load regional data to act as an in-memory cache.

# Arguments
- `config` : Configuration settings, typically loaded from a TOML file.
- `reef_data_path` : Path to pre-prepared reef data

# Returns
OrderedDict of `RegionalCriteria` for each region.
"""
function setup_regional_data(config::Dict)
    if @isdefined(REGIONAL_DATA)
        @debug "Using previously generated regional data store."
        sleep(1)  # Pause so message is noticeably visible
        return REGIONAL_DATA
    end

    # Check disk-based store
    reg_cache_dir = config["server_config"]["REGIONAL_CACHE_DIR"]
    reg_cache_fn = joinpath(reg_cache_dir, "regional_cache.dat")
    if isfile(reg_cache_fn)
        @debug "Loading regional data cache from disk"
        @eval const REGIONAL_DATA = deserialize($(reg_cache_fn))
        return REGIONAL_DATA
    end

    @debug "Setting up regional data store..."

    reef_data_path = config["prepped_data"]["PREPPED_DATA_DIR"]

    regional_assessment_data = OrderedDict{String,RegionalCriteria}()
    for reg in get_regions()
        data_paths = String[]
        data_names = String[]

        slope_table = nothing
        flat_table = nothing

        for (k, dp) in criteria_data_map()
            g = glob("$reg*$dp.tif", reef_data_path)
            if length(g) == 0
                continue
            end

            push!(data_paths, first(g))
            push!(data_names, string(k))
            if occursin("valid", string(dp))
                # Load up Parquet files
                parq_file = replace(first(g), ".tif" => "_lookup.parq")

                if occursin("slope", string(dp))
                    slope_table = GeoParquet.read(parq_file)
                elseif occursin("flat", string(dp))
                    flat_table = GeoParquet.read(parq_file)
                else
                    msg = "Unknown lookup found: $(parq_file). Must be 'slope' or 'flat'"
                    throw(ArgumentError(msg))
                end
            end
        end

        # Pre-extract long/lat coordinates
        coords = GI.coordinates.(slope_table.geometry)
        slope_table[!, :lons] .= first.(coords)
        slope_table[!, :lats] .= last.(coords)

        coords = GI.coordinates.(flat_table.geometry)
        flat_table[!, :lons] .= first.(coords)
        flat_table[!, :lats] .= last.(coords)

        rst_stack = RasterStack(data_paths; name=data_names, lazy=true)
        regional_assessment_data[reg] = RegionalCriteria(
            rst_stack,
            slope_table,
            flat_table
        )
    end

    # Store cache on disk to avoid excessive cold startup times
    @debug "Saving regional data cache to disk"
    serialize(reg_cache_fn, regional_assessment_data)

    # Remember, `@eval` runs in global scope.
    @eval const REGIONAL_DATA = $(regional_assessment_data)

    return REGIONAL_DATA
end

"""
    _cache_location(config::Dict)::String

Retrieve cache location for geotiffs.
"""
function _cache_location(config::Dict)::String
    cache_loc = try
        in_debug = "DEBUG_MODE" in config["server_config"]
        if in_debug && lowercase(config["server_config"]["DEBUG_MODE"]) == "true"
            mktempdir()
        else
            config["server_config"]["TIFF_CACHE_DIR"]
        end
    catch
        mktempdir()
    end

    return cache_loc
end

"""
    n_gdal_threads(config::Dict)::String

Retrieve the configured number of threads to use when writing COGs with GDAL.
"""
function n_gdal_threads(config::Dict)::String
    n_cog_threads = try
        config["server_config"]["COG_THREADS"]
    catch
        "1"  # Default to using a single thread for GDAL write
    end

    return n_cog_threads
end

"""
    tile_size(config::Dict)::Tuple

Retrieve the configured size of map tiles in pixels (width and height / lon and lat).
"""
function tile_size(config::Dict)::Tuple
    tile_dims = try
        res = parse(Int, config["server_config"]["TILE_SIZE"])
        (res, res)
    catch
        (256, 256)  # 256x256
    end

    return tile_dims
end

function get_auth_router(config::Dict)
    # Setup auth middleware - depends on config.toml - can return identity func
    auth = setup_jwt_middleware(config)
    return router(""; middleware=[auth])
end

"""
    warmup_cache(config_path::String)

Invokes warm up of regional data cache to reduce later spin up times.
"""
function warmup_cache(config_path::String)
    config = TOML.parsefile(config_path)
    return setup_regional_data(config)
end

function start_server(config_path)
    @info "Launching server... please wait"

    @info "Parsing configuration from $(config_path)..."
    config = TOML.parsefile(config_path)

    @info "Setting up auth middleware and router."
    auth = get_auth_router(config)

    @info "Setting up region routes..."
    setup_region_routes(config, auth)

    @info "Setting up tile routes..."
    setup_tile_routes(config, auth)

    port = 8000
    @info "Initialisation complete, starting server on port $(port) with $(Threads.nthreads()) threads."

    return serve(;
        middleware=[CorsMiddleware],
        host="0.0.0.0",
        port=port,
        parallel=Threads.nthreads() > 1
    )
end

export
    RegionalCriteria,
    criteria_data_map

# Methods to assess/identify deployment "plots" of reef.
export
    assess_reef_site,
    identify_potential_sites_edges,
    filter_sites,
    output_geojson

# Geometry handling
export
    create_poly,
    create_bbox,
    port_buffer_mask,
    meters_to_degrees,
    polygon_to_lines

# Raster->Index interactions (defunct?)
export
    valid_slope_lon_inds,
    valid_slope_lat_inds,
    valid_flat_lon_inds,
    valid_flat_lat_inds

# Ruleset thresholds
export
    within_thresholds

end

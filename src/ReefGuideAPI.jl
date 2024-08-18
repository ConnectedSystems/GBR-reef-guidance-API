module ReefGuideAPI

using
    Glob,
    TOML

using DataFrames
using OrderedCollections
using Memoization
using SparseArrays

import GeoDataFrames as GDF
using
    GeoParquet,
    Rasters

using
    FLoops,
    HTTP,
    Oxygen

include("assessment/criteria.jl")
include("geom_handlers/site_assessment.jl")
include("assessment/query_thresholds.jl")


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

@memoize function setup_regional_data(reef_data_path::String)
    regional_assessment_data = OrderedDict{String, RegionalCriteria}()
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
                parq_file = replace(first(g), ".tif"=>"_lookup.parq")

                _valid_geodf = GeoParquet.read(parq_file)
                if occursin("slope", string(dp))
                    slope_table = _valid_geodf
                elseif occursin("flat", string(dp))
                    flat_table = _valid_geodf
                else
                    error("Unknown lookup found: $(parq_file)")
                end
            end
        end

        rst_stack = RasterStack(data_paths; name=data_names, lazy=true)

        regional_assessment_data[reg] = RegionalCriteria(
            rst_stack,
            slope_table,
            flat_table,
            Raster(
                rst_stack[names(rst_stack)[1]];
                data=zeros(Float32, size(rst_stack)),
                missingval=-9999.0
            )
        )
    end

    return regional_assessment_data
end

function regional_assessment_data(config)
    return setup_regional_data(config["prepped_data"]["PREPPED_DATA_DIR"])
end


export
    RegionalCriteria,
    criteria_data_map,
    regional_assessment_data

# Methods to assess/identify deployment "plots" of reef.
export
    assess_reef_site,
    identify_potential_sites

# Geometry handling
export
    create_poly,
    create_bbox,
    port_buffer_mask

# Raster->Index interactions (defunct?)
export
    valid_slope_lon_inds,
    valid_slope_lat_inds,
    valid_flat_lon_inds,
    valid_flat_lat_inds


function start_server(config_path)
    config = TOML.parsefile(config_path)
    setup_region_routes(config)
    serve(port=8000)
end

end

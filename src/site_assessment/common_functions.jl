""" Functions common to both site_assessment methods."""

using LinearAlgebra
using GeoDataFrames

include("geom_ops.jl")

"""
    meters_to_degrees(x, lat)

Convert meters to degrees at target latitude.
"""
function meters_to_degrees(x, lat)
    return x / (111.1 * 1000 * cosd(lat))
end

"""
    degrees_to_meters(x, lat)

Convert degrees to meters at target latitude.
"""
function degrees_to_meters(x, lat)
    return x * (111.1 * 1000 * cosd(lat))
end

"""
    from_zero(v::Vector{Tuple{Float64,Float64}})::Vector{Tuple{Float64, Float64}}

Translates Vector of points `v` to begin from (0, 0), retaining direction and length.

# Argument
- `v` : Vector of point coordinates (`Tuple{Float64, Float64}`).
"""
function from_zero(v::Vector{Tuple{Float64,Float64}})::Vector{Tuple{Float64,Float64}}
    max_coord = maximum(v)
    if first(v) == max_coord
        v = reverse(v)
    end

    new_coords = [
        Vector{Union{Missing,Float64}}(missing, size(max_coord, 1)),
        Vector{Union{Missing,Float64}}(missing, size(max_coord, 1))
    ]
    for (j, coords) in enumerate(new_coords)
        for val in eachindex(coords)
            coords[val] = max_coord[val] - v[j][val]
        end
    end

    return Tuple.(new_coords)
end

"""
    line_angle(a::T, b::T)::Float64 where {T <: Vector{Tuple{Float64,Float64}}}

Calculate the angle between two lines.

# Arguments
- `a` : Line between point coordinates.
- `b` : Line between point coordinates.

# Returns
Angle between the two lines.

# Examples
```julia
line_angle([(0.0,5.0), (0.0,0.0)], from_zero(edge_line))
line_angle([(0.0,5.0), (0.0,0.0)], [(1.0, 4.0), (7.0, 8.0)])
```
"""
function line_angle(a::T, b::T)::Float64 where {T<:Vector{Tuple{Float64,Float64}}}
    return acosd(clamp(a ⋅ b / (norm(a) * norm(b)), -1, 1))
end

"""
    filter_far_polygons(gdf::DataFrame, pixel::GIWrap.Point, lat::Float64, dist::Union{Int64,Float64})::BitVector

Filter out reefs that are > `dist` (meters) from the target pixel (currently `dist` is hardcoded in `initial_search_rotation()`).
"""
function filter_far_polygons(
    gdf::DataFrame,
    pixel::GeometryBasics.Point,
    lat::Float64,
    dist::Union{Int64,Float64}
)::BitVector
    geoms = gdf[:, first(GI.geometrycolumns(gdf))]
    return (GO.distance.(GO.centroid.(geoms), [pixel]) .< meters_to_degrees(dist, lat))
end

"""
    initial_search_box(
        (lon::Float64, lat::Float64),
        x_dist::Union{Int64, Float64},
        y_dist::Union{Int64, Float64},
        target_crs::GeoFormatTypes.CoordinateReferenceSystemFormat,
        res::Float64
    )::GI.Wrappers.Polygon

Create an initial search box that is centered around the point `(lon, lat)` in `target_crs`,
and is buffered by `res` distance.

# Arguments
- `(lon, lat)` : Longitude and latitude coordinates of the center target pixel.
- `x_dist` : x (longitude) dimension length of initial search box.
- `y_dist` : y (latitude) dimension length of initial search box.
- `target_crs` : Target CRS of box to match input data types.
- `res` : Buffer distance (resolution of input raster search data).

# Returns
Initial search box geometry.
"""
function initial_search_box(
    (lon, lat),
    x_dist::Union{Int64,Float64},
    y_dist::Union{Int64,Float64},
    target_crs::GeoFormatTypes.CoordinateReferenceSystemFormat,
    res::Float64
)::GI.Wrappers.Polygon
    lon_dist = meters_to_degrees(x_dist, lat)
    xs = (lon - lon_dist / 2, lon + lon_dist / 2)
    lat_dist = meters_to_degrees(y_dist, lat)
    ys = (lat - lat_dist / 2, lat + lat_dist / 2)

    search_plot = create_poly(create_bbox(xs, ys), target_crs)
    geom_buff = GO.buffer(search_plot, res)

    return geom_buff
end

"""
    closest_reef_edge(
        pixel::GeometryBasics.Point{2, Float64},
        reef_lines::Vector{GeometryBasics.Line{2, Float64}}
    )::Vector{Tuple{Float64, Float64}}

Find the nearest line in `reef_lines` to a point `pixel`.

# Arguments
- `pixel` : Target point geometry.
- `reef_lines` : Vector containing lines for comparison.

# Returns
Coordinates of the reef edge line that is closest to the target `pixel`. Returned in Tuples.
"""
function closest_reef_edge(
    pixel::GeometryBasics.Point{2,Float64},
    reef_lines::Vector{GeometryBasics.Line{2,Float64}}
)::Vector{Tuple{Float64,Float64}}
    nearest_edge = reef_lines[argmin(GO.distance.([pixel], reef_lines))]

    return [tuple(x...) for x in nearest_edge]
end

"""
    initial_search_rotation(
        pixel::GeometryBasics.Point{2, Float64},
        geom_buff::GI.Wrappers.Polygon,
        gdf::DataFrame,
        reef_outlines::Vector{Vector{GeometryBasics.Line{2, Float64}}};
        search_buffer::Union{Int64,Float64}=20000.0
    )::Float64

Identifies the closest edge to the target `pixel`/'`geom_buff` and returns the initial rotation
angle required to match the edge line.

# Arguments
- `pixel` : Target point at the center of the search polygon.
- `geom_buff` : Initial search box with zero rotation.
- `gdf` : GeoDataFrame containing a geometry column used for pixel masking.
- `reef_outlines` : Line segments for the outlines of each reef in `gdf`.
- `search_buffer` : Distance to search from pixel to find closest reef.
"""
function initial_search_rotation(
    pixel::GeometryBasics.Point{2,Float64},
    geom_buff::GI.Wrappers.Polygon,
    gdf::DataFrame,
    reef_outlines::Vector{Vector{GeometryBasics.Line{2,Float64}}};
    search_buffer::Union{Int64,Float64}=20000.0
)::Float64
    distance_indices = filter_far_polygons(gdf, pixel, pixel[2], search_buffer)
    reef_lines = reef_outlines[distance_indices]
    reef_lines = reef_lines[
    GO.within.([pixel], gdf[distance_indices, first(GI.geometrycolumns(gdf))])
]
    reef_lines = vcat(reef_lines...)

    # If a pixel is outside of a polygon, use the closest polygon instead.
    if isempty(reef_lines)
        reef_distances =
            GO.distance.(
                [pixel],
                gdf[distance_indices, first(GI.geometrycolumns(gdf))]
            )
        reef_lines = reef_outlines[distance_indices]
        reef_lines = reef_lines[argmin(reef_distances)]
        reef_lines = vcat(reef_lines...)
    end

    edge_line = closest_reef_edge(pixel, reef_lines)

    # Calculate the angle between the two lines
    edge_bearing = line_angle([(0.0, 5.0), (0.0, 0.0)], from_zero(edge_line))
    rot_angle = line_angle(from_zero(find_horizontal(geom_buff)), from_zero(edge_line))
    if edge_bearing > 90
        rot_angle = -rot_angle
    end

    return rot_angle
end

"""
    filter_sites(res_df::DataFrame)::DataFrame

Filter out sites where the qc_flag indicates a suitabiltiy < `surr_threshold` in searching.
Where site polygons are overlapping, keep only the highest scoring site polygon.

# Arguments
- `res_df` : Results DataFrame containing potential site polygons
             (output from `identify_potential_sites()` or `identify_potential_sites_edges()`).

# Returns
DataFrame containing only the highest scoring sites where site polygons intersect, and
containing only sites with scores greater than the `surr_threshold` specified in
`identify_potential_sites_edges()` (default=0.33).
"""
function filter_sites(res_df::DataFrame)::DataFrame
    res_df.row_ID = 1:size(res_df, 1)
    ignore_list = []

    for (row) in eachrow(res_df)
        if row.row_ID ∈ ignore_list
            continue
        end

        if row.qc_flag == 1
            push!(ignore_list, row.row_ID)
            continue
        end

        if any(GO.intersects.([row.poly], res_df[:, :poly]))
            intersecting_polys = res_df[(GO.intersects.([row.poly], res_df[:, :poly])), :]
            if maximum(intersecting_polys.score) <= row.score
                for x_row in
                    eachrow(intersecting_polys[intersecting_polys.row_ID .!= row.row_ID, :])
                    push!(ignore_list, x_row.row_ID)
                end
            else
                push!(ignore_list, row.row_ID)
            end
        end
    end

    rename!(res_df, :poly => :geometry)

    return res_df[res_df.row_ID .∉ [unique(ignore_list)], Not(:qc_flag, :row_ID)]
end

"""
    output_geojson(
        df::DataFrame,
        region::String,
        output_dir::String
    )::Nothing

Writes out GeoJSON file to a target directory. Output file will be located at location:
"`output_dir`/output_sites_`region`.geojson"

# Arguments
- `df` : DataFrame intended for writing to geojson file.
- `region` : Region name for labelling output file.
- `output_dir` : Directory to write geojson file to.
"""
function output_geojson(
    df::DataFrame,
    region::String,
    output_dir::String
)::Nothing
    GDF.write(
        joinpath(
            output_dir,
            "output_sites_$(region).geojson"
        ),
        df;
        crs=GI.crs(first(df.geometry))
    )

    return nothing
end

"""
    identify_search_pixels(input_raster::Raster, criteria_function)::DataFrame

Identifies all pixels in an input raster that return true for the function `criteria_function`.

# Arguments
- `input_raster` : Raster containing pixels for the target region.
- `criteria_function` : Function that returns a boolean value for each pixel in `input_raster`. Pixels that return true will be targetted in analysis.

# Returns
DataFrame containing indices, lon and lat for each pixel that is intended for further analysis.
"""
function identify_search_pixels(input_raster::Raster, criteria_function)::DataFrame
    pixels = trim(criteria_function(input_raster))
    indices = findall(pixels)
    indices_lon = Vector{Union{Missing,Float64}}(missing, size(indices, 1))
    indices_lat = Vector{Union{Missing,Float64}}(missing, size(indices, 1))

    for (j, index) in enumerate(indices)
        indices_lon[j] = dims(pixels, X)[index[1]]
        indices_lat[j] = dims(pixels, Y)[index[2]]
    end

    return DataFrame(; indices=indices, lon=indices_lon, lat=indices_lat)
end

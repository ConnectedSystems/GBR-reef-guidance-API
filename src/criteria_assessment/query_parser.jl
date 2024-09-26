"""
    parse_criteria_query(qp)::Tuple

Parse criteria values from request query.

Queries should take the form of:
`Depth=-9.0:0.0&Slope=0.0:40.0&Rugosity=0.0:0.0`

# Arguments
- `qp` : Parsed query string from request.

# Returns
Tuple of criteria names, lower bounds, upper bounds
"""
function parse_criteria_query(qp::Dict)::Tuple
    criteria_names = keys(criteria_data_map())
    lbs = []
    ubs = []
    for k in criteria_names
        if k ∉ keys(qp)
            continue
        end

        lb, ub = string.(split(qp[k], ":"))
        push!(lbs, lb)
        push!(ubs, ub)
    end

    return criteria_names, lbs, ubs
end

"""
    remove_rugosity(reg, criteria, lbs, ubs)

Remove rugosity layer from consideration if region is not Townsville.
Rugosity data currently only exists for the Townsville region.
"""
function remove_rugosity(reg, criteria_names, lbs, ubs)

    if !contains(reg, "Townsville")
        # Remove rugosity layer from consideration as it doesn't exist for regions
        # outside of Townsville.
        pos = findfirst(lowercase.(criteria_names) .== "rugosity")
        criteria_names = [cname for (i, cname) in enumerate(criteria_names) if i != pos]
        lbs = [lb for (i, lb) in enumerate(lbs) if i != pos]
        ubs = [ub for (i, ub) in enumerate(ubs) if i != pos]
    end

    return criteria_names, lbs, ubs
end

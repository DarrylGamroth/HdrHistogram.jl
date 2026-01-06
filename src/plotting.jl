function percentile_plot_data(h::AbstractHistogram; ticks_per_half_distance::Int64=5, value_scale::Float64=1.0)
    iter = PercentileIterator(h, ticks_per_half_distance)
    state = iterator_state(iter)
    percentiles = Float64[]
    values = Float64[]
    while iterate!(iter, state)
        v = state.iter_value
        push!(percentiles, percentile_iterated_to(v))
        push!(values, highest_equivalent_value(h, value_iterated_to(v)) / value_scale)
    end
    return percentiles, values
end

function percentile_plot(h::AbstractHistogram; kwargs...)
    error("Plots.jl is not available. Add Plots.jl to use percentile_plot.")
end

function percentile_plot!(plot_obj, h::AbstractHistogram; kwargs...)
    error("Plots.jl is not available. Add Plots.jl to use percentile_plot!.")
end

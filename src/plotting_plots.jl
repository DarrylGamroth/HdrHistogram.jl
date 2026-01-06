using Plots

function percentile_plot(h::AbstractHistogram; ticks_per_half_distance::Int64=5, value_scale::Float64=1.0,
    xlabel::AbstractString="Percentile", ylabel::AbstractString="Value", kwargs...)
    percentiles, values = percentile_plot_data(h; ticks_per_half_distance=ticks_per_half_distance, value_scale=value_scale)
    return plot(percentiles, values; xlabel=xlabel, ylabel=ylabel, kwargs...)
end

function percentile_plot!(plot_obj, h::AbstractHistogram; ticks_per_half_distance::Int64=5, value_scale::Float64=1.0,
    kwargs...)
    percentiles, values = percentile_plot_data(h; ticks_per_half_distance=ticks_per_half_distance, value_scale=value_scale)
    return plot!(plot_obj, percentiles, values; kwargs...)
end

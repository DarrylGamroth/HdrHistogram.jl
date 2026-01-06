module HdrHistogram

using Printf
using Requires

include("abstracthistogram.jl")
include("histogram.jl")
include("atomichistogram.jl")
include("concurrenthistogram.jl")
include("synchronizedhistogram.jl")
include("abstractiterator.jl")
include("histogramiterators.jl")
include("plotting.jl")
include("encoding.jl")
include("logio.jl")
include("logprocessor.jl")
include("writerreaderphaser.jl")
include("intervalrecorder.jl")
include("recorder.jl")

function __init__()
    @require Plots="91a5bcdd-55d7-5caf-9e0b-520d859cae80" include("plotting_plots.jl")
end

end # module HdrHistogram

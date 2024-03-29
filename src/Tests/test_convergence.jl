# I should include a manufactured solution in this

"""
Double the step size to get more precise solutions, and compare the change in
error with the "true" solution (solution using the most steps / smallest step
size).

Error is Frobenius norm of the difference between the "true" and approximate
solutions, with the number of points in time compared taken to be the number
of points in time when using the fewest steps / largest step size.

Note: Plots.scalefontsizes(1.5-2.0) seems appropriate for slideshow

I need a better solution for getting a 'fine-grain solution'. Don't want to do
way more computation than necessary to get the 'true' solution.

Richardson extrapolation seems like a good idea for that.
"""
function get_history_convergence(prob, control, pcof, N_iterations;
        orders=(2, 4, 6, 8), true_history=missing, error_limit=-Inf, n_runs=1,
        kwargs...
    )
    base_nsteps = prob.nsteps
    nsteps_change_factor = 2

    # Copy problem so we can mutate nsteps without altering input
    prob_copy = copy(prob)

    histories = []

    errors_all = Matrix{Float64}(undef, N_iterations, length(orders))
    timing_all = Matrix{Float64}(undef, N_iterations, length(orders))
    timing_stddev_all = Matrix{Float64}(undef, N_iterations, length(orders))
    # Fill with NaN, so that we can break the loop early and still plot, ignoring unfilled values
    errors_all .= NaN
    timing_all .= NaN
    timing_stddev_all .= NaN

    step_sizes = (prob.tf/base_nsteps) ./ [nsteps_change_factor^k for k in 0:N_iterations-1]

    for (j, order) in enumerate(orders)
        errors = Vector{Float64}(undef, N_iterations)
        timing = Vector{Float64}(undef, N_iterations)
        timing_stddev = Vector{Float64}(undef, N_iterations)
        errors .= NaN
        timing .= NaN
        timing_stddev .= NaN


        N_derivatives = div(order, 2)

        println("========================================")
        println("Running Order ", order)
        println("========================================")

        histories_this_order = []

        if ismissing(true_history)
            println("----------------------------------------")
            println("True history not given, using Richardson extrapolation\n")
            println("Calculating solution with base_nsteps=", base_nsteps)
            println("----------------------------------------")
            prob_copy.nsteps = base_nsteps
            base_history = eval_forward(
                prob_copy, control, pcof, order=order;
                saveEveryNsteps=div(prob_copy.nsteps, base_nsteps),
                kwargs...
            )
            # Only include state, not derivatives
            base_history = base_history[:,1,:,:]
            push!(histories_this_order, base_history)
        end


        for k in 1:N_iterations
            nsteps_multiplier = nsteps_change_factor^k
            prob_copy.nsteps = base_nsteps*nsteps_multiplier

            elapsed_times = zeros(n_runs)

            elapsed_times[1] = @elapsed history = eval_forward(
                prob_copy, control, pcof, order=order;
                saveEveryNsteps=div(prob_copy.nsteps, base_nsteps),
                kwargs...

            )
            for rerun_i in 2:n_runs
                elapsed_times[rerun_i] = @elapsed history = eval_forward(
                    prob_copy, control, pcof, order=order;
                    saveEveryNsteps=div(prob_copy.nsteps, base_nsteps),
                    kwargs...
                )
            end
            mean_elapsed_time = sum(elapsed_times)/length(elapsed_times)
            stddev_elapsed_time = sum((elapsed_times .- mean_elapsed_time) .^ 2)
            stddev_elapsed_time /= length(elapsed_times)-1
            stddev_elapsed_time = sqrt(stddev_elapsed_time)


            # Only compare state, not derivatives
            history = history[:,1,:,:]
            push!(histories_this_order, history)

            if ismissing(true_history)
                history_prev = histories_this_order[k]
                error = richardson_extrap_rel_err(history, history_prev, order)
            else
                error = norm(history - true_history)/norm(true_history)
            end

            errors[k] = error
            timing[k] = mean_elapsed_time
            timing_stddev[k] = stddev_elapsed_time

            println("Nsteps = ", prob_copy.nsteps)
            println("Error = ", error)
            println("Mean Elapsed Time = ", mean_elapsed_time)
            println("StdDev Elapsed Time = ", stddev_elapsed_time)
            println("----------------------------------------")

            # Break once we reach high enough precision
            if error < error_limit 
                break
            end
            # If we are reasonably precise, break if the error increases twice
            # (numerical saturation)
            if k > 2
                if (error < 1e-4) && (error > errors[k-1]) && (errors[k-1] > errors[k-2])
                    break
                end
            end
        end

        push!(histories, histories_this_order)

        errors_all[:,j] .= errors
        timing_all[:,j] .= timing
        timing_stddev_all[:,j] .= timing_stddev
        #errors_all[:,length(orders)+j] .= order_line
    end

    #return step_sizes, errors_all, timing_all, timing_stddev_all
    return step_sizes, errors_all, timing_all, timing_stddev_all, histories
end



function plot_history_convergence(step_sizes, errors_all, timing_all, timing_stddev_all; fontsize=16, kwargs...) 
    
    pl_stepsize = Plots.plot(ylabel="Log₁₀(Rel Err)", fontsize=fontsize)
    pl_timing = Plots.plot(ylabel="Log₁₀(Rel Err)", fontsize=fontsize)
    Plots.plot!(pl_stepsize, xlabel="Log₁₀(Step Size Δt)")
    Plots.plot!(pl_timing, xlabel="Log₁₀(Elapsed Time) (s)")

    yticks = -15:15 
    Plots.plot!(pl_stepsize, yticks=yticks, legend=:outerright)
    Plots.plot!(pl_timing, yticks=yticks, legend=:outerright)

    plot_history_convergence!(pl_stepsize, pl_timing,
        step_sizes, errors_all, timing_all, timing_stddev_all;
        kwargs...
    )
    # Add the lines here

    stepsize_xlims = collect(Plots.xlims(pl_stepsize))
    timing_xlims   = collect(Plots.xlims(pl_timing))
    Plots.plot!(pl_stepsize, stepsize_xlims, [-7, -7], linecolor=:red, label="Target Error")
    Plots.plot!(pl_timing, timing_xlims, [-7, -7], linecolor=:red, label="Target Error")

    return pl_stepsize, pl_timing
end



function plot_history_convergence!(pl_stepsize, pl_timing, step_sizes, errors_all, timing_all, timing_stddev_all;
        orders=(2, 4, 6, 8, 10), include_orderlines=false, fontsize=16, orderline_offset=0,
        labels=missing, marker=:circle, colors=missing, lw=2, markersize=5
    )

    N_orders = size(errors_all, 2)

    if ismissing(labels)
        labels = ["Order=$order" for order in orders]
    end
    labels = reshape(labels, 1, :) # Labels must be row matrix

    if ismissing(colors)
        colors = collect(Plots.theme_palette(:default))
        colors = colors[1:N_orders]
        colors = reshape(colors, 1, :)
    end

    Plots.plot!(pl_timing, log10.(timing_all), log10.(errors_all), marker=marker,
                markersize=markersize, labels=labels, linealpha=0.5, color=colors, lw=lw)
    Plots.plot!(pl_stepsize, log10.(step_sizes), log10.(errors_all), marker=marker,
                markersize=markersize, labels=labels, color=colors, lw=lw)


    # Add order lines
    if include_orderlines
        # If a single number is given, fill vector with that number
        if length(orderline_offset) == 1
            orderline_offset = ones(length(orders)) .* orderline_offset
        end
        @assert length(orderline_offset) == length(orders)

        # Order lines may extend too far down. Save the old limits so I can fix the window size back.
        old_ylims = Plots.ylims(pl_stepsize)

        linestyle_list = (:solid, :dash, :dot, :dashdot)
        for n in 1:N_orders
            order = orders[n]
            order_line = step_sizes .^ order
            order_line .*= 2 * errors_all[1,n]/order_line[1] # Adjust vertical position to match data, with small offset for visibility

            linestyle_index = n % length(linestyle_list)
            if linestyle_index > 0
                linestyle = linestyle_list[linestyle_index]
            else 
                linestyle = linestyle_list[end]
            end

            Plots.plot!(
                pl_stepsize, log10.(step_sizes), log10.(order_line) .+ orderline_offset[n],
                label="Δt^$order", linecolor=:black, linestyle=linestyle
            )
        end

        Plots.ylims!(pl_stepsize, old_ylims...)
        Plots.plot!(pl_stepsize, legend=:outerright)
    end
    return pl_stepsize, pl_timing
end

"""
Given solutions with stepsize h and 2h, which have error of order 'order', compute
an order 'order+1' estimate in the error of Aₕ 
"""
function richardson_extrap_rel_err(Aₕ, A₂ₕ, order)
    richardson_sol = richardson_extrap_sol(Aₕ, A₂ₕ, order)
    return norm(richardson_sol - Aₕ)/norm(richardson_sol)
end

"""
Given solutions with stepsize h and 2h, which have error of order 'order', compute
an order 'order+1' solution 
"""
function richardson_extrap_sol(Aₕ, A₂ₕ, order)
    n = order
    return ((2^n)*Aₕ - A₂ₕ)/(2^n-1)
end

"""
Given CPU times and relative errors, estimate the CPU time which would give a
relative error of 1e-7
"""
function get_runtime_ratios(errors_all, timing_all, errors_juqbox, timing_juqbox,
                            target_error=1e-7)

    errors_log = log10.(errors_all)
    timing_log = log10.(timing_all)

    errors_juqbox_log = log10.(errors_juqbox)
    timing_juqbox_log = log10.(timing_juqbox)

    juqbox_time = 10.0 ^ find_target_y(
        timing_juqbox_log[:,1], errors_juqbox_log[:,1], log10(target_error)
    )


    N = size(errors_all, 2)
    runtime_ratios = zeros(N)

    for n in 1:N
        runtime_ratios[n] = 10.0 ^ find_target_y(
            timing_log[:,n], errors_log[:,n], log10(target_error)
        )
        runtime_ratios[n] /= juqbox_time
    end

    return runtime_ratios 
end


"""
Assuming a linear interpolation between subsequent points, find the value of x
which is expected to yield the target_y. (also generally assumes that the ys are
monotonically decreasing, or at least aroudn the area of target_y)
"""
function find_target_y(xs, ys, target_y)
    @assert length(xs) == length(ys)
    N = length(xs)

    upper_index = -1
    for n in 1:N
        y = ys[n]
        if y > target_y
            upper_index = n
        end
    end
    lower_index = upper_index-1

    x1 = xs[upper_index]
    x2 = xs[lower_index]
    y1 = ys[upper_index]
    y2 = ys[lower_index]

    m = (y2-y1)/(x1-x2)

    target_x = x1 + ((target_y - y1)/m)

    return target_x
end


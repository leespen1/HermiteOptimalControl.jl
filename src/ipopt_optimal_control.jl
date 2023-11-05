import Ipopt

# First set up constraint, jacobian, and hessian functions. We will not be
# using those in our optimization process (yet), so they all just return
# nothing.
#
# I have added exclamation points because their purpose really is to mutate
# vectors. They don't return anything meaningful.

"""
Unused, but need a function to provide to ipopt.
"""
function dummy_eval_g!(x::Vector{Float64}, g::Vector{Float64})
    return
end

"""
Unused, but need a function to provide to ipopt.
"""
function dummy_eval_jacobian_g!(
    x::Vector{Float64},
    rows::Vector{Int32},
    cols::Vector{Int32},
    values::Union{Nothing,Vector{Float64}},
)
    return
end

"""
Unused, but need a function to provide to ipopt.
"""
function dummy_eval_hessian!(
        x::Vector{Float64},
        rows::Vector{Int32},
        cols::Vector{Int32},
        obj_factor::Float64,
        lambda::Vector{Float64},
        values::Union{Nothing,Vector{Float64}},
    )

    return 
end

"""
Unused, but need a function to provide to ipopt.
"""
function optimize_gate(
        schro_prob::SchrodingerProb{M, VM}, control::Control,
        pcof_init::AbstractVector{Float64}, target::VM;
        order=4,
        pcof_L=missing,
        pcof_U=missing
    ) where {V<:AbstractVector{Float64}, VM<:AbstractVecOrMat{Float64}, M<:AbstractMatrix{Float64}}

    # Right now I am unnecessarily doing a full forward evolution to compute the
    # infidelity, when this should be done already in the gradient computation.
    function eval_f(pcof::Vector{Float64})
        println(pcof)
        history = eval_forward(schro_prob, control, pcof, order=order)
        QN = @view history[:,end,:]
        return infidelity(QN, target, schro_prob.N_ess_levels)
    end

    function eval_grad_f!(pcof::Vector{Float64}, grad_f::Vector{Float64})
        grad_f .= discrete_adjoint(schro_prob, control, pcof, target, order=order)
    end


    if ismissing(pcof_L)
        pcof_L = -ones(control.N_coeff)
    end
    if ismissing(pcof_U)
        pcof_U = ones(control.N_coeff)
    end

    N_constraints = 0
    g_L = Vector{Float64}()
    g_U = Vector{Float64}()

    nele_jacobian = 0
    nele_hessian = 0

    ipopt_prob = Ipopt.CreateIpoptProblem(
        control.N_coeff,
        pcof_L,
        pcof_U,
        N_constraints,
        g_L,
        g_U,
        nele_jacobian,
        nele_hessian,
        eval_f,
        dummy_eval_g!,
        eval_grad_f!,
        dummy_eval_jacobian_g!,
        dummy_eval_hessian!,
    )

    maxIter = 50
    lbfgsMax = 200
    coldStart = true
    acceptTol = 1e-5 # Num
    ipTol = 1e-5
    acceptIter = 5 # Number of "succesful" iterations before calling it quits

    #Ipopt.AddIpoptIntOption(ipopt_prob, "acceptable_iter", acceptIter)
    Ipopt.AddIpoptStrOption(ipopt_prob, "hessian_approximation", "limited-memory"); # Use L-BFGS, approximate hessian
    Ipopt.AddIpoptIntOption(ipopt_prob, "limited_memory_max_history", lbfgsMax);
    Ipopt.AddIpoptIntOption(ipopt_prob, "max_iter", maxIter);
    Ipopt.AddIpoptNumOption(ipopt_prob, "tol", ipTol);
    Ipopt.AddIpoptNumOption(ipopt_prob, "acceptable_tol", acceptTol);
    Ipopt.AddIpoptIntOption(ipopt_prob, "acceptable_iter", acceptIter);
    Ipopt.AddIpoptStrOption(ipopt_prob, "jacobian_approximation", "exact");
    #Ipopt.AddIpoptStrOption(ipopt_prob, "derivative_test", "first-order") # What does this do?
    Ipopt.AddIpoptStrOption(ipopt_prob, "derivative_test", "none") # Not sure what derivative test does, but it takes a minute.

    #=
    addOption(ipopt_prob, "hessian_approximation", "limited-memory");
    addOption(ipopt_prob, "limited_memory_max_history", lbfgsMax); # Max number of past iterations for hessian approximation
    addOption(ipopt_prob, "jacobian_approximation", "exact");
    =#

    ipopt_prob.x .= pcof_init
    solvestat = Ipopt.IpoptSolve(ipopt_prob)
    # solvestat I think is stored in ipopt_prob as 'status'

    return ipopt_prob
end

#=
"""
    pcof = run_optimizer(params, pcof0, maxAmp; maxIter=50, lbfgsMax=200, coldStart=true, ipTol=1e-5, acceptTol=1e-5, acceptIter=15, print_level=5, print_frequency_iter=1, nodes=[0.0], weights=[1.0])

Call IPOPT to  optimizize the control functions.

# Arguments
- `params:: objparams`: Struct with problem definition
- `pcof0:: Vector{Float64}`: Initial guess for the control vector
- `maxAmp:: Vector{Float64}`: Maximum amplitude for each control function (size Nctrl)
- `maxIter:: Int64`: (Optional-kw) Maximum number of iterations to be taken by optimizer
- `lbfgsMax:: Int64`: (Optional-kw) Maximum number of past iterates for Hessian approximation by L-BFGS
- `coldStart:: Bool`: (Optional-kw) true (default): start a new optimization with ipopt; false: continue a previous optimization
- `ipTol:: Float64`: (Optional-kw) Desired convergence tolerance (relative)
- `acceptTol:: Float64`: (Optional-kw) Acceptable convergence tolerance (relative)
- `acceptIter:: Int64`: (Optional-kw) Number of acceptable iterates before triggering termination
- `print_level:: Int64`: (Optional-kw) Ipopt verbosity level (5)
- `print_frequency_iter:: Int64`: (Optional-kw) Ipopt printout frequency (1)
- `nodes:: AbstractArray`: (Optional-kw) Risk-neutral opt: User specified quadrature nodes on the interval [-ϵ,ϵ] for some ϵ
- `weights:: AbstractArray`: (Optional-kw) Risk-neutral opt: User specified quadrature weights on the interval [-ϵ,ϵ] for some ϵ
- `derivative_test:: Bool`: (Optional-kw) Set to true to check the gradient against a FD approximation (default is false)
"""
=#

function eval_forward(prob::SchrodingerProb, α=missing; order=2, return_time_derivatives=false)
    if order == 2
        return eval_forward_order2(prob, α, return_time_derivatives=return_time_derivatives)
    elseif order == 4
        return eval_forward_order4(prob, α, return_time_derivatives=return_time_derivatives)
    end
    throw("Invalid order: $order")
end


function eval_forward_order2(prob::SchrodingerProb, α=missing;
        return_time_derivatives=false)
    Ks = prob.Ks
    Ss = prob.Ss
    a_plus_adag = prob.a_plus_adag
    a_minus_adag = prob.a_minus_adag
    p = prob.p
    q = prob.q
    u0 = prob.u0
    v0 = prob.v0
    tf = prob.tf
    nsteps = prob.nsteps

    t = 0
    dt = tf/nsteps

    uv = zeros(4)
    copyto!(uv,1,u0,1,2)
    copyto!(uv,3,v0,1,2)
    uv_history = Matrix{Float64}(undef,4,1+nsteps)
    uv_history[:,1] .= uv
    utvt_history = Matrix{Float64}(undef,4,1+nsteps)

    RHSu::Vector{Float64} = zeros(2)
    RHSv::Vector{Float64} = zeros(2)
    RHS::Vector{Float64} = zeros(4)

    u = copy(u0)
    v = copy(v0)
    ut = zeros(2)
    vt = zeros(2)

    # Order 2
    for n in 0:nsteps-1
        utvt!(ut, vt, u, v,
              Ks, Ss, a_plus_adag, a_minus_adag,
              p, q, t, α)

        utvt_history[1:2,1+n] .= ut
        utvt_history[3:4,1+n] .= vt

        copy!(RHSu,u)
        axpy!(0.5*dt,ut,RHSu)

        copy!(RHSv,v)
        axpy!(0.5*dt,vt,RHSv)

        copyto!(RHS,1,RHSu,1,2)
        copyto!(RHS,3,RHSv,1,2)

        t += dt

        LHS_map = LinearMap(
            uv -> LHS_func(ut, vt, uv[1:2], uv[3:4],
                           Ks, Ss, a_plus_adag, a_minus_adag,
                           p, q, t, α, dt),
            4,4
        )

        gmres!(uv, LHS_map, RHS, abstol=1e-15, reltol=1e-15)
        uv_history[:,1+n+1] .= uv
        u = uv[1:2]
        v = uv[3:4]
    end

    # One last time, for utvt history at final time
    utvt!(ut, vt, u, v,
          Ks, Ss, a_plus_adag, a_minus_adag,
          p, q, t, α)

    utvt_history[1:2,1+nsteps] .= ut
    utvt_history[3:4,1+nsteps] .= vt

    if return_time_derivatives
        return cat(uv_history, utvt_history, dims=3)
    end
    return uv_history
end

function eval_forward_order4(prob::SchrodingerProb, α=missing;
        return_time_derivatives=false)
    Ks = prob.Ks
    Ss = prob.Ss
    a_plus_adag = prob.a_plus_adag
    a_minus_adag = prob.a_minus_adag
    p = prob.p
    q = prob.q
    dpdt = prob.dpdt
    dqdt = prob.dqdt
    u0 = prob.u0
    v0 = prob.v0
    tf = prob.tf
    nsteps = prob.nsteps

    t = 0
    dt = tf/nsteps

    uv = zeros(4)
    copyto!(uv,1,u0,1,2)
    copyto!(uv,3,v0,1,2)
    uv_history = Matrix{Float64}(undef,4,1+nsteps)
    uv_history[:,1] .= uv
    utvt_history = Matrix{Float64}(undef,4,1+nsteps)
    uttvtt_history = Matrix{Float64}(undef,4,1+nsteps)

    RHSu::Vector{Float64} = zeros(2)
    RHSv::Vector{Float64} = zeros(2)
    RHS::Vector{Float64} = zeros(4)

    u = copy(u0)
    v = copy(v0)
    ut = zeros(2)
    vt = zeros(2)
    utt = zeros(2)
    vtt = zeros(2)

    # Order 4
    for n in 0:nsteps-1
        utvt!(ut, vt, u, v,
              Ks, Ss, a_plus_adag, a_minus_adag,
              p, q, t, α)
        uttvtt!(utt, vtt, ut, vt, u, v,
                Ks, Ss, a_plus_adag, a_minus_adag,
                p, q, dpdt, dqdt, t, α)

        utvt_history[1:2,1+n] .= ut
        utvt_history[3:4,1+n] .= vt
        uttvtt_history[1:2,1+n] .= utt
        uttvtt_history[3:4,1+n] .= vtt

        weights = [1,1/3]
        copy!(RHSu,u)
        axpy!(0.5*dt*weights[1],ut,RHSu)
        axpy!(0.25*dt^2*weights[2],utt,RHSu)

        copy!(RHSv,v)
        axpy!(0.5*dt*weights[1],vt,RHSv)
        axpy!(0.25*dt^2*weights[2],vtt,RHSv)

        copyto!(RHS,1,RHSu,1,2)
        copyto!(RHS,3,RHSv,1,2)

        t += dt

        LHS_map = LinearMap(
            uv -> LHS_func_order4(utt, vtt, ut, vt, uv[1:2], uv[3:4],
                                  Ks, Ss, a_plus_adag, a_minus_adag,
                                  p, q, dpdt, dqdt, t, α, dt),
            4,4
        )

        gmres!(uv, LHS_map, RHS)
        uv_history[:,1+n+1] .= uv
        u = uv[1:2]
        v = uv[3:4]
    end

    # One last time, for utvt history at final time
    utvt!(ut, vt, u, v,
          Ks, Ss, a_plus_adag, a_minus_adag,
          p, q, t, α)
    uttvtt!(utt, vtt, ut, vt, u, v,
            Ks, Ss, a_plus_adag, a_minus_adag,
            p, q, dpdt, dqdt, t, α)

    utvt_history[1:2,1+nsteps] .= ut
    utvt_history[3:4,1+nsteps] .= vt
    uttvtt_history[1:2,1+nsteps] .= utt
    uttvtt_history[3:4,1+nsteps] .= vtt

    if return_time_derivatives
        return cat(uv_history, utvt_history, uttvtt_history, dims=3)
    end
    return uv_history
end


function eval_forward_forced(prob::SchrodingerProb, forcing_ary::Array{Float64,3}, α=missing; order=2)
    if order == 2
        return eval_forward_forced_order2(prob, forcing_ary, α)
    elseif order == 4
        return eval_forward_forced_order4(prob, forcing_ary, α)
    end

    throw("Invalid Order: $order")
end

"""
Evolve schrodinger problem with forcing applied, and forcing given as an array
of forces at each discretized point in time.

Maybe I should also do a one with forcing functions as well.
"""
function eval_forward_forced_order2(prob::SchrodingerProb, forcing_ary::Array{Float64,3}, α=missing)
    Ks = prob.Ks
    Ss = prob.Ss
    a_plus_adag = prob.a_plus_adag
    a_minus_adag = prob.a_minus_adag
    p = prob.p
    q = prob.q
    u0 = prob.u0
    v0 = prob.v0
    tf = prob.tf
    nsteps = prob.nsteps

    t = 0
    dt = tf/nsteps

    uv = zeros(4)
    copyto!(uv,1,u0,1,2)
    copyto!(uv,3,v0,1,2)
    uv_history = Matrix{Float64}(undef,4,1+nsteps)
    uv_history[:,1] .= uv

    RHSu::Vector{Float64} = zeros(2)
    RHSv::Vector{Float64} = zeros(2)
    RHS_uv::Vector{Float64} = zeros(4)

    u = copy(u0)
    v = copy(v0)
    ut = zeros(2)
    vt = zeros(2)
    utt = zeros(2)
    vtt = zeros(2)

    for n in 0:nsteps-1
        utvt!(ut, vt, u, v,
              Ks, Ss, a_plus_adag, a_minus_adag,
              p, q, t, α)
        copy!(RHSu,u)
        axpy!(0.5*dt,ut,RHSu)

        copy!(RHSv,v)
        axpy!(0.5*dt,vt,RHSv)

        copyto!(RHS_uv,1,RHSu,1,2)
        copyto!(RHS_uv,3,RHSv,1,2)

        axpy!(0.5*dt,forcing_ary[:,1+n,1], RHS_uv)
        axpy!(0.5*dt,forcing_ary[:,1+n+1,1], RHS_uv)

        t += dt

        LHS_map = LinearMap(
            uv -> LHS_func(ut, vt, uv[1:2], uv[3:4],
                           Ks, Ss, a_plus_adag, a_minus_adag,
                           p, q, t, α, dt),
            4,4
        )

        gmres!(uv, LHS_map, RHS_uv, abstol=1e-15, reltol=1e-15)
        uv_history[:,1+n+1] .= uv
        u = uv[1:2]
        v = uv[3:4]
    end
    
    return uv_history
end



function eval_forward_forced_order4(prob::SchrodingerProb, forcing_ary::Array{Float64,3}, α=missing)
    Ks = prob.Ks
    Ss = prob.Ss
    a_plus_adag = prob.a_plus_adag
    a_minus_adag = prob.a_minus_adag
    p = prob.p
    q = prob.q
    dpdt = prob.dpdt
    dqdt = prob.dqdt
    u0 = prob.u0
    v0 = prob.v0
    tf = prob.tf
    nsteps = prob.nsteps

    t = 0
    dt = tf/nsteps

    uv = zeros(4)
    copyto!(uv,1,u0,1,2)
    copyto!(uv,3,v0,1,2)
    uv_history = Matrix{Float64}(undef,4,1+nsteps)
    uv_history[:,1] .= uv

    RHSu::Vector{Float64} = zeros(2)
    RHSv::Vector{Float64} = zeros(2)
    RHS_uv::Vector{Float64} = zeros(4)

    u = copy(u0)
    v = copy(v0)
    ut = zeros(2)
    vt = zeros(2)
    utt = zeros(2)
    vtt = zeros(2)

    weights = [1,1/3]
    weights_LHS = [1,-1/3]
    for n in 0:nsteps-1
        # First time derivative at current timestep
        utvt!(ut, vt, u, v,
              Ks, Ss, a_plus_adag, a_minus_adag,
              p, q, t, α)
        axpy!(1.0,forcing_ary[1:2,1+n,1], ut)
        axpy!(1.0,forcing_ary[3:4,1+n,1], vt)

        # Second time derivative at current timestep
        uttvtt!(utt, vtt, ut, vt, u, v,
                Ks, Ss, a_plus_adag, a_minus_adag,
                p, q, dpdt, dqdt, t, α)
        axpy!(1.0,forcing_ary[1:2,1+n,2], utt)
        axpy!(1.0,forcing_ary[3:4,1+n,2], vtt)

        # Accumulate RHS (current time contributions)
        copy!(RHSu,u)
        axpy!(0.5*dt*weights[1],ut,RHSu)
        axpy!(0.25*dt^2*weights[2],utt,RHSu)

        copy!(RHSv,v)
        axpy!(0.5*dt*weights[1],vt,RHSv)
        axpy!(0.25*dt^2*weights[2],vtt,RHSv)

        # Add in forcing from first time derivative at next timestep
        axpy!(0.5*dt*weights_LHS[1],forcing_ary[1:2,1+n+1,1], RHSu)
        axpy!(0.5*dt*weights_LHS[1],forcing_ary[3:4,1+n+1,1], RHSv)

        # Add in forcing from second time derivative at next timestep
        axpy!(0.25*dt^2*weights_LHS[2],forcing_ary[1:2,1+n+1,2], RHSu)
        axpy!(0.25*dt^2*weights_LHS[2],forcing_ary[3:4,1+n+1,2], RHSv)

        # Advance time to next point
        t += dt

        # Don't forget to differentiate the forcing from the first derivative
        utvt!(ut, vt, forcing_ary[1:2,1+n+1,1], forcing_ary[3:4,1+n+1,1],
              Ks, Ss, a_plus_adag, a_minus_adag,
              p, q, t, α)

        axpy!(0.25*dt^2*weights_LHS[2], ut, RHSu)
        axpy!(0.25*dt^2*weights_LHS[2], vt, RHSv)

        copyto!(RHS_uv,1,RHSu,1,2)
        copyto!(RHS_uv,3,RHSv,1,2)

        LHS_map = LinearMap(
            uv -> LHS_func_order4(utt, vtt, ut, vt, uv[1:2], uv[3:4],
                           Ks, Ss, a_plus_adag, a_minus_adag,
                           p, q, dpdt, dqdt, t, α, dt),
            4,4
        )

        gmres!(uv, LHS_map, RHS_uv, abstol=1e-15, reltol=1e-15)
        uv_history[:,1+n+1] .= uv
        u = uv[1:2]
        v = uv[3:4]
    end
    
    return uv_history
end

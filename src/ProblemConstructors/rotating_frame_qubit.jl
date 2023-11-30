"""
A single qubit in the dispersive limit (e.g. section 2 of JuqBox paper), in the
rotating frame.

Frequencies should be in GHz, and will be multiplied by 2pi to get angular
frequencies in the Hamiltonian.
"""
function rotating_frame_qubit(N_ess_levels::Int, N_guard_levels::Int;
        tf::Float64=1.0, nsteps::Int64=10, detuning_frequency::Float64=1.0,
        self_kerr_coefficient::Float64=1.0
    )

    N_tot_levels = N_ess_levels + N_guard_levels

    a = lowering_operator(N_tot_levels)

    system_sym  = zeros(N_tot_levels, N_tot_levels)
    system_sym .+= 2*pi*detuning_frequency .* (a'*a)
    system_sym .-= (0.5*2*pi*self_kerr_coefficient) .* (a'*a'*a*a)

    system_asym = zeros(N_tot_levels, N_tot_levels)


    sym_operator  = a + a'
    asym_operator = a - a'

    u0, v0 = initial_basis(N_ess_levels, N_guard_levels)

    return SchrodingerProb(
        system_sym, system_asym,
        [sym_operator], [asym_operator],
        u0, v0, 
        tf, nsteps,
        N_ess_levels, N_guard_levels
    )
end

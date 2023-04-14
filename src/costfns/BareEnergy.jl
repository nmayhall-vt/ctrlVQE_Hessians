import ...EnergyFunctions, ...AbstractGradientFunction

import ....Parameters, ....LinearAlgebraTools, ....Devices, ....Evolutions
import ....Operators: StaticOperator, IDENTITY
import ....Bases: BasisType, OCCUPATION

function functions(
    O0::AbstractMatrix,
    ψ0::AbstractVector,
    T::Real,
    device::Devices.Device,
    r::Int;
    algorithm=Evolutions.Rotate(r),
    basis=OCCUPATION,
    frame=IDENTITY,
)
    f = CostFunction(O0, ψ0, T, device, algorithm, basis, frame)
    g = GradientFunction(f, r)
    return f, g
end

struct CostFunction{
    F<:AbstractFloat,
    D<:Devices.Device,
    A<:Evolutions.Algorithm,
    B<:BasisType,
    C<:StaticOperator,
} <: EnergyFunctions.AbstractEnergyFunction
    O0::Matrix{Complex{F}}
    ψ0::Vector{Complex{F}}
    T::F
    device::D
    algorithm::A
    basis::B
    frame::C

    ψ::Vector{Complex{F}}
    OT::Matrix{Complex{F}}
    Ot::Matrix{Complex{F}}

    function CostFunction(
        O0::AbstractMatrix,
        ψ0::AbstractVector,
        T::Real,
        device::D,
        algorithm::A,
        basis::B,
        frame::C,
    ) where {D, A, B, C}
        # INFER FLOAT TYPE AND CONVERT ARGUMENTS
        F = real(promote_type(Float16, eltype(O0), eltype(ψ0), eltype(T)))
        O0 = convert(Array{Complex{F}}, O0)
        ψ0 = convert(Array{Complex{F}}, ψ0)
        T = F(T)

        # CONSTRUCT PRE-ALLOCATED VARIABLES
        ψ = Array{LinearAlgebraTools.cis_type(F)}(undef, size(ψ0))
        OT = copy(O0); Devices.evolve!(frame, device, T, OT)
        Ot = copy(O0)   # TO BE EVOLVED BY t AS NEEDED

        # CREATE OBJECT
        return new{F,D,A,B,C}(O0, ψ0, T, device, algorithm, basis, frame, ψ, OT, Ot)
    end
end

function (f::CostFunction)(x̄::AbstractVector)
    x̄0 = Parameters.values(f.device)
    Parameters.bind(f.device, x̄)
    Evolutions.evolve(
        f.algorithm,
        f.device,
        f.basis,
        f.T,
        f.ψ0;
        result=f.ψ,
    )
    Parameters.bind(f.device, x̄0)
    return EnergyFunctions.evaluate(f, f.ψ)
end

function EnergyFunctions.evaluate(f::CostFunction, ψ::AbstractVector)
    return real(LinearAlgebraTools.expectation(f.OT, ψ))
end

function EnergyFunctions.evaluate(f::CostFunction, ψ::AbstractVector, t::Real)
    f.Ot .= f.O0; Devices.evolve!(f.frame, f.device, t, f.Ot)
    return real(LinearAlgebraTools.expectation(f.Ot, ψ))
end




struct GradientFunction{
    F<:AbstractFloat,
    D<:Devices.Device,
    A<:Evolutions.Algorithm,
    B<:BasisType,
} <: AbstractGradientFunction
    f::CostFunction{F,D,A,B}
    r::Int

    ϕ̄::Matrix{F}

    function GradientFunction(
        f::CostFunction{F,D,A,B},
        r::Int,
    ) where {F, D, A, B}
        ϕ̄ = Array{F}(undef, r+1, Devices.ngrades(f.device))
        return new{F,D,A,B}(f,r,ϕ̄)
    end
end

function (g::GradientFunction)(∇f̄::AbstractVector, x̄::AbstractVector)
    x̄0 = Parameters.values(g.f.device)
    Parameters.bind(g.f.device, x̄)
    Evolutions.gradientsignals(
        g.f.device,
        g.f.basis,
        g.f.T,
        g.f.ψ0,
        g.r,
        g.f.OT;
        result=g.ϕ̄,
        evolution=g.f.algorithm,
    )
    Parameters.bind(g.f.device, x̄0)
    τ, τ̄, t̄ = Evolutions.trapezoidaltimegrid(g.f.T, g.r)
    ∇f̄ .= Devices.gradient(g.f.device, τ̄, t̄, g.ϕ̄)
    return ∇f̄
end
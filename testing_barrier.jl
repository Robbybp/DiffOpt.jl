################################################
# sIPOPT test
################################################

using JuMP
using SparseArrays
using LinearAlgebra
using Ipopt
# using MadNLP
# using KNITRO

############
# Test Case
############

# Define the problem
model = Model(Ipopt.Optimizer)

# Parameters
@variable(model, p ∈ MOI.Parameter(1.0))

# Variables
@variable(model, x) 
@variable(model, y)

# Constraints
@constraint(model, con1, y == sin(p)) # NLP Constraint
@constraint(model, con2, x >= p)
@constraint(model, con3, y >= 0)
@objective(model, Min, (1 - x)^2 + 100 * (y - x^2)^2) # NLP Objective
optimize!(model)

# Check local optimality
termination_status(model)

############
# Retrieve important quantities
############

function _dense_hessian(hessian_sparsity, V, n)
    I = [i for (i, _) in hessian_sparsity]
    J = [j for (_, j) in hessian_sparsity]
    raw = SparseArrays.sparse(I, J, V, n, n)
    return Matrix(
        raw + raw' -
        SparseArrays.sparse(LinearAlgebra.diagm(0 => LinearAlgebra.diag(raw))),
    )
end

# Primal Solution
primal_values = value.([x, y])
dual_values = dual.([con1; con2; con3])
num_vars = length(primal_values)

# `Evaluator`: Object that helps evaluating functions and calculating related values (Hessian, Jacobian, ...)
evaluator = JuMP.MOI.Nonlinear.Evaluator(model.moi_backend.optimizer.model.nlp_model, JuMP.MOI.Nonlinear.SparseReverseMode(), [model.moi_backend.model_to_optimizer_map[index(x)], model.moi_backend.model_to_optimizer_map[index(y)]])

# Define what we will need to evaluate
MOI.initialize(evaluator, [:Grad, :Jac, :Hess, :JacVec])

# Hessian "Symetric" structure values - Placeholder that will be modified to during the evaluation of the hessian
W = [NaN, NaN, NaN]
hessian_sparsity = MOI.hessian_lagrangian_structure(evaluator)

# Modify H with the values for the hessian of the lagrangian
MOI.eval_hessian_lagrangian(evaluator, W, primal_values, 1.0, dual_values)
W = _dense_hessian(hessian_sparsity, W, num_vars)

# Jacobian of the constraints Placeholder
jacobian_sparsity = MOI.jacobian_structure(evaluator)
A = zeros(length(jacobian_sparsity))

# Evaluate Jacobian
MOI.eval_constraint_jacobian(evaluator, A, primal_values)

# TODO: ∇ₓₚL (Partial second derivative of the lagrangian wrt primal solution and parameters) ; 
# TODO: ∇ₚC (partial derivative of the equality constraintswith wrt parameters).

############
# (WORK IN PROGRESS) - Non working code

# Calculate Sensitivity
############
V = diag(dual_values)
X = diag(primal_values)

M = [
    [W A -I];
    [A' 0 0];
    [V 0 X]
]

N = [∇ₓₚL ; ∇ₚC]

# sesitivity of the solution (primal-dual) with respect to the parameter
∂s = inv(M) * N
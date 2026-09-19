%% FETI SOLVER FOR NONLOCAL DIFFUSION PROBLEMS
clear; clc; close all;

%% ==================== PARAMETERS ====================
% Mesh parameters
NX = 40;                    % Number of points in x-direction
NY = 40;                    % Number of points in y-direction
h = 1/NX;                   % Mesh size
area = h^2;                 % Area per node (for scaling)

% Nonlocal parameters
delta = 0.1;                % Horizon
kernel_type = 'constant';   % 'constant', 'fractional', or 'peridynamic'
s = 0.4;                    % Fractional order (for fractional kernel)

% Domain decomposition parameters
numSubX = 2;                % Number of subdomains in x-direction
numSubY = 2;                % Number of subdomains in y-direction
Ns = numSubX * numSubY;      % Total number of subdomains

% Solver parameters
tol = 1e-8;                  % PCG tolerance
maxit = 500;                 % Maximum PCG iterations

fprintf('========================================\n');
fprintf('FETI SOLVER FOR NONLOCAL PROBLEMS\n');
fprintf('========================================\n');
fprintf('Mesh: %d x %d, h = %e\n', NX, NY, h);
fprintf('Horizon: delta = %e\n', delta);
fprintf('Subdomains: %d x %d = %d\n', numSubX, numSubY, Ns);
fprintf('Kernel type: %s\n', kernel_type);
fprintf('========================================\n\n');

%% ==================== STEP 1: MESH GENERATION ====================
fprintf('Step 1: Generating mesh...\n');

% Create mesh grid
[x, y] = meshgrid(linspace(0, 1, NX), linspace(0, 1, NY));
nodes = [x(:) y(:)];
numNodes = size(nodes, 1);

% Create triangulation for visualization
tri = delaunay(nodes(:,1), nodes(:,2));

% Identify Dirichlet boundary nodes (Γ_D)
tol_boundary = 1e-10;
isDirichlet = (nodes(:,1) <= tol_boundary) | (nodes(:,1) >= 1 - tol_boundary) | ...
              (nodes(:,2) <= tol_boundary) | (nodes(:,2) >= 1 - tol_boundary);
dirichlet_nodes = find(isDirichlet);
free_nodes = find(~isDirichlet);

fprintf('  Total nodes: %d\n', numNodes);
fprintf('  Dirichlet nodes: %d\n', length(dirichlet_nodes));
fprintf('  Free nodes: %d\n', length(free_nodes));

%% ==================== STEP 2: DOMAIN DECOMPOSITION ====================
fprintf('\nStep 2: Domain decomposition with overlap...\n');

% Create non-overlapping subdomains (Ω̃_k)
[subdomains_nonoverlap, ~] = partition_nonoverlapping(nodes, numSubX, numSubY);

% Extend to overlapping subdomains with thickness δ/2
[subdomains, overlap_regions] = create_overlapping_subdomains(...
    nodes, subdomains_nonoverlap, delta, h);

fprintf('  Number of subdomains: %d\n', Ns);

%% ==================== STEP 3: OVERLAP COUNTER ζ ====================
fprintf('\nStep 3: Computing overlap counter ζ(x,y)...\n');

% Build sparse matrix C: C(i,k) = 1 if node i belongs to subdomain k
C = sparse(numNodes, Ns);
for s = 1:Ns
    C(subdomains{s}, s) = 1;
end

% Compute ζ(x_i, x_j) = (C * C')_ij
zeta_matrix = C * C';

% ζ_F(x) for the forcing term (counts subdomains containing x)
zeta_F = full(sum(C, 2));

fprintf('  Overlap counts range: %d to %d\n', min(zeta_F), max(zeta_F));

%% ==================== STEP 4: IDENTIFY FLOATING SUBDOMAINS ====================
fprintf('\nStep 4: Identifying floating subdomains...\n');

floating_subdomains = false(Ns, 1);
Gamma_k = cell(Ns, 1);      % Interface regions Γ_k
Omega_k = cell(Ns, 1);      % Interior regions Ω_k

for s = 1:Ns
    % Γ_k = subdomain ∩ Γ (Dirichlet boundary)
    Gamma_k{s} = intersect(subdomains{s}, dirichlet_nodes);
    
    % Floating subdomain if it has no Dirichlet nodes
    floating_subdomains(s) = isempty(Gamma_k{s});
    
    % Ω_k = interior of subdomain (nodes not on interface)
    % Interface nodes are those shared with other subdomains
    temp_interface = [];
    for t = 1:Ns
        if t ~= s
            temp_interface = union(temp_interface, ...
                intersect(subdomains{s}, subdomains{t}));
        end
    end
    Omega_k{s} = setdiff(subdomains{s}, temp_interface);
end

fprintf('  Floating subdomains: %d\n', sum(floating_subdomains));
fprintf('  Non-floating subdomains: %d\n', Ns - sum(floating_subdomains));

%% ==================== STEP 5: ASSEMBLE SUBDOMAIN MATRICES ====================
fprintf('\nStep 5: Assembling subdomain matrices in parallel...\n');

% Manufactured solution and forcing term
u_exact_fun = @(x,y) x.^2 .* y + y.^2;
g_fun = @(x,y) u_exact_fun(x,y);   % Dirichlet data
% Forcing term for constant kernel (with scaling to match local Laplacian)
f_source = @(x,y) -(2*y + 2);      % Since u_xx = 0, u_yy = 2 -> -Laplace = -2

% Initialize cell arrays for subdomain data
A_k = cell(Ns, 1);          % Subdomain stiffness matrices
f_k = cell(Ns, 1);          % Subdomain load vectors
Z_k = cell(Ns, 1);          % Nullspace matrices
idx_map = cell(Ns, 1);      % Maps local to global indices

% Cell arrays for storing node classifications
interior_nodes = cell(Ns, 1);    % Interior node indices (local)
interface_nodes = cell(Ns, 1);   % Interface node indices (local)
dirichlet_nodes_local = cell(Ns, 1); % Dirichlet node indices (local)

for s = 1:Ns
    % Get local nodes
    local_nodes_global = subdomains{s};
    Nk = length(local_nodes_global);
    
    % Create local to global mapping
    idx_map{s} = local_nodes_global;
    
    % Initialize local matrices
    A_local = sparse(Nk, Nk);
    f_local = zeros(Nk, 1);
    
    % Build interaction lists for efficiency
    interaction_pairs = cell(Nk, 1);
    for i = 1:Nk
        xi = nodes(local_nodes_global(i), :);
        dist = sqrt((nodes(local_nodes_global, 1) - xi(1)).^2 + ...
                    (nodes(local_nodes_global, 2) - xi(2)).^2);
        interaction_pairs{i} = find(dist < delta & dist > 0);
    end
    
    % Assemble stiffness matrix with weighting by ζ_A^{-1}
    for i = 1:Nk
        xi = nodes(local_nodes_global(i), :);
        global_i = local_nodes_global(i);
        
        for j_idx = 1:length(interaction_pairs{i})
            j = interaction_pairs{i}(j_idx);
            global_j = local_nodes_global(j);
            
            xj = nodes(global_j, :);
            dist = norm(xi - xj);
            
            gamma_val = compute_kernel(dist, delta, kernel_type, s);
            
            if global_i <= size(zeta_matrix, 1) && global_j <= size(zeta_matrix, 2)
                zeta_val = zeta_matrix(global_i, global_j);
            else
                zeta_val = 1;
            end
            
            if zeta_val > 0
                weight = 1 / zeta_val;
                A_local(i, i) = A_local(i, i) + gamma_val * weight;
                A_local(i, j) = A_local(i, j) - gamma_val * weight;
            end
        end
        
        % RHS with weighting by ζ_F^{-1}
        if global_i <= length(zeta_F)
            zeta_F_val = zeta_F(global_i);
            if zeta_F_val > 0
                f_local(i) = f_source(xi(1), xi(2)) / zeta_F_val;
            else
                f_local(i) = f_source(xi(1), xi(2));
            end
        else
            f_local(i) = f_source(xi(1), xi(2));
        end
    end
    
    % Scale by area (h^2) to approximate integral
    A_local = A_local * area;
    f_local = f_local * area;
    
    % -------------------------------
    % ENFORCE DIRICHLET CONDITIONS
    % -------------------------------
    if ~isempty(Gamma_k{s})
        [~, local_dir] = ismember(Gamma_k{s}, local_nodes_global);
        local_dir = local_dir(local_dir > 0);
        for idx = local_dir'
            % Set row and column to zero, diagonal to 1
            A_local(idx, :) = 0;
            A_local(:, idx) = 0;
            A_local(idx, idx) = 1;
            % Set RHS to exact Dirichlet value
            x_node = nodes(local_nodes_global(idx), 1);
            y_node = nodes(local_nodes_global(idx), 2);
            f_local(idx) = g_fun(x_node, y_node);
        end
    end
    
    A_k{s} = A_local;
    f_k{s} = f_local;
    
    % Identify interface nodes (those in overlap regions)
    interface_local = [];
    for t = 1:Ns
        if t ~= s
            shared = intersect(local_nodes_global, subdomains{t});
            [~, loc] = ismember(shared, local_nodes_global);
            interface_local = union(interface_local, loc(loc > 0));
        end
    end
    
    interior_local = setdiff(1:Nk, interface_local);
    
    interior_nodes{s} = interior_local(:);
    interface_nodes{s} = interface_local(:);
    
    % Dirichlet nodes are already fixed, we keep them in the system but
    % they will be treated as known. They should not be part of interface
    % because they are not unknowns. Remove them from interface set.
    if ~isempty(dirichlet_nodes_local{s})
        interface_nodes{s} = setdiff(interface_nodes{s}, dirichlet_nodes_local{s});
    end
    
    if floating_subdomains(s)
        Z_k{s} = ones(Nk, 1);
    else
        Z_k{s} = zeros(Nk, 0);
    end
    
    if mod(s, max(1, floor(Ns/10))) == 0
        fprintf('    Subdomain %d/%d assembled\n', s, Ns);
    end
end

fprintf('  Subdomain matrices assembled successfully\n');
fprintf('  Subdomain sizes range from %d to %d nodes\n', ...
    min(cellfun(@length, idx_map)), max(cellfun(@length, idx_map)));

%% ==================== STEP 6: BUILD GLOBAL CONSTRAINT MATRIX B ====================
fprintf('\nStep 6: Building constraint matrix B...\n');

total_constraints = 0;
constraint_info = {};

for node = 1:numNodes
    containing = find(C(node, :));
    m = length(containing);
    if m >= 2
        for idx = 1:(m-1)
            total_constraints = total_constraints + 1;
            constraint_info{total_constraints} = struct(...
                'node', node, ...
                'sub1', containing(idx), ...
                'sub2', containing(idx+1));
        end
    end
end

fprintf('  Total non-redundant constraints: %d\n', total_constraints);

rows = []; cols = []; vals = [];
for c = 1:total_constraints
    node = constraint_info{c}.node;
    sub1 = constraint_info{c}.sub1;
    sub2 = constraint_info{c}.sub2;
    rows = [rows; c; c];
    cols = [cols; node; node];
    vals = [vals; 1; -1];
end
B = sparse(rows, cols, vals, total_constraints, numNodes);

%% ==================== STEP 7: BUILD COARSE MATRICES ====================
fprintf('\nStep 7: Building coarse matrices...\n');

Z_global = zeros(numNodes, 0);
nullspace_offsets = zeros(Ns+1, 1);
nullspace_offsets(1) = 1;
for s = 1:Ns
    if floating_subdomains(s)
        Z_local = Z_k{s};
        nz = size(Z_local, 2);
        Z_global_block = zeros(numNodes, nz);
        Z_global_block(idx_map{s}, :) = Z_local;
        Z_global = [Z_global, Z_global_block];
        nullspace_offsets(s+1) = nullspace_offsets(s) + nz;
    else
        nullspace_offsets(s+1) = nullspace_offsets(s);
    end
end

G = B * Z_global;
GtG = G' * G + 1e-12 * eye(size(G' * G));
[L_G, p] = chol(GtG, 'lower');
if p > 0
    warning('GtG not positive definite, using pseudo-inverse');
    inv_GtG = pinv(GtG);
else
    inv_GtG = L_G' \ (L_G \ eye(size(GtG)));
end
fprintf('  GtG size: %d x %d\n', size(GtG, 1), size(GtG, 2));

%% ==================== STEP 8: COMPUTE SCHUR COMPLEMENTS ====================
fprintf('\nStep 8: Computing subdomain Schur complements...\n');

S_k = cell(Ns, 1);
apply_Sinv = cell(Ns, 1);
apply_S = cell(Ns, 1);
f_red_k = cell(Ns, 1);

for s = 1:Ns
    A = A_k{s};
    interior = interior_nodes{s};
    interface = interface_nodes{s};
    
    if isempty(interface)
        S_k{s} = sparse(0, 0);
        apply_Sinv{s} = @(x) zeros(0, size(x, 2));
        apply_S{s} = @(x) zeros(0, size(x, 2));
        f_red_k{s} = [];
        continue;
    end
    
    A_II = A(interior, interior) + 1e-12 * speye(length(interior));
    A_IB = A(interior, interface);
    A_BI = A(interface, interior);
    A_BB = A(interface, interface);
    
    [L_II, p] = chol(A_II, 'lower');
    if p > 0
        [L_II, U_II, P_II] = lu(A_II + 1e-10 * speye(size(A_II)));
        apply_invA_II = @(x) U_II \ (L_II \ (P_II * x));
    else
        apply_invA_II = @(x) L_II' \ (L_II \ x);
    end
    
    S = A_BB - A_BI * apply_invA_II(A_IB);
    S_k{s} = S;
    
    if floating_subdomains(s) && ~isempty(interface)
        [U, D] = eig(full(S));
        d = diag(D);
        tol_svd = 1e-10 * max(abs(d));
        d_inv = zeros(size(d));
        d_inv(abs(d) > tol_svd) = 1 ./ d(abs(d) > tol_svd);
        apply_Sinv{s} = @(x) U * (d_inv .* (U' * x));
        apply_S{s} = @(x) S * x;
    else
        [L_S, p] = chol(S, 'lower');
        if p == 0
            apply_Sinv{s} = @(x) L_S' \ (L_S \ x);
        else
            [U, D] = eig(full(S));
            d = diag(D);
            d_inv = 1 ./ (d + 1e-12);
            apply_Sinv{s} = @(x) U * (d_inv .* (U' * x));
        end
        apply_S{s} = @(x) S * x;
    end
    
    f_interior = f_k{s}(interior);
    f_interface = f_k{s}(interface);
    f_red_k{s} = f_interface - A_BI * apply_invA_II(f_interior);
end

fprintf('  Schur complements computed\n');

%% ==================== STEP 9: BUILD GLOBAL OPERATORS ====================
fprintf('\nStep 9: Building global FETI operators...\n');

% Compute e = Z' * f_global
f_global = zeros(numNodes, 1);
for s = 1:Ns
    f_global(idx_map{s}) = f_global(idx_map{s}) + f_k{s};
end
e = Z_global' * f_global;

% Compute S^+ * f_red for each subdomain and assemble global vector
Splus_f_red_global = zeros(numNodes, 1);
for s = 1:Ns
    if ~isempty(interface_nodes{s})
        w_interface = apply_Sinv{s}(f_red_k{s});
        global_iface_nodes = idx_map{s}(interface_nodes{s});
        Splus_f_red_global(global_iface_nodes) = w_interface;
    end
end

% Compute d = B * (S^+ * f_red)
d = B * Splus_f_red_global;

%% ==================== STEP 10: SET UP PROJECTION ====================
fprintf('\nStep 10: Setting up projection...\n');

P_apply = @(x) x - G * (inv_GtG * (G' * x));

% No preconditioner for simplicity (can be added later)
M_inv_apply = [];

%% ==================== STEP 11: INITIAL GUESS ====================
fprintf('\nStep 11: Computing initial Lagrange multiplier...\n');

lambda0 = G * (inv_GtG * e);

%% ==================== STEP 12: SOLVE DUAL SYSTEM ====================
fprintf('\nStep 12: Solving dual system with projected PCG...\n');

F_apply = @(lambda) apply_F(lambda, B, S_k, idx_map, constraint_info, interface_nodes, floating_subdomains);
A_fun = @(lambda) P_apply(F_apply(P_apply(lambda)));

rhs = P_apply(d);

[lambda, flag, relres, iter] = pcg(A_fun, rhs, tol, maxit, M_inv_apply, [], lambda0);

fprintf('  PCG converged in %d iterations, residual = %e\n', iter, relres);

lambda = P_apply(lambda) + lambda0;

%% ==================== STEP 13: COMPUTE NULLSPACE COEFFICIENTS ====================
fprintf('\nStep 13: Computing nullspace coefficients α...\n');

alpha = inv_GtG * (G' * (d - F_apply(lambda)));

%% ==================== STEP 14: RECOVER PRIMAL SOLUTION ====================
fprintf('\nStep 14: Recovering primal solution u...\n');

u_global = zeros(numNodes, 1);
count = zeros(numNodes, 1);

for s = 1:Ns
    local_nodes = idx_map{s};
    interior = interior_nodes{s};
    interface = interface_nodes{s};
    
    if isempty(interface)
        u_local = A_k{s} \ f_k{s};
    else
        A = A_k{s};
        A_II = A(interior, interior) + 1e-12 * speye(length(interior));
        A_IB = A(interior, interface);
        A_BI = A(interface, interior);
        
        % Build B^T * lambda for this subdomain
        B_lambda = zeros(length(local_nodes), 1);
        for i = 1:length(local_nodes)
            global_node = local_nodes(i);
            [c_rows, ~] = find(B(:, global_node));
            if ~isempty(c_rows)
                for c = c_rows'
                    if constraint_info{c}.sub1 == s
                        B_lambda(i) = B_lambda(i) + lambda(c);
                    elseif constraint_info{c}.sub2 == s
                        B_lambda(i) = B_lambda(i) - lambda(c);
                    end
                end
            end
        end
        
        B_lambda_interface = B_lambda(interface);
        
        if floating_subdomains(s)
            u_interface = apply_Sinv{s}(f_red_k{s} - B_lambda_interface);
            % Nullspace correction
            if ~isempty(Z_k{s}) && size(Z_k{s},2) > 0
                start_idx = nullspace_offsets(s);
                nz = nullspace_offsets(s+1) - start_idx;
                alpha_sub = alpha(start_idx:start_idx+nz-1);
                u_interface = u_interface - Z_k{s}(interface, :) * alpha_sub;
            end
        else
            [L_S, p] = chol(S_k{s}, 'lower');
            if p == 0
                u_interface = L_S' \ (L_S \ (f_red_k{s} - B_lambda_interface));
            else
                u_interface = S_k{s} \ (f_red_k{s} - B_lambda_interface);
            end
        end
        
        u_interior = A_II \ (f_k{s}(interior) - A_IB * u_interface - B_lambda(interior));
        
        u_local = zeros(length(local_nodes), 1);
        u_local(interior) = u_interior;
        u_local(interface) = u_interface;
    end
    
    % Accumulate and count
    u_global(local_nodes) = u_global(local_nodes) + u_local;
    count(local_nodes) = count(local_nodes) + 1;
end

% Average using overlap counter (zeta_F)
u_global = u_global ./ count;

% Enforce Dirichlet on global solution (ensure exact match)
for idx = dirichlet_nodes'
    u_global(idx) = g_fun(nodes(idx,1), nodes(idx,2));
end

%% ==================== STEP 15: ERROR ANALYSIS ====================
fprintf('\nStep 15: Computing errors...\n');

x = nodes(:,1);
y = nodes(:,2);
u_exact = u_exact_fun(x, y);

error = abs(u_global - u_exact);
L2_error = sqrt(sum(error.^2) / numNodes);
max_error = max(error);
rel_error = norm(u_global - u_exact) / norm(u_exact);

fprintf('\n========================================\n');
fprintf('ERROR RESULTS\n');
fprintf('========================================\n');
fprintf('L2 error:        %e\n', L2_error);
fprintf('Max error:       %e\n', max_error);
fprintf('Relative error:  %e\n', rel_error);
fprintf('========================================\n');

%% ==================== STEP 16: VISUALIZATION ====================
fprintf('\nStep 16: Generating plots...\n');

figure('Position', [100, 100, 1200, 400]);

subplot(1, 3, 1);
trisurf(tri, nodes(:,1), nodes(:,2), u_global, 'EdgeColor', 'none');
title('FETI Solution');
xlabel('x'); ylabel('y'); zlabel('u');
colorbar;
view(30, 30);

subplot(1, 3, 2);
trisurf(tri, nodes(:,1), nodes(:,2), u_exact, 'EdgeColor', 'none');
title('Exact Solution');
xlabel('x'); ylabel('y'); zlabel('u');
colorbar;
view(30, 30);

subplot(1, 3, 3);
trisurf(tri, nodes(:,1), nodes(:,2), error, 'EdgeColor', 'none');
title('Absolute Error');
xlabel('x'); ylabel('y'); zlabel('error');
colorbar;
view(30, 30);

sgtitle(sprintf('FETI Results: %d subdomains, δ = %.3f', Ns, delta));

figure;
hold on;
colors = lines(Ns);
for s = 1:Ns
    plot(nodes(subdomains{s}, 1), nodes(subdomains{s}, 2), '.', ...
        'Color', colors(s, :), 'MarkerSize', 10);
end
title('Subdomain Decomposition');
xlabel('x'); ylabel('y');
axis equal tight;
hold off;

fprintf('\nFETI solver completed successfully!\n');

%% ==================== HELPER FUNCTIONS ====================

function gamma_val = compute_kernel(dist, delta, kernel_type, s)
    if dist >= delta || dist == 0
        gamma_val = 0;
        return;
    end
    
    switch kernel_type
        case 'constant'
            gamma_val = 3 / (4 * delta^2);
        case 'fractional'
            d = 2;
            scaling = (2 - 2*s) / (pi * delta^(2 - 2*s));
            gamma_val = scaling / (dist^(d + 2*s) + eps);
        case 'peridynamic'
            scaling = 3 / delta^3;
            gamma_val = scaling / (dist^2 + eps);
        otherwise
            error('Unknown kernel type');
    end
end

function [subdomains, overlap] = partition_nonoverlapping(nodes, nx, ny)
    subdomains = cell(nx*ny, 1);
    overlap = cell(nx*ny, 1);
    dx = 1/nx; dy = 1/ny;
    k = 1;
    for i = 1:nx
        for j = 1:ny
            xmin = (i-1)*dx; xmax = i*dx;
            ymin = (j-1)*dy; ymax = j*dy;
            in_sub = find(nodes(:,1) >= xmin & nodes(:,1) <= xmax & ...
                         nodes(:,2) >= ymin & nodes(:,2) <= ymax);
            subdomains{k} = in_sub;
            overlap{k} = in_sub;
            k = k + 1;
        end
    end
end

function [subdomains_overlap, overlap_regions] = create_overlapping_subdomains(...
    nodes, subdomains_nonoverlap, delta, h)
    Ns = length(subdomains_nonoverlap);
    subdomains_overlap = cell(Ns, 1);
    overlap_regions = cell(Ns, 1);
    for s = 1:Ns
        current = subdomains_nonoverlap{s};
        boundary_nodes = find_boundary_nodes(nodes, current);
        for b = 1:length(boundary_nodes)
            node_b = nodes(boundary_nodes(b), :);
            dist = sqrt((nodes(:,1) - node_b(1)).^2 + ...
                        (nodes(:,2) - node_b(2)).^2);
            nearby = find(dist <= delta/2 + h);
            current = union(current, nearby);
        end
        subdomains_overlap{s} = current;
        overlap_regions{s} = setdiff(current, subdomains_nonoverlap{s});
    end
end

function boundary_nodes = find_boundary_nodes(nodes, subdomain_nodes)
    sub_coords = nodes(subdomain_nodes, :);
    try
        k = convhull(sub_coords(:,1), sub_coords(:,2));
        boundary_nodes = subdomain_nodes(k);
    catch
        [~, idx] = min(sub_coords(:,1)); boundary_nodes = subdomain_nodes(idx);
        [~, idx] = max(sub_coords(:,1)); boundary_nodes = [boundary_nodes; subdomain_nodes(idx)];
        [~, idx] = min(sub_coords(:,2)); boundary_nodes = [boundary_nodes; subdomain_nodes(idx)];
        [~, idx] = max(sub_coords(:,2)); boundary_nodes = [boundary_nodes; subdomain_nodes(idx)];
        boundary_nodes = unique(boundary_nodes);
    end
end

function F_lambda = apply_F(lambda, B, S_k, idx_map, constraint_info, interface_nodes, floating_subdomains)
    Bt_lambda = B' * lambda;   % efficient sparse multiplication
    
    Splus_Bt_lambda = zeros(size(Bt_lambda));
    Ns = length(S_k);
    for s = 1:Ns
        local_nodes = idx_map{s};
        interface_local = interface_nodes{s};
        if isempty(interface_local)
            continue;
        end
        Bt_interface = Bt_lambda(local_nodes(interface_local));
        w_interface = apply_Sinv_local(S_k{s}, floating_subdomains(s), Bt_interface);
        Splus_Bt_lambda(local_nodes(interface_local)) = w_interface;
    end
    
    F_lambda = B * Splus_Bt_lambda;
end

function w = apply_Sinv_local(S, is_floating, v)
    if is_floating
        [U, D] = eig(full(S));
        d = diag(D);
        tol = 1e-10 * max(abs(d));
        d_inv = zeros(size(d));
        d_inv(abs(d) > tol) = 1 ./ d(abs(d) > tol);
        w = U * (d_inv .* (U' * v));
    else
        [L, p] = chol(S, 'lower');
        if p == 0
            w = L' \ (L \ v);
        else
            w = S \ v;
        end
    end
end
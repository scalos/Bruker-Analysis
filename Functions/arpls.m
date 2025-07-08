function z = arpls(y, lambda, ratio, itermax)
% arpls: Baseline correction using Asymmetrically Reweighted Penalized Least Squares
% Taken from: https://nirpyresearch.com/two-methods-baseline-correction-spectral-data/
% and translated to matlab
%
% Inputs:
%   y        - Input data (1D array: spectrum or chromatogram)
%   lambda   - Smoothness parameter (higher = smoother baseline)
%   ratio    - Convergence threshold for stopping iterations (0 < ratio < 1)
%   itermax  - Maximum number of iterations
%
% Output:
%   z        - Estimated baseline

    arguments
        y 
        lambda {mustBeNumeric} = 1e4;
        ratio {mustBeNumeric} = 0.05;
        itermax {mustBeInteger} = 100;
    end
    y = y(:);  % Ensure column vector
    N = length(y);
    
    % Construct second-order difference matrix D
    e = ones(N,1);
    D = spdiags([e -2*e e], 0:2, N-2, N);  % Second derivative matrix
    H = lambda * (D' * D);  % Smoothness penalty term

    w = ones(N,1);  % Initial weights
    
    for i = 1:itermax
        W = spdiags(w, 0, N, N);
        WH = W + H;
        
        % Solve (W + H) z = w .* y using Cholesky decomposition
        % MATLAB's backslash operator with sparse matrices uses Cholesky automatically
        z = WH \ (w .* y);
        
        % Update weights based on generalized logistic function
        d = y - z;
        dn = d(d < 0);
        m = mean(dn);
        s = std(dn);
        wt = 1 ./ (1 + exp(2 * (d - (2 * s - m)) / s));
        
        % Check for convergence
        if norm(w - wt) / norm(w) < ratio
            break;
        end
        
        w = wt;
    end
end
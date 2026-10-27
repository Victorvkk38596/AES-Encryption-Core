function R = fast_corr(X, Y)
% FAST_CORR Computes Pearson correlation coefficient between columns of X and Y.
%   R = fast_corr(X, Y)
%
%   Inputs:
%       X: [N x K] matrix of observations (e.g., N traces x 256 key hypotheses)
%       Y: [N x M] matrix of observations (e.g., N traces x M time samples)
%
%   Outputs:
%       R: [K x M] matrix of Pearson correlation coefficients:
%          R(k, m) = corr(X(:, k), Y(:, m))
%
%   Optimized for high-throughput vectorized CPA execution without loops.

    [Nx, K] = size(X);
    [Ny, M] = size(Y);
    assert(Nx == Ny, 'Row dimension mismatch between X and Y matrices.');

    % Mean-center columns
    Xc = X - mean(X, 1);
    Yc = Y - mean(Y, 1);

    % Compute standard deviations / norms
    normX = sqrt(sum(Xc .^ 2, 1));  % [1 x K]
    normY = sqrt(sum(Yc .^ 2, 1));  % [1 x M]

    % Guard against division by zero on static/flat time samples
    normX(normX == 0) = Inf;
    normY(normY == 0) = Inf;

    % Vectorized covariance and Pearson correlation
    % (Xc' * Yc) has dimensions [K x M]
    denom = (normX') * normY;       % [K x M]
    R = (Xc' * Yc) ./ denom;

    % Clean any residual NaNs
    R(isnan(R)) = 0;
end

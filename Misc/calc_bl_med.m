function baseline = calc_bl_med(x, mw, sf, sigma)
% calc_bl_med: Median baseline correction for 1D NMR data
%
% Inputs:
%   x     - 1D array of NMR data
%   mw    - Median window size in points
%   sf    - Smooth window size in points
%   sigma - Standard deviation for Gaussian convolution
%
% Output:
%   baseline - Estimated baseline

    % Ensure column vector
    x = x(:);
    
    % Step 1: Find extrema points
    med3 = medfilt1(x, 3);  % 3-point median filter
    mask = (x == med3);
    mask(1) = false;
    mask(end) = false;
    e = x;
    e(~mask) = NaN;  % Mask non-extrema by setting to NaN
    
    % Step 2: Apply median filter to masked array
    % Replace NaNs with mirrored border for medfilt1
    e_filled = fillmissing(e, 'nearest');
    m = medfilt1(e_filled, mw + 1, 'truncate');  % mimic 'mirror' mode
    
    % Step 3: Convolve with a Gaussian
    g = gausswin(sf, sigma);  % Create Gaussian window
    g = g / sum(g);           % Normalize
    baseline = conv(m, g, 'same');  % Convolve and return baseline
end
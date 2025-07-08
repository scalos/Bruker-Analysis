function [phasedData, optPhases] = autops(data, fn, p0, p1, returnPhases, peakWidth, varargin)
    % Automatic linear phase correction for NMR data in MATLAB
    % data: complex vector
    % fn: function handle or string ('acme', 'peak_minima')
    % p0, p1: initial phase estimates in degrees
    % returnPhases: boolean, whether to return [p0, p1]
    % peakWidth: int, used for 'peak_minima' mode
    
    if nargin < 3, p0 = 0; end
    if nargin < 4, p1 = 0; end
    if nargin < 5, returnPhases = false; end
    if nargin < 6, peakWidth = 100; end
    
    % Wrap scoring function
    if isa(fn, 'char') || isa(fn, 'string')
        switch lower(fn)
            case 'acme'
                scorer = @(ph) ps_acme_score(ph, data);
            case 'peak_minima'
                scorer = @(ph) ps_peak_minima_score(ph, data, peakWidth);
            otherwise
                error('Unknown scoring function: %s', fn);
        end
    else
        scorer = @(ph) fn(ph, data);  % Custom function
    end
    
    % Optimization
    opt = fminsearch(scorer, [p0, p1], varargin{:});
    phasedData = ps(data, opt(1), 0, opt(2));
    
    if returnPhases
        optPhases = opt;
    else
        optPhases = [];
    end
end

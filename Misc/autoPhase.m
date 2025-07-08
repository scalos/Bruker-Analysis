function [phasedspc, opt] = autoPhase(data, fn, p0, p1, return_phases, peak_width, varargin)
    if nargin < 3, p0 = 0.0; end
    if nargin < 4, p1 = 0.0; end
    if nargin < 5, return_phases = false; end
    if nargin < 6, peak_width = 100; end

    if isa(fn, 'function_handle')
        score_fn = fn;
        args = {data};
    else
        switch lower(fn)
            case 'acme'
                score_fn = @ps_acme_score;
                args = {data};
            case 'peak_minima'
                score_fn = @(ph, d) ps_peak_minima_score(ph, d, peak_width);
                args = {data};
            otherwise
                error('Unknown phase score function: %s', fn);
        end
    end

    opts = optimset('fminsearch');
    opts = optimset(opts, varargin{:});
    opt = fminsearch(@(ph) score_fn(ph, args{:}), [p0, p1], opts);
    phasedspc = ps(data, opt(1), opt(2));

    if ~return_phases
        opt = [];
    end
end

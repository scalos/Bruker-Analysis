function data = shift_data(data, shiftInd, dim, opts)
    arguments
        data 
        shiftInd {mustBeInteger,mustBeGreaterThan(shiftInd,0)};
        dim {mustBeInteger,mustBeGreaterThan(dim,0)} = 1;
        opts.zeroTail {mustBeNumericOrLogical} = false; 
    end
     
    sz = size(data);

    % Create index cell arrays for source and destination
    idx1 = repmat({':'}, 1, ndims(data));
    idx2 = repmat({':'}, 1, ndims(data));

    % Define shifting range for the specified dimension
    idx1{dim} = 1:sz(dim)-shiftInd;
    idx2{dim} = shiftInd+1:sz(dim);

    % Perform the shift
    data(idx1{:}) = data(idx2{:});

    % Zero out the trailing part if requested
    if opts.zeroTail
        idx_fill = repmat({':'}, 1, ndims(data));
        idx_fill{dim} = sz(dim)-shiftInd+1:sz(dim);
        data(idx_fill{:}) = 0;
    end
end
function pos = getGridPos(m, n, index, spacing)
    % getGridPos: calculates position vector [x y w h] for subplot-style layout
    % m: number of rows
    % n: number of columns
    % index: position index (1-based)
    % spacing: scalar or [hspace vspace] in normalized units (optional)
    
    if nargin < 4, spacing = 0.02; end
    if isscalar(spacing), spacing = [spacing spacing]; end
    
    % Calculate width/height per tile
    w = (1 - spacing(1)*(n+1)) / n;
    h = (1 - spacing(2)*(m+1)) / m;
    
    % Row/column indices
    row = m - floor((index-1)/n); % invert y-direction
    col = mod(index-1, n) + 1;
    
    % Position
    x = spacing(1) + (col-1)*(w + spacing(1));
    y = spacing(2) + (row-1)*(h + spacing(2));
    
    pos = [x, y, w, h];
end
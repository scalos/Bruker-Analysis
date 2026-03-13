function updateWaterfall(h, x, y, z, c)
    %update waterfall plot. h is patch handle
    arguments
        h 
        x
        y
        z
        c = [];
    end
    if isempty(c)
        c = z;
    end
    % Replicate waterfall's padding scheme
    z0 = min(z(:));
    if z0 == max(z(:))
        if z0 == 0
            z0 = -1;
        else
            z0 = z0 - abs(z0)/2;
        end
    end

    % Pad x and y
    x = [x(:,[1 1]) x x(:,size(x,2)*[1 1 1])];
    y = [y(:,[1 1]) y y(:,size(y,2)*[1 1 1])];

    % Pad z
    z = [z0*ones(size(z,1),1) z(:,1) z z(:,size(z,2)) z0*ones(size(z,1),2)];

    
    % Pad c (matching waterfall's source exactly)
    c0 = (max(c(:)) + min(c(:))) / 2;
    c = [c0*ones(size(c,1),2) c c0*ones(size(c,1),2) NaN(size(c,1),1)];

    % Assign transposed
    h.CData = c';
    h.XData = x';
    h.YData = y';
    h.ZData = z';
end
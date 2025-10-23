function [TC,cBds,dataNorm] = mat2TC(data,colormap,opts)
    % Convert 2D matrix into true color array
    %
    % mat2TC(data,colormap,opts)
    %
    % opts.clim -> color limits, data outside these bounds will be clipped
    %
    % Returns: 
    %   TC = true color array, 
    %   cBounds = color bounds numbers for adding ticks to cbar

    arguments
        data (:,:);
        colormap (:,3);
        opts.clim = [];
    end
    dataMax = max(max(data));
    dataMin = min(min(data));
    dataRange = dataMax-dataMin;
    if isempty(opts.clim)
        dataNorm = (data-dataMin)/(dataRange);
        data = dataNorm*height(colormap);
        cBds = [dataMin,dataMax];
    else
        cMax = max(opts.clim);
        cMin = min(opts.clim);
        cRange = cMax-cMin;
        dataNorm = (data-cMin)/cRange;
        dataNorm(data>cMax) = 1;
        dataNorm(data<cMin) = 0;
        data = dataNorm*height(colormap);
        cBds = [cMin,cMax];
    end
    TC = ind2rgb(round(data),colormap);
end
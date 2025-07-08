function data = zFill(data,fillFac,leftFills)
    %add zero fill to data. By default, the first dimension is expected to
    %be spectral and thus the zero fill is only at the end. All other
    %dimensions are expected to be spatial and will have the zero fill
    %added to both ends. To change this behavior, edit leftFills parameter
    %to set what portion of the zfill will be added to the left of each
    %dimension.
    arguments
        data 
        fillFac {mustBeInteger}
        leftFills = []; %ex: default = [0,1/2,1/2,1/2,...]
    end
    if isempty(leftFills)
        leftFills = 1/2*ones(length(size(data)));
        leftFills(1) = 0;
    end
    rawData = data;
    zf = ones(length(size(data)),1);
    zf(1:length(fillFac)) = fillFac;
    rawSizes = size(data);
    zfSizes = rawSizes;
    for idx = (1:length(rawSizes))
        if zf(idx)>1
            zfSizes(idx) = zfSizes(idx)*zf(idx);
        end
    end
    data = zeros(zfSizes,'like',rawData);
    rawSlice = repmat({':'}, 1, length(zfSizes));
    for idx = (1:length(zfSizes))
        indStart = floor((zfSizes(idx)-rawSizes(idx))*leftFills(idx))+1;
        rawSlice{idx} = indStart:indStart+rawSizes(idx)-1;
    end
    data(rawSlice{:}) = rawData;
end
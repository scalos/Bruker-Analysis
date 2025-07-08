function maskedBase = mask(base,mask,dimOffset)
    arguments
        base
        mask
        dimOffset = 1;
    end
    %Apply 2d mask to first two dimensions of base matrix after dim Offset
    %ex: M = 1024x10x10x1x6, dimOffset = 2=> mask applied to 10x10 matrix

    nDims = length(size(base));
    if dimOffset > nDims-1
        error('Dim Offset must be <= base dimensions-1')
    end
    permutedBase = permute(base,[dimOffset:nDims,1:dimOffset-1]);
    baseSize = size(permutedBase);
    scaledMask = imresize(mask,[baseSize(1),baseSize(2)]);
    maskedBase_permute = permutedBase.*double(scaledMask);
    maskedBase = permute(maskedBase_permute,[nDims-dimOffset+2:nDims,...
        1:nDims-dimOffset+1]);
end
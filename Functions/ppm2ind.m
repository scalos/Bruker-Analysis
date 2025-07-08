function idxs = ppm2ind(xppm,ppmVal)
    arguments
        xppm;
        ppmVal; 
    end
    idxs = zeros(size(ppmVal));
    for ind = 1:numel(ppmVal)
        [~,idx] = min(abs(xppm-ppmVal(ind)));
        idxs(ind) = idx;
    end
end
function [dimStrings,allRanges] = summarize5DLogical(focus)
    assert(ndims(focus) == 5, 'Input must be a 5D logical array');
    sz = size(focus);
    [s, x, y, z, r] = ind2sub(sz, find(focus));

    allDims = {s, x, y, z, r};
    dimStrings = cell(5,1);
    allRanges = cell(5,1);
    for d = 1:5
        uniqueVals = unique(allDims{d});
        ranges = indexEdges(uniqueVals);

        parts = cell(size(ranges,1),1);
        allRanges{d} = ranges;
        for i = 1:size(ranges,1)
            if ranges(i,1) == ranges(i,2)
                parts{i} = sprintf('%d', ranges(i,1));
            else
                parts{i} = sprintf('%d:%d', ranges(i,1), ranges(i,2));
            end
        end

        dimStrings{d} = strjoin(parts, ',');
    end
end
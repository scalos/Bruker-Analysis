function edges = indexEdges(indices)
    if isempty(indices)
        edges = zeros(0,2);
        return;
    end

    indices = sort(indices(:));
    d = diff(indices);
    breaks = [0; find(d ~= 1); length(indices)];

    edges = zeros(length(breaks)-1, 2);
    for i = 1:length(breaks)-1
        startIdx = indices(breaks(i)+1);
        endIdx   = indices(breaks(i+1));
        edges(i, :) = [startIdx, endIdx];
    end
end
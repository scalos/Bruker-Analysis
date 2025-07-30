function cmap = rgb2cmap(rgbs,nPts)
%colormap formed by gradient between rgb1 -> ... -> rgbN with nPts colors
% rgb2cmap(rgbs,nPts)
%   rgbs -> (nx3) matrix of rgb values to interpolate through
%            NOTE: if size(rgbs,1) => interpolate from black to rgbs
%   nPts -> number of color in resulting cmap
    if size(rgbs,1)==1
        rgbs = [0,0,0;rgbs];
    end
    R = zeros(nPts,1);
    G = zeros(nPts,1);
    B = zeros(nPts,1);
    step = round(nPts/(size(rgbs,1)-1));
    for idx = 1:size(rgbs,1)-1
        iStart = step*(idx-1)+1;
        iEnd = step*(idx);
        R(iStart:iEnd) = linspace(rgbs(idx,1),rgbs(idx+1,1),step)';
        G(iStart:iEnd) = linspace(rgbs(idx,2),rgbs(idx+1,2),step)';
        B(iStart:iEnd) = linspace(rgbs(idx,3),rgbs(idx+1,3),step)';
    end
    cmap = [R,G,B];
end
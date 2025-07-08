function roi = readImg(path,size)
    arguments
        path
        size = []
    end
    fileID = fopen(path);
    roiRaw = fread(fileID,inf,'int8');
    roi = abs(flip(permute(reshape(roiRaw,size),[2,1]),1));
end
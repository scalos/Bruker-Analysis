function data = decodeCentric(rawData)
    data(:,:,7,:) = rawData(:,:,1,:);
    data(:,:,6,:) = rawData(:,:,2,:);
    data(:,:,8,:) = rawData(:,:,3,:);
    data(:,:,5,:) = rawData(:,:,4,:);
    data(:,:,9,:) = rawData(:,:,5,:);
    data(:,:,4,:) = rawData(:,:,6,:);
    data(:,:,10,:) = rawData(:,:,7,:);
    data(:,:,3,:) = rawData(:,:,8,:);
    data(:,:,11,:) = rawData(:,:,9,:);
    data(:,:,2,:) = rawData(:,:,10,:);
    data(:,:,12,:) = rawData(:,:,11,:);
    data(:,:,1,:) = rawData(:,:,12,:);
end
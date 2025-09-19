
k_data = zeros([2048,8,8,1,numel(csiNums)]);
for idx = 1:numel(csiNums)
    eNum = csiNums(idx);
    csiEx_ = study.getExpmt(eNum);
    k_data(:,:,:,:,idx) = csiEx_.procData.kspace{1};
end

csi = DataRecon(k_data,'K','allParams',csiEx.sysParams,'dataShape',size(k_data));
function newLayers = spreadStructFields(refStruct,spreadStructs,fields)
    newLayers = cell(numel(spreadStructs),1);
    for fInd = 1:numel(fields)
        f = fields{fInd};
        if isfield(refStruct,f)
            for sInd = 1:numel(spreadStructs)
                s = spreadStructs{sInd};
                if isfield(s,f)
                    s.(f) = refStruct.(f);
                    newLayers{sInd} = s;
                end
            end
        end
    end
end
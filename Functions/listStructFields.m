function tbl = listStructFields(structs,fields)
    fieldData = cell(1,numel(fields));
    for sInd = 1:numel(structs)
        s = structs{sInd};
        for fInd = 1:numel(fields)
            f = fields{fInd};
            if isfield(s,f)
                fieldData{sInd,fInd} = s.(f);
            else
                fieldData{sInd,fInd} = 'INVALID FIELD';
            end

        end
    end
    tbl = cell2table(fieldData,'VariableNames',fields);
    tbl = [table((1:numel(structs))','VariableNames',{'Index'}),tbl];
end
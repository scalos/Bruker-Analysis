function diffTbl = strucDiff(struct1,struct2,structNames)
    arguments
        struct1
        struct2
        structNames = {};
    end
    fields1 = fieldnames(struct1);
    cols = {'Field','Struct 1 Value','Struct 2 Value'};
    if ~isempty(structNames)
        for idx = 1:numel(structNames)
            name = structNames{idx};
            cols{1+idx} = name;
        end
    end
    diffFields = {};
    vals1 = {};
    vals2 = {};
    for fInd = 1:numel(fields1)
        f = fields1{fInd};
        if isfield(struct2,f)
            val1 = string(struct1.(f));
            val2 = string(struct2.(f));
            isDiffField = false;
            try 
                if ~strcmp(val1,val2)
                    isDiffField = true;
                end
            catch
                if numel(val1) ~= numel(val2)
                    isDiffField = true;
                end
            end
            if isDiffField
                diffFields{end+1} = f;  %#ok agrow
                vals1{end+1} = val1;    %#ok agrow
                vals2{end+1} = val2;    %#ok agrow
            end
        end
    end
    diffTbl = table(diffFields',vals1',vals2','VariableNames',cols);
end
function diffTbl = structDiff(structs,names)
    arguments
        structs
        names = {};
    end
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Function to analyze differences in structures. Structs should be a
    % cell array of MATLAB structures, names is an optional cell array of
    % string names for the passed structures (to be displayed in the
    % produced table.
    %
    % The function will produce a table containing all fields which have at
    % least one difference in value across the structures. For fields which
    % aren't shared across all structures, structures without this field
    % will be assigned a corresponding value of NaN in the difference table
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    
    if ~iscell(structs) && isscalar(structs)
        structs = {structs};
    end
    if ~iscell(names) && isscalar(names)
        names = {names};
    end
    cols = cell(numel(structs)+1,1);
    cols{1} = 'Field';
    for idx = 1:numel(structs)
        cols{idx+1} = sprintf('Struct %d',idx);
    end
    if ~isempty(names)
        for idx = 1:numel(names)
            name = names{idx};
            cols{1+idx} = name;
        end
    end
    fields = {};
    for sInd = 1:numel(structs)
        s = structs{sInd};
        sFields = fieldnames(s);
        for fInd = 1:numel(sFields)
            f = char(sFields{fInd});
            if ~ismember(f,fields)
                fields{end+1} = f; %#ok agrow
            end
        end
    end
    diffCellMat = {};
    for fInd = 1:numel(fields)
        f = fields{fInd};
        vals = cell(numel(structs),1);
        for sInd = 1:numel(structs)
            s = structs{sInd};
            if isfield(s,f)
                val = string(s.(f));
            else
                val = NaN;
            end
            vals{sInd} = val;
        end
        if ~isequal(vals{:})
            diffCellMat = cat(3 ,diffCellMat,{f,vals{:}}); %#ok agrow
        end
    end
    diffTbl = cell2table(squeeze(diffCellMat)',VariableNames=cols);     
end
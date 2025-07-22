function newStructs = spreadStructFields(refStruct,spreadStructs,fields)
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Function to apply values from one struct (refStruct) to any number of
    % other structures (spreadStructs). Fields to 'spread' are given as a
    % cell array of strings (fields). Fields will only be spread if the
    % corresponding structure already has the required field (no new fields
    % will be added). Function returns modified spreadStructs in cell array
    % newStructs
    %
    % Syntax: 
    % spreadStructFields(refStruct,spreadStructs,fields)
    %   - refStruct     -> struct with fields to be spread
    %   - spreadStructs -> cell array of structs
    %   - fields        -> cell array of fields to be spread
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    if ~iscell(spreadStructs) && isscalar(spreadStructs)
        spreadStructs = {spreadStructs};
    end
    if ~iscell(fields) && isscalar(fields)
        fields = {fields};
    end
    newStructs = cell(numel(spreadStructs),1);
    for fInd = 1:numel(fields)
        f = fields{fInd};
        if isfield(refStruct,f)
            for sInd = 1:numel(spreadStructs)
                s = spreadStructs{sInd};
                if isfield(s,f)
                    s.(f) = refStruct.(f);
                    newStructs{sInd} = s;
                end
            end
        end
    end
end
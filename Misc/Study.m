classdef Study < handle
    properties
        studyPath
        name
        expmts
    end

    methods
        function obj = Study(path)
            obj.studyPath = path;
            studyDir = dir(path);
            dirCell =  struct2cell(studyDir);
            expmtNums = [];
            pathArr = split(path,"/");
            obj.name = pathArr(end);
            if isempty(obj.name{1})
                obj.name = pathArr(end-1);
            end

            for name = dirCell(1,:)
                if ~isnan(str2double(name{1}))
                    expmtNums(end+1) = string(name{1});
                end
            end
            expmtNums = sort(expmtNums);            
            expmts(1:length(expmtNums)) = SpecExpmt;
            for i = (1:length(expmtNums))
                expmts(i) = SpecExpmt(fullfile(obj.studyPath,string(expmtNums(i)),'/pdata/1/'));
            end
            obj.expmts = expmts;
        end
        function list = listExpments(obj)
            list = cell(length(obj.expmts),1);
            for ind = (1:length(obj.expmts))
                list{ind} = obj.expmts(ind).brukerObj.Acqp.ACQ_scan_name;
            end
        end
    end
end
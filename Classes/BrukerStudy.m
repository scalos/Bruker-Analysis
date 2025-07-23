classdef BrukerStudy < handle
    properties
        path
        name
        expmts
    end

    properties (Access = private)
        expmtCache;
    end

    methods (Access = private)
        function loaded = isLoaded(obj,expmtNum)
            expmtNums = obj.getNums;
            ind = find(expmtNum==expmtNums);
            loaded = ind && ~isempty(obj.expmts{ind});
        end

        function expmtNums = getNums(obj)
            % Method used to get the numbers corresponding to the
            % experiment directories. Valid directories must contain an
            % integer name.
            dirCell =  struct2cell(dir(obj.path));
            expmtNums = [];
            %Experiment folders must match criterion of name = ##;
            for ind = dirCell(1,:)
                if ~isnan(str2double(ind{1}))
                    expmtNums(end+1) = string(ind{1}); %#ok agrow
                end
            end
            expmtNums = sort(expmtNums);  
        end
    end

    methods

        %%%%%%%%%%%%% CONSTRUCTOR %%%%%%%%%%%%%%%%%

        function obj = BrukerStudy(path)
            % Constructor method for BrukerStudy. Takes in a path to a valid
            % bruker study directory. If no path is given, user will be 
            % prompted to select a directory.
            %   NOTE: expmerements are not automatically loaded here
            %
            % BrukerStudy(path)
            %   path -> path to valid Bruker Study directory. If left blank
            %           user will be prompted with uigetdir
            arguments
                path = NaN;
            end
            
            if isnan(path)
                path = uigetdir;
                if path == 0
                    disp('Load Cancelled');
                    return
                end
            else
                path = char(path);
            end
            progBar = waitbar(0,'Fetching Experiments...');
            %Initialize study parameters:
            obj.path = path;
            pathArr = split(path,"/");
            obj.name = pathArr(end);
            if isempty(obj.name{1})
                obj.name = pathArr(end-1);
            end
            obj.name = obj.name{1};
            expmtNums = obj.getNums;
            obj.expmtCache = cell(size(expmtNums));
            obj.expmts = cell(size(expmtNums));

            foundError = false;
            for ind = (1:length(expmtNums))
                waitbar((ind-1)/length(expmtNums),progBar,'Fetching Experiments...');
                expmtNum = expmtNums(ind);
                try
                    acqp = readBrukerParamFile(char(fullfile(obj.path,string(expmtNum),'acqp')));
                    eName = acqp.ACQ_scan_name;
                    obj.expmtCache{ind} = sprintf('%2d: (UNLOADED) %s',expmtNum,eName);
                catch ME
                    obj.expmtCache{ind} = sprintf("%2d: ERROR",expmtNum);
                    foundError = true;
                end
            end
            close(progBar);
            if foundError
                warning('Some Experiments could not be loaded. Failed to load acqp files.')
            end
        end

        %%%%%%%%%% Experiment Methods %%%%%%%%%%%%%

        function loadExpmts(obj,loadNums)
            % Method used to load bruker experiments and populate
            % obj.expmts with BrukerExpmt objects. Failed loads will be
            % reported along with their error messages but the method will
            % continue to load subsequent experiments.
            %
            % loadExpmts(obj,loadNums)
            %   loadNums -> numbers of experiment directories to load. By
            %               default this is set to [] which means all
            %               experiments will be loaded
            %                 NOTE: loadNums correspond to directory numbers
            %                       and NOT to E numbers displayed in PV
            
            arguments
                obj 
                loadNums {mustBeInteger,mustBeGreaterThanOrEqual(loadNums,1)} = [];
            end
            expmtNums = obj.getNums;
            if isempty(loadNums)
                loadNums = expmtNums;
            end
            progBar = waitbar(0,sprintf('Loading Experiment %2d of %2d',1,length(loadNums)));

            newExpmts = cell(length(expmtNums),1);
            for ind = (1:length(loadNums))
                waitbar((ind-1)*1/length(loadNums),progBar,sprintf('Loading Experiment %2d of %2d',ind,length(loadNums)))
                expmtInd = find(expmtNums==loadNums(ind));
                if expmtInd
                    try
                        newExpmts{expmtInd} = BrukerExpmt(char(fullfile(obj.path,string(loadNums(ind)))));
                        fprintf('Loaded: .../%2d -> %s\n',newExpmts{expmtInd}.num,newExpmts{expmtInd}.name);
                    catch ME
                        warning('Failed to load experiment #%d',loadNums(ind));
                        warning(getReport(ME));
                    end
                else
                    warning('Requested load number %d is not valid!',loadNums(ind));
                end
            end
            waitbar(1,progBar);
            for ind = (1:length(newExpmts))
                if ~isempty(newExpmts{ind})
                    obj.expmts{ind} = newExpmts{ind};
                end
            end
            close(progBar);
        end

        function listExpmts(obj)
            % Method used to display the number, load status, and name of the
            % experiments within the study. The function will pull
            % information from pre-loaded experiments when possible and
            % when not it uses pvtools/.../readBrukerParamFile.m to parse
            % the acqp file for the scan name to display. If the cache
            % initially loaded with an error the method will attempt to
            % reload.

            expmtNums = obj.getNums;
            list = cell(length(expmtNums),1);
            for ind = (1:length(expmtNums))
                expmtNum = expmtNums(ind);
                try
                    if obj.isLoaded(expmtNum)
                        %If loaded: append identifiers to list
                        list{ind} = sprintf('%2d: ( LOADED ) %s',obj.expmts{ind}.num,obj.expmts{ind}.name);
                    else
                        if ~isempty(obj.expmtCache{ind})
                            if contains(char(obj.expmtCache{ind}),'ERROR')
                                %If not loaded and initially loaded with
                                %error: try to load again
                                acqp = readBrukerParamFile(char(fullfile(obj.path,string(expmtNum),'acqp')));
                                eName = acqp.ACQ_scan_name;
                                obj.expmtCache{ind} = sprintf('%2d: (UNLOADED) %s',expmtNum,eName);
                                list{ind} = sprintf('%2d: (UNLOADED) %s',expmtNum,eName);
                            else
                                %If previously cached but not loaded:
                                %append identifiers to list
                                list{ind} = obj.expmtCache{ind};
                            end
                        else
                            %If cache entry is empty: try to load
                            acqp = readBrukerParamFile(char(fullfile(obj.path,string(expmtNum),'acqp')));
                            eName = acqp.ACQ_scan_name;
                            list{ind} = sprintf('%2d: (UNLOADED) %s',expmtNum,eName);
                            obj.expmtCache{ind} = list{ind};
                        end
                    end
                catch ME
                    %catch loading errors and append error status (also
                    %display error report)
                    list{ind} = sprintf("%2d: ERROR",expmtNum);
                    warning(getReport(ME))
                end
            end

            %Finally show list:
            for ind = (1:length(list))
                disp(list{ind});
            end
        end

        function expmt = getExpmt(obj,num)
            % Conveniance function used to get a certain experiment from
            % the list of experiments in obj.expmts according to its
            % directory number
            % 
            % getExpmt(obj,num)
            %   num -> directory number corresponding to desired
            %          experiment
            expmt = [];
            expmtNums = obj.getNums;
            if isscalar(num)
                if ismember(num,expmtNums)
                    if obj.isLoaded(num)
                        expmt = obj.expmts{expmtNums==num};
                    else
                        warning('Experiment #%d is not loaded!\n',num);
                    end
                else
                    warning("Experiment #%d does not exist!\n" + ...
                            "(NOTE: number refers to folder number not (E##) in name)\n",num);
                end
            else
                error('ERROR: Method intended to grab one experiment at a time!');
            end
        end
    end
end
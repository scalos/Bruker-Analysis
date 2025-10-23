classdef Report < handle
    properties
        entries % Cell array of structures containing figs, sysParams, procParams, and notes
        runningID = 1;
        delEntries;
        exportParams;
        reportDir;
        recordDir;
        recording = true;
        charMax = 1000;
    end
    properties (Access=private)
        recordDirName = 'Records';
        reportFileName = 'Report.txt';
        logFileName = 'reco_logs.txt';
    end
        

    methods (Access=private)
        function fVar = formatVar(~,var)
            fVar = formattedDisplayText(var,"SuppressMarkup",true,"UseTrueFalseForLogical",true);
        end
        function vName = validFilename(~,path)
            working = true;
            vName = path;
            copyNum = 1;
            [parentPath,name,ext] = fileparts(path);
            while working
                if isfile(vName)
                    nChar = char(name);
                    if numel(char(name))<3
                        name = sprintf("%s(%d)",name,copyNum);
                    elseif strcmp(nChar(end-2:end),sprintf('(%d)',copyNum))
                        copyNum = copyNum+1;
                        name = sprintf("%s(%d)",nChar(1:end-3),copyNum);
                    else
                        name = sprintf("%s(%d)",name,copyNum);
                    end
                    vName = fullfile(parentPath,sprintf('%s%s',name,ext));
                else
                    working = false;
                end
            end
        end
    end

    % Prevent commandRecord and saveCode from overwriting
    %   - commandRecord should append
    %   - saveCode should make new timestamped file.
    
    methods

        function obj = Report(parentDir,opts)
            arguments
                parentDir = NaN;
                opts.name = [];
                opts.commandRecord = true;
                opts.saveCode = [];
                opts.timeStamp = true;
            end
            if isnan(parentDir)
                parentDir = uigetdir;
                if parentDir == 0
                    disp('Report cancelled.');
                    return;
                end
            end
            
            formats = {'fig','png'};
            obj.exportParams.DPI = 300;
            obj.exportParams.figSaveFormats = formats;
            timeStamp = datetime('now','Format','MMddyyHHmm');

            % Check if parentDir is valid recon dir:
            %   requires: 
            %       1) record dir with name obj.recordDirName
            %       2) file with name obj.logFileName in obj.recordDir
            newSession = true;
            if isfolder(fullfile(parentDir,obj.recordDirName))
                if isfile(fullfile(parentDir,obj.recordDirName,obj.logFileName))
                    newSession = false;
                end
            end

            if ~newSession
                %set report path to parentDir
                obj.reportDir = parentDir;
                obj.recordDir = fullfile(parentDir,obj.recordDirName);
            else
                if isempty(opts.name)
                    % Default name:
                    dirName = 'ReconReport';
                else
                    dirName = opts.name;
                end
                if opts.timeStamp
                    dirName = sprintf('%s_%s',timeStamp,dirName);
                end
                reportDir = fullfile(parentDir, dirName);
                recordDir = fullfile(reportDir,obj.recordDirName);
                mkdir(reportDir);
                mkdir(recordDir);
                obj.reportDir = reportDir;
                obj.recordDir = recordDir;
            end
            if opts.commandRecord
                recordName = sprintf('%s_commandlineRecord',timeStamp);
                diary(fullfile(obj.recordDir,recordName));
            end
            if isempty(opts.saveCode)
                if newSession
                    opts.saveCode = true;
                else
                    opts.saveCode = false;
                end
            end
            if opts.saveCode
                classEnvDir = fileparts(fileparts(mfilename("fullpath")));
                saveName = sprintf('%s_source_code',timeStamp);
                zip(fullfile(obj.recordDir,saveName),classEnvDir);
            end
            obj.updateIDFile;
            obj.update;
        end

        function updateIDFile(obj)
            path = fullfile(obj.recordDir,obj.logFileName);
            firstSession = true;
            if isfile(path)
                firstSession = false;
            end
            id = fopen(path,'a+');
            timeStamp = datetime('now','Format','dd-MMM-uuuu HH:mm:ss');
            if firstSession
                fprintf(id,'Recon started: %s',timeStamp);
            else
                fprintf(id,'\nRecon resumed: %s',timeStamp);
            end
        end
        
        function toggleRecording(obj)
            if obj.recording
                diary off;
                obj.recording = false;
                disp('Recording Paused');
            else
                diary on;
                obj.recording = true;
                disp('Recording Resumed');
            end
        end
        
        function openDir(obj)
            system(sprintf("open %s",strrep(obj.reportDir,' ','\ ')))
        end

        function update(obj)
            % Open the main report text file
            reportFile = fullfile(obj.reportDir, obj.reportFileName);
            %open with a+ => append to file
            fileID = fopen(reportFile, 'a+');
            
            % Loop through each entry in obj.entries
            toPrint = [];
            for idx = 1:numel(obj.entries)
                entry = obj.entries{idx};
                if entry.written
                    continue
                else
                    obj.entries{idx}.written = true;
                end

                if isfield(entry,'figs')
                    toPrint = [toPrint,char("===== Figures =====\n")];%#ok agrow
                    figEntries = entry.figs;
                    if isfield(obj.exportParams,'figSaveFormats')
                        saveFormats = obj.exportParams.figSaveFormats;
                    else
                        saveFormats = {'fig','png'};
                    end
                    for n = 1:2:numel(figEntries)
                        name = figEntries{n};
                        fig = figEntries{n+1};
                        for i = 1:numel(saveFormats)
                            format = ['.',saveFormats{i}];
                            path = obj.validFilename(fullfile(obj.reportDir,[name,format]));
                            if strcmp(format,'.fig')
                                savefig(fig,path);
                            else
                                exportgraphics(fig,path, ...
                                    'Resolution',obj.exportParams.DPI);
                            end
                            [~,vName] = fileparts(path);
                            toPrint = [toPrint,char(sprintf('%s%s\n',vName,format))]; %#ok agrow;
                        end
                        toPrint = [toPrint,'\n']; %#ok agrow;
                    end
                end
               
                % Write notes
                if isfield(entry, 'notes')
                    toPrint = [toPrint,char("===== Notes =====\n")];%#ok agrow
                    notes = entry.notes;
                    if ~iscell(notes) % Single note (string)
                        toPrint = [toPrint,char(sprintf("%s\n", obj.formatVar(notes)))];%#ok agrow
                    else % Array of notes
                        for n = 1:2:numel(notes)
                            label = notes{n};
                            note = notes{n + 1};
                            if numel(char(obj.formatVar(note)))>obj.charMax
                                fileName = sprintf('%s.txt',label);
                                filePath = fullfile(obj.reportDir, fileName);
                                vPath = obj.validFilename(filePath);
                                [~,vName,ext] = fileparts(vPath);
                                vFileName = sprintf('%s%s',vName,ext);
                                if isnumeric(note)
                                    % Save to a separate .txt file as CSV
                                    writematrix(note, vPath, 'Delimiter', ',');
                                else
                                    id = fopen(vPath,'w');
                                    fprintf(id,obj.formatVar(note));
                                end
                                % Reference the external file in Report.txt
                                toPrint = [toPrint,char(sprintf("%s:\n\tSaved in: %s\n", label, vFileName))]; %#ok agrow
                            else
                                toPrint = [toPrint,char(sprintf("%s:\n\t%s\n", label, obj.formatVar(note)))]; %#ok agrow
                            end
                        end
                    end
                end
                toPrint = [toPrint,char("\n=======================================\n\n")];%#ok agrow
            end
            if ~isempty(toPrint)
                fprintf(fileID,toPrint);
            end
            % Close the text file
            fclose(fileID);
        end

        function add(obj,entry)
            arguments
                obj 
                entry.notes;
                entry.figs;
            end

            %validation:
            if isfield(entry,'figs')
                figs = entry.figs;
                if ~iscell(figs)
                    error('ERROR: fig entries must be a cell of form {''fileName'',''figHandle''}');
                elseif mod(numel(figs),2)==1
                    error('ERROR: fig entries must be pairs of {''fileName'',''figHandle''}');
                end
            end

            if isfield(entry,'notes')
                notes = entry.notes;
                if ~iscell(notes)
                    if numel(char(obj.formatVar(notes)))>obj.charMax
                        error(['ERROR: notes longer than obj.charMax (%d)' ...
                            ' must be passed as name-value pairs\n e.g. {''name'',''value''}'],obj.charMax);
                    end
                elseif mod(numel(notes),2)==1
                    error('ERROR: name-val note entries must be pairs of {''noteTitle'',''noteContents''}');
                end
            end
            
            if ~isempty(fieldnames(entry))
                entry.written = false;
                entry.ID = obj.runningID+1;
                obj.runningID = obj.runningID+1;
                obj.entries{end+1} = entry;
            end
            obj.update;
        end

    end
end
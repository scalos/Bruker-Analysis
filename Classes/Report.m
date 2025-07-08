classdef Report < handle
    properties
        entries % Cell array of structures containing figs, sysParams, procParams, and notes
        runningID = 1;
        delEntries;
        exportParams;
        reportDir;
        recording = true;
    end
    % Add new report parameter: 'mat', pass to it strings corresponding to
    % workspace variables which will then be saved and placed into a
    % dedicated folder for .mat files

    % Prevent commandRecord and saveCode from overwriting
    %   - commandRecord should append
    %   - saveCode should make new timestamped file.
    
    methods

        function obj = Report(parentDir,opts)
            arguments
                parentDir = NaN;
                opts.name = [];
                opts.commandRecord = true;
                opts.saveCode = true;
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
            
            reportFile = fullfile(parentDir, 'Report.txt');

            % Check if the file exists
            if exist(reportFile, 'file') == 2
                obj.reportDir = parentDir;
            else
                if isempty(opts.name)
                    % Create a timestamped directory
                    timeStamp = datestr(now, 'mmddyyHHMM');
                    dirName = sprintf('%s_ReconReport', timeStamp);
                else
                    dirName = opts.name;
                end
                reportDir = fullfile(parentDir, dirName);
                mkdir(reportDir);
                obj.reportDir = reportDir;
            end
            if opts.commandRecord
                diary(fullfile(obj.reportDir,'commandLineRecord'));
            end
            if opts.saveCode
                classEnvDir = fileparts(fileparts(mfilename("fullpath")));
                zip(fullfile(obj.reportDir,'Source_Code'),classEnvDir);
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
        
        function update(obj)
            % Open the main report text file
            reportFile = fullfile(obj.reportDir, 'Report.txt');
            fileID = fopen(reportFile, 'a+');
            
            % Loop through each entry in obj.entries
            for idx = 1:numel(obj.entries)
                entry = obj.entries{idx};
                if entry.written
                    continue
                else
                    obj.entries{idx}.written = true;
                end

                % % Header for each entry
                % fprintf(fileID, "===== Entry %d =====\n", idx);

                % Write file information
                if isfield(entry, 'fileName') && isfield(entry, 'filePath')
                    fprintf(fileID, "===== File Information =====\n");
                    % relativeFilePath = fullfile(entry.fileName);
                    % [~, relativeFilePath] = fileparts(relativeFilePath); % Remove parent directories
                    fprintf(fileID, "File Name  : %s\n", entry.fileName);
                    % fprintf(fileID, "File Path  : %s\n\n", relativeFilePath);

                    % Copy the associated file to the new directory
                    sourceFile = fullfile(entry.filePath, entry.fileName);
                    destFile = fullfile(obj.reportDir, entry.fileName);
                    copyfile(sourceFile, destFile);
                end
                if isfield(entry,'figs')
                    fprintf(fileID, "===== Figures =====\n");
                    figs = entry.figs;
                    if isfield(obj.exportParams,'figSaveFormats')
                        saveFormats = obj.exportParams.figSaveFormats;
                    else
                        saveFormats = {'fig','png'};
                    end
                    if iscell(figs)
                        for n = 1:2:numel(figs)
                            name = figs{n};
                            fig = figs{n+1};
                            for i = 1:numel(saveFormats)
                                format = ['.',saveFormats{i}];
                                path = fullfile(obj.reportDir,[name,format]);
                                if strcmp(format,'.fig')
                                    savefig(fig,path);
                                else
                                    exportgraphics(fig,path, ...
                                        'Resolution',obj.exportParams.DPI);
                                end
                            end
                            fprintf(fileID,'%s%s\n',name,format);
                        end
                    end
                end

                % Write system parameters
                if isfield(entry, 'sysParams')
                    fprintf(fileID, "===== System Parameters =====\n");
                    sysFields = fieldnames(entry.sysParams);
                    maxSysFieldLength = max(cellfun(@length, sysFields));
                    for i = 1:numel(sysFields)
                        field = sysFields{i};
                        value = entry.sysParams.(field);
                        fprintf(fileID, "%*s : %s\n", maxSysFieldLength, field, num2str(value));
                    end
                    fprintf(fileID, "\n");
                end

                % Write processing parameters
                if isfield(entry, 'procParams')
                    fprintf(fileID, "===== Processing Parameters =====\n");
                    procFields = fieldnames(entry.procParams);
                    maxProcFieldLength = max(cellfun(@length, procFields));
                    for i = 1:numel(procFields)
                        field = procFields{i};
                        value = entry.procParams.(field);

                        % Check if value is a large array
                        if isnumeric(value) && numel(value) > 10
                            % Save to a separate .txt file
                            paramFileName = sprintf('proc(%d)_%s.txt',idx, field);
                            paramFilePath = fullfile(obj.reportDir, paramFileName);
                            writematrix(value, paramFilePath, 'Delimiter', ',');

                            % Reference the external file in Report.txt
                            fprintf(fileID, "%*s : Saved in %s\n", maxProcFieldLength, field, paramFileName);
                        else
                            % Regular parameter, write normally
                            fprintf(fileID, "%*s : %s\n", maxProcFieldLength, field, num2str(value));
                        end
                    end
                    fprintf(fileID, "\n");
                end
               
                % Write notes
                if isfield(entry, 'notes')
                    fprintf(fileID, "===== Notes =====\n");
                    notes = entry.notes;
                    
                    if ischar(notes) || isstring(notes) % Single note (string)
                        fprintf(fileID, "%s\n", formattedDisplayText(notes));
                    elseif iscell(notes) % Array of notes
                        for n = 1:2:numel(notes)
                            label = notes{n};
                            note = notes{n + 1};
                            fprintf(fileID, "%s:\n%s\n", label, formattedDisplayText(note));
                        end
                    end
                end
                fprintf(fileID, "\n=======================================\n\n");
            end
            
            % Close the text file
            fclose(fileID);
        end

        function obj = add(obj,entry)
            arguments
                obj 
                entry.notes;
                entry.sysParams;
                entry.procParams;
                entry.figs;
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
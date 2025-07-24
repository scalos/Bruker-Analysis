classdef BrukerExpmt < handle
    properties
        name;
        scanMethod = NaN;
        num;
        path;
        rawData;
		nChannels;
		nPoints;
        spatialSizes = NaN;
        nSlices;
        nReps;
        procPaths = {};
        procData = struct('raw',[],'kspace',[]);
        seqData = struct('raw',[],'kspace',[]);
        Acqp;
        Reco = {};
        Method;
        Visu = {};
        sysParams = struct;
        brukerRawObj = NaN;
        brukerFrameObj = NaN;
        brukerCKObject = NaN;
    end

    properties (Access = private)
        isEPSI;
        is360;
    end 

	methods
		function obj = BrukerExpmt(path)
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

            obj.path = path;

            %Load paths to pdata folders:
            dirCell = struct2cell(dir(fullfile(path,'pdata')));
            for ind = dirCell(1,:)
                if ~isnan(str2double(ind{1}))
                    obj.procPaths{end+1} = fullfile(path,'pdata',char(ind{1}));
                end
            end
            %%%%%%%%%%%%%%% LOAD PARAMETER FILES %%%%%%%%%%%%%%%%%%%%%%
            [~,name,~] = fileparts(obj.path);
            obj.num = str2double(name);
            brukerRawObj = RawDataObject(char(obj.procPaths{1}));
            obj.brukerRawObj = brukerRawObj;
            obj.rawData = brukerRawObj.data{1};
            %Acqp and Method appear only once in expmt folder
            obj.Acqp = brukerRawObj.Acqp;
            obj.Method = brukerRawObj.Method;
            %Load copy of reco and visu files for each pdata folder
            validProcPaths = ones(size(obj.procPaths));
            for idx = (1:length(obj.procPaths))
                try
		            brukerRawObj = RawDataObject(char(obj.procPaths{idx}));
                    obj.Reco{end+1} = brukerRawObj.Reco;
                    obj.Visu{end+1} = brukerRawObj.readVisu.Visu;
                catch
                    warning('Error loading parameter files for %s/pdata/%d. Skipping folder...',obj.path,idx);
                    validProcPaths(idx) = 0;
                end
            end
            for idx = (length(validProcPaths):-1:1)
                if ~validProcPaths(idx)
                    obj.procPaths(idx) = [];
                end
            end
            
            %%%%%%%%%%% LOAD USEFUL PARAMETERS FROM FILES %%%%%%%%%%%%
            obj.name = obj.Acqp.ACQ_scan_name;
            obj.sysParams.flipAng = obj.Visu{1}.VisuAcqFlipAngle;
            obj.sysParams.TR = obj.Acqp.ACQ_repetition_time; % TR in ms
            obj.nReps = obj.Reco{1}.RecoNumRepetitions;
            obj.nSlices = obj.Reco{1}.RecoObjectsPerRepetition;
            obj.scanMethod = obj.Acqp.ACQ_method;
            obj.isEPSI = ~isempty(strfind(obj.Acqp.ACQ_method,'EPSI'));
            obj.is360 = bruker_getAcqPvVersion(obj.Acqp,'is360');

            [obj.nChannels,~,~] = size(obj.rawData);
            
            %Modified from brukerLoadSpectra.m:
            if (isfield(obj.Acqp,'ACQ_RxFilterInfo'))
                obj.sysParams.groupDelay = obj.Acqp.ACQ_RxFilterInfo(1,1);
            elseif (isfield(obj.Acqp,'GRPDLY'))
                obj.sysParams.groupDelay = obj.Acqp.GRPDLY;
            else
                obj.sysParams.groupDelay = NaN;
            end
            
            %%%%%%%%%%%% LOAD SPATIAL PARAMETERS %%%%%%%%%%%%%%%%%%

            try
                nSpatialDims = length(obj.Reco{1}.RECO_size)-1;
                obj.spatialSizes = ones(1,3);
                if obj.isEPSI
                    % In EPSI, the spectral dimension is in between the first two spatial
                    % dimensions
                    obj.spatialSizes(1) = obj.Reco{1}.RECO_size(1);
                    obj.nPoints = obj.Reco{1}.RECO_size(2);
                    obj.spatialSizes(2) = obj.Reco{1}.RECO_size(3);
                    if 3 == nSpatialDims
                        obj.spatialSizes(3) = obj.Reco{1}.RECO_size(4);
                    end
                else
                    obj.nPoints = obj.Reco{1}.RECO_size(1);
                    for dim = 1:nSpatialDims
                        obj.spatialSizes(dim) = obj.Reco{1}.RECO_size(dim+1);
                    end
                end
    
                if 2 == nSpatialDims
                    obj.spatialSizes(3) = obj.Reco{1}.RecoObjectsPerRepetition;
                end
                
            catch ME
                warning('Error loading spatial-spectral dimensions\n%s',getReport(ME));
            end
            
            %%%%%%%%%%%% LOAD SPECTRAL PARAMETERS %%%%%%%%%%%%%%%%%%

            try
                if obj.isEPSI
                    if isfield(obj.Method,'SpecBand')
                        obj.sysParams.hzBW = obj.Method.SpecBand;
                    end
                    if isfield(obj.Method,'SpecBandPpm')
                        obj.sysParams.ppmBW = obj.Method.SpecBandPpm;
                    end
                else
                    if isfield(obj.Method,'PVM_SpecSWH')
                        obj.sysParams.hzBW = obj.Method.PVM_SpecSWH(1);
                    end
                    if isfield(obj.Method,'PVM_SpecSW')
                        obj.sysParams.ppmBW = obj.Method.PVM_SpecSW(1);
                    end
                end
                if isfield(obj.Method,'PVM_FrqRef')
                    % working center frequency in MHz
                    obj.sysParams.mhzCF = obj.Method.PVM_FrqRef(1); 
                end
                if isfield(obj.Method,'PVM_FrqWorkPpm')
                    % center frequency in ppm
                    obj.sysParams.ppmCF = obj.Method.PVM_FrqWorkPpm(1); 
                end
            catch ME
                warning('Error loading spectral parameters\n%s',getReport(ME));
            end

            obj.sysParams.dataShape = [obj.nPoints,obj.spatialSizes(1), ...
                                    obj.spatialSizes(2),obj.spatialSizes(3),obj.nReps];
            
            %%%%%%%%%%%%%%%%%%%%%%%% LOAD PROCESSED DATA %%%%%%%%%%%%%%%%%
            obj.loadFidProc;
            obj.load2dseq;

        end

        function loadFidProc(obj)
            for idx = (1:length(obj.procPaths))
                procPath = obj.procPaths{idx};
                % Supported methods for fid or fid_proc files:
                if ~isempty(strfind(obj.Acqp.ACQ_method,'CSI')) || ...
                   ~isempty(strfind(obj.Acqp.ACQ_method,'PRESS')) || ...
                   ~isempty(strfind(obj.Acqp.ACQ_method,'STEAM')) || ...
                   ~isempty(strfind(obj.Acqp.ACQ_method,'NSPECT')) || ...
                   ~isempty(strfind(obj.Acqp.ACQ_method,'ISIS')) || ...
                   ~isempty(strfind(obj.Acqp.ACQ_method,'EPSI')) || ...
                   ~isempty(strfind(obj.Acqp.ACQ_method,'SLASER'))
                    try
                        brukerProcObj = RawDataObject(char(procPath),'fid_proc');
                        procDataRaw = brukerProcObj.data{1};
                        procDataRecon = procDataRaw;
                        if prod(obj.spatialSizes)>1
                            if obj.isEPSI
                                procDataRaw = reshape(procDataRaw,...
                                [obj.spatialSizes(1),obj.nPoints ...
                                obj.spatialSizes(2),obj.spatialSizes(3),obj.nReps]);
                                procDataRaw = permute(procDataRaw,[2,1,3,4,5,6]);
                            else
                                procDataRaw = reshape(procDataRaw,...
                                    [obj.nPoints,obj.spatialSizes(1), ...
                                    obj.spatialSizes(2),obj.spatialSizes(3),obj.nReps]);
                            end
                            
                            % K-Space reconstruction:
                            
                            if obj.is360
                                tFormMat = {
                                            {},...
                                            {'fftshift','fft','fftshift'},...
                                            {'fftshift','fft','fftshift'},...
                                            {'fftshift','fft','fftshift'},...
                                            {},{}
                                            };
                                obj.sysParams.kReconOrder = tFormMat;
                                procDataRecon = K_R_Tform(procDataRaw,tFormMat);
    
                            else
                                tFormMat = {
                                            {},...
                                            {'fft','fftshift'},...
                                            {'fft','fftshift'},...
                                            {'fft','fftshift'},...
                                            {},{}
                                            };
                                obj.sysParams.kReconOrder = tFormMat;
                                procDataRecon = K_R_Tform(procDataRaw,tFormMat);
                            end
                        end
                        obj.procData.raw{end+1} = procDataRaw;
                        obj.procData.kspace{end+1} = procDataRecon;
                    catch ME
                        if obj.is360
                            fidName = 'fid_proc.64';
                        else
                            fidName = 'fid';
                        end
                        warning('Unable to load pdata/%d/%s\n%s',idx,fidName,getReport(ME))
                    end
                end 
            end

        end
    
        function load2dseq(obj)
            %Loop through procno paths to load processed data:
            for idx = (1:length(obj.procPaths))
                procPath = obj.procPaths{idx};
                if ~isempty(bruker_findDataname(procPath,'2dseq'))
                    try
                        seqDataRaw = readBruker2dseq(fullfile(procPath,'2dseq'),obj.Visu{idx});
                        %Methods where seq data may need reconstruction
                        if ~isempty(strfind(obj.Acqp.ACQ_method,'CSI')) || ...
                           ~isempty(strfind(obj.Acqp.ACQ_method,'PRESS')) || ...
                           ~isempty(strfind(obj.Acqp.ACQ_method,'STEAM')) || ...
                           ~isempty(strfind(obj.Acqp.ACQ_method,'NSPECT')) || ...
                           ~isempty(strfind(obj.Acqp.ACQ_method,'ISIS')) || ...
                           ~isempty(strfind(obj.Acqp.ACQ_method,'EPSI')) || ...
                           ~isempty(strfind(obj.Acqp.ACQ_method,'SLASER'))

                            
                        
                            if prod(obj.spatialSizes)>1
                                if obj.isEPSI
                                    seqDataRaw = reshape(seqDataRaw,...
                                    [obj.spatialSizes(1),obj.nPoints ...
                                    obj.spatialSizes(2),obj.spatialSizes(3),obj.nReps]);
                                    seqDataRaw = permute(seqDataRaw,[2,1,3,4,5,6]);
                                else
                                    seqDataRaw = reshape(seqDataRaw,...
                                        [obj.nPoints,obj.spatialSizes(1), ...
                                        obj.spatialSizes(2),obj.spatialSizes(3),obj.nReps]);
                                end
                            end
                            %Weird that we need this but...
                            seqDataRaw = flip(seqDataRaw,1);

                            tFormMat = {
                                            {'ifft','ifftshift'},...
                                            {'fftshift','fft','fftshift'},...
                                            {'fftshift','fft','fftshift'},...
                                            {'fftshift','fft','fftshift'},...
                                            {},{}
                                            };
                            seqDataRecon = K_R_Tform(seqDataRaw,tFormMat);
                            obj.seqData.kspace{end+1} = seqDataRecon;
                        end
                        obj.seqData.raw{end+1} = seqDataRaw;

                    catch ME
                        warning('Unable to load pdata/%d/2dseq\n%s',idx,getReport(ME))
                    end
                    
                end
            end
        end
    end
end

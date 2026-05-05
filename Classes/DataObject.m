classdef DataObject < handle

    properties
        kDataRaw
        dimF = NaN
        dimX = NaN
        dimY = NaN
        dimZ = NaN
        dimFG = NaN
        nDims;
        proc = struct;
        sysParams = struct;
        analysis = {};
        %rProcParamsCellima
        linkedPlots = {};
        procSetters = {};
    end

    properties (Access = private)
        % kProc_cashed;
        % rProc_cashed;
        % loadType;
    end

    properties (Dependent)
        %rProcParams;
        xppm;
        rData;
        kData;
    end

    properties (SetObservable)
        %kProcParams;
        rFocus;
        kFocus;
        prefs = struct('showFocChg',true, ...
                       'showFoc',true, ...
                       'ppmShift',0);
    end

    events
        focusChanged
        procChanged;
        prefsChanged;
    end

    methods (Access = private)
        function handlePropEvents(obj,src,evnt)
            switch evnt.EventName
                case 'PostSet'
                    switch src.Name
                        case 'rFocus'
                            if obj.prefs.showFocChg
                                notify(obj,'focusChanged')
                            end
                        case 'kFocus'
                            if obj.prefs.showFocChg
                                notify(obj,'focusChanged')
                            end
                        case 'prefs'
                            notify(obj,'prefsChanged');
                    end
            end
        end
    end

    methods
        %%%%%%%%%%%%% CONSTRUCTOR %%%%%%%%%%%%%%%%%

        function obj = DataObject(data,dataType,sysParams)
            arguments
                data; %data must be organized: (nPts,x,y,z,FG)
                dataType {mustBeMember(dataType,{'k','r'})};

                %allParams should be a struct with fields below
                sysParams.allParams = [];
                
                %Any of these params will override those within allParams if
                %both are passed to the constructor
                sysParams.hzBW = [];
                sysParams.mhzCF = [];
                sysParams.ppmCF = [];
                sysParams.flipAng = [];
                sysParams.ppmBW = [];
                sysParams.tempRes = [];
                %sysParams.dataShape = [];
                sysParams.kspaceTforms = {{'fftshift','fft'},...
                                          {'ifftshift','ifft','ifftshift'},...
                                          {'ifftshift','ifft','ifftshift'},...
                                          {'ifftshift','ifft','ifftshift'},...
                                          {},{}}; % transforms from k-space to real space
            end
            
            % initially set sysParams to any fields within allParams with
            % names matching expected fieldNames
            obj.sysParams = rmfield(sysParams,'allParams');
            if ~isempty(sysParams.allParams)
                paramFields = fieldnames(sysParams.allParams);
                for idx = (1:length(paramFields))
                    fieldName = paramFields{idx};
                    if isfield(obj.sysParams,fieldName)
                        obj.sysParams.(fieldName) = sysParams.allParams.(fieldName);
                    end
                end
            end
            % If any name/value parameters are passed explicitly outside of
            % allParams, override with explicit values:
            explicitParams = rmfield(sysParams,'allParams');
            fields = fieldnames(explicitParams);
            for ind = (1:length(fields))
                fieldName = fields{ind};
                if ~isempty(explicitParams.(fieldName))
                    obj.sysParams.(fieldName) = explicitParams.(fieldName);
                end
            end
            
            
            %initialize data dimensions: 
            obj.setDims(data);
            
            %Set up k/r data variables
            if strcmp(dataType,'k')
                obj.kDataRaw = data;
            else
                obj.kDataRaw = K_R_Tform(data,obj.sysParams.kspaceTforms,true);                
            end
            %initialize focus (all vals = 1)
            obj.initFocus;
            
            

            %If ppmBW is not passed it can be calculated here:
            if isempty(obj.sysParams.ppmBW) && ~isempty(obj.sysParams.hzBW) && ~isempty(obj.sysParams.mhzCF)
                obj.sysParams.ppmBW = obj.sysParams.hzBW/obj.sysParams.mhzCF;
            end
            
            if isempty(obj.sysParams.ppmBW) ||...
               isempty(obj.sysParams.ppmCF)
                warning(['Methods referencing the chemical shift will be unaccessable without ' ...
                    'parameters, "ppmBW","ppmCF".'])
            end
            if isempty(obj.sysParams.mhzCF)
                warning('Line Broadening will be unaccessable without parameter mhzCF');
            end

            %Set up procParam structs:
            % - kProcParams is struct b/c proc is applied to whole dataset
            % - rProcParams is stored as array for speed since each voxel
            %   can have individual proc params
            
            %obj.kProcParams = struct('blank',[],'lb',[],'zf',[]);
            %obj.kProc_cashed = obj.kProcParams;
            obj.initProc;
            obj.setListeners;
            obj.updateProc;
        end

        %%%%%%%%%%%%% GETS AND SETS %%%%%%%%%%%%%%%%%

        function setListeners(obj)
            %Reset listeners needed for auto-updating plots
            %   (if DataRecon obj is loaded from .mat file, run this to
            %   restart listeners)
            addlistener(obj,'procChanged',@obj.procChangedFcn);
            addlistener(obj,'focusChanged',@obj.focChangedFcn);
            addlistener(obj,'prefs','PostSet',@obj.handlePropEvents);
            addlistener(obj,'rFocus','PostSet',@obj.handlePropEvents);
            addlistener(obj,'kFocus','PostSet',@obj.handlePropEvents);
        end

        function focChangedFcn(obj,~,~)
            obj.updateLinkedPlots;
            obj.updateProcSetters;
        end

        function updateLinkedPlots(obj)
            if ~isempty(obj.linkedPlots)
               clearInds = [];
               for idx = 1:numel(obj.linkedPlots)
                    lp = obj.linkedPlots{idx};
                    if ~isvalid(obj.linkedPlots{idx})||~isprop(obj.linkedPlots{idx},'LinkedPlotParams')
                        clearInds(end+1) = idx; %#ok agrow
                        continue;
                    end
                    switch lp.LinkedPlotParams.domain
                        case 'k'
                            lp.FocNav.axMaps = obj.axMaps("k");
                            lp.FocNav.data = obj.kData;
                            lp.FocNav.focus = obj.kFocus;
                        case 'r'
                            lp.FocNav.axMaps = obj.axMaps("r");
                            lp.FocNav.data = obj.rData;
                            lp.FocNav.focus = obj.rFocus;

                    end
               end
               if ~isempty(clearInds)
                   fprintf('Cleared %d invalid linked plot(s)\n',numel(clearInds))
               end
               obj.linkedPlots(clearInds) = [];
            end
        end

        function pInd = procStepInd(obj,procStep)
            arguments
                obj
                procStep ProcStep
            end
            allSteps = [obj.proc.kProcSteps,obj.proc.rProcSteps];
            pInd = [];
            for idx = 1:numel(allSteps)
                if isequal(procStep,allSteps{idx})
                    pInd = idx;
                end
            end
        end

        function t = procStreamTbl(obj)
            kSteps = obj.proc.kProcSteps;
            rSteps = obj.proc.rProcSteps;
            steps = cell(numel(kSteps)+numel(rSteps)+2,2);
            steps(1,:) = {NaN,'Raw K-Space'};
            for idx = 1:numel(kSteps)
                steps(idx+1,1) = {idx};
                steps(idx+1,2) = {kSteps{idx}.tag};
            end
            steps(numel(kSteps)+2,:) = {NaN,'FFT'};
            for idx = 1:numel(rSteps)
                steps(idx+numel(kSteps)+2,1) = {idx+numel(kSteps)};
                steps(idx+numel(kSteps)+2,2) = {rSteps{idx}.tag};
            end
            t = cell2table(steps,'VariableNames',{'Index','Tag'});
        end

        function newProcSetter(obj,procInd,opts)
            arguments
                obj
                procInd {mustBeInteger}
                opts.togglePrevStepCache = true %start caching prev step
            end
            procStep = obj.getProcByInd(procInd);
            if isempty(procStep)
                disp('Invalid Proc Ind!');
            end
            if isempty(procStep.setter)
                warning('Proc step #%d doesn''t have an attached setter!',procInd);
                return;
            end
            setter = procStep.setter;
            setter.init;
            obj.procSetters{end+1} = setter;
            if opts.togglePrevStepCache
                prevStep = obj.prevProcStep(procStep);
                if ~isempty(prevStep)
                    prevStep.cacheable = true;
                    obj.updateProcStep(prevStep);
                end
            end
            obj.updateProcSetters;
        end
        
        function updateProcSetters(obj)
            %
            if ~isempty(obj.procSetters)
               clearInds = [];
               for idx = 1:numel(obj.procSetters)
                    setter = obj.procSetters{idx};
                    if ~setter.isActive()
                        clearInds(end+1) = idx; %#ok agrow
                        continue;
                    end
                    domain = obj.procStepDomain(setter.procStep);
                    if isempty(domain)
                        %proc step not found
                        clearInds(end+1) = idx; %#ok agrow
                        continue
                    end
                    setter.update;
               end
               if ~isempty(clearInds)
                   fprintf('Cleared %d inactive proc setter(s)\n',numel(clearInds))
               end
               obj.procSetters(clearInds) = [];
            end
        end

        function procChangedFcn(obj,~,~)
            obj.updateLinkedPlots;
            obj.updateProcSetters;
        end

        function rData = get.rData(obj)
            rData = obj.proc.cache.rData;
        end

        function kData = get.kData(obj)
            kData = obj.proc.cache.kData;
        end

        function aMaps = axMaps(obj,domain)
            arguments
                obj
                domain {mustBeMember(domain,{'k','r'})};
            end
            aMaps = {1:obj.dimF,...
                      1:obj.dimX,...
                      1:obj.dimY,...
                      1:obj.dimZ,...
                      1:obj.dimFG};
            if strcmp(domain,'r')
                aMaps{1} = obj.xppm;
            end
        end

        function newLinkedPlot(obj,domain,focController)
            arguments
                obj
                domain {mustBeMember(domain,{'k','r'})}
                focController logical = 0;
            end

            function lp = setupLinkedPlot(domain,isController,viewerObj)
                lp = viewerObj.dispAx;
                lp.DeleteFcn = @(src,evt) linkedPlotClosed(src,evt,obj);
                addprop(lp,'LinkedPlotParams');
                s = struct('domain',domain,'isController',isController);
                lp.LinkedPlotParams = domain;
                lp.LinkedPlotParams = s;
            end

            function linkedPlotClosed(src,~,obj)
                for lIdx = 1:numel(obj.linkedPlots)
                    if isequal(obj.linkedPlots{lIdx},src)
                        obj.linkedPlots(lIdx) = [];
                        return;
                    end
                end
            end

            function loadFoc(~,~,focObj)
                focNavAx = focObj.dispAx;
                if isvalid(focNavAx)
                    currFoc = focNavAx.FocNav.focus;
                    if strcmp(domain,'k')
                        obj.kFocus = currFoc;
                    else
                        obj.rFocus = currFoc;
                    end
                end
            end
            obj.updateLinkedPlots;
            dimDirs = ones(obj.nDims,1);
            if strcmp(domain,'k')
                initFoc = obj.kFocus;
                axMaps = obj.axMaps('k');
                data = obj.kData;
                dimLbls = {'kt','kx','ky','kz','frames'};
            else
                initFoc = obj.rFocus;
                axMaps = obj.axMaps('r');
                data = obj.rData;
                dimLbls = {'Chemical Shift (ppm)','x','y','z','frames'};
                dimDirs(1) = -1;
            end
            domainPlots = {};
            if ~isempty(obj.linkedPlots)
                for idx = 1:numel(obj.linkedPlots)
                    if obj.linkedPlots{idx}.LinkedPlotParams.domain == domain
                        domainPlots{end+1} = obj.linkedPlots{idx}; %#ok agrow
                    end
                end
            end
            
            
            if focController&&~isempty(domainPlots)
                %if user requests plot to control focus, ensure
                %that there isn't already a controller:
                existingController = 0;
                for idx = 1:numel(domainPlots)
                    if domainPlots{idx}.LinkedPlotParams.isController
                        existingController = 1;
                        break
                    end
                end
                if existingController
                    %TODO: add replace controller logic
                    warning('Linked Focus controller already open!');
                    return;
                end
            end
            
            
            viewerObj = ndMRViewer(data,"axMaps",axMaps, ...
                                        "initFoc",initFoc,...
                                        "dimLbls",dimLbls,...
                                        'intensityLbl',"MR Signal (a.u.)",...
                                        "showFoc",focController,...
                                        "dimDirections",dimDirs);
            viewerObj.plotMode = 'real';
            if focController
                viewerObj.FocChangedFcn = @loadFoc;
            end
            obj.linkedPlots{end+1} = setupLinkedPlot(domain,focController,viewerObj);
        end

        function addProcStep(obj,domain,procStep,insertAfterIdx)
            arguments
                obj
                domain {mustBeMember(domain,{'k','r'})};
                procStep
                insertAfterIdx = [];
            end
            
            %Function to add processing step. Must specify the domain over
            %which the step will be appled.

            if ~isa(procStep,'ProcStep')
                error('ERROR: attempted to add invalid processing step!');
            end
            if isempty(procStep.dataObj)
                procStep.dataObj = obj;
            end
            if strcmp(domain,'k')
                currProcList = obj.proc.kProcSteps;
                if -1==insertAfterIdx
                    insertAfterIdx = numel(currProcList);
                end
                currProcList = [currProcList(1:insertAfterIdx),...
                                                {procStep},...
                                                currProcList(insertAfterIdx+1:end)];
                 obj.proc.kProcSteps = currProcList;
                
            else
                currProcList = obj.proc.rProcSteps;
                if -1==insertAfterIdx
                    insertAfterIdx = numel(currProcList);
                end
                currProcList = [currProcList(1:insertAfterIdx),...
                                                {procStep},...
                                                currProcList(insertAfterIdx+1:end)];
                 obj.proc.rProcSteps = currProcList;
            end
        end
        
        function pStep = getProcByInd(obj,ind)
            arguments
                obj
                ind {mustBeInteger}
            end
            allSteps = [obj.proc.kProcSteps,obj.proc.rProcSteps];
            pStep = allSteps{ind};
        end

        function domain = procStepDomain(obj,procStep)
            arguments
                obj
                procStep ProcStep
            end
            domains = [];
            domain = '';
            
            if any(cellfun(@(x) isequal(x, procStep),obj.proc.kProcSteps))
                domains(1) = 1;
                domain = 'k';
            end
            if any(cellfun(@(x) isequal(x, procStep),obj.proc.rProcSteps))
                domains(2) = 1;
                domain = 'r';
            end
            if all(domains)
                error('ERROR: proc step is found in both domains!');
            end
        end

        function prevStep = prevProcStep(obj,procStep,opts)
            arguments
                obj
                procStep
                opts.restrictDomain = true
            end
            assert(isa(procStep,'ProcStep'));
            %get the previous proccessing step. use restrictDomain to only
            %return previous step within same domain. Thus calling this on
            %the first step in either domain will return []
            
            stepInd = obj.procStepInd(procStep);
            if isempty(stepInd)
                %=> procStep is not in stream
                error('ProcStep is not in stream!');
            end

            if 1==stepInd
                %no previous step
                prevStep = [];
                return;
            end
            if ~opts.restrictDomain
                prevStep = getProcByInd(stepInd-1);
                return;
            end
            %search by domain:
            kSteps = obj.proc.kProcSteps;
            rSteps = obj.proc.rProcSteps;
            if strcmp(obj.procStepDomain(procStep),'k')
                %safe to skip first here b/c we checked above
                for idx = 2:numel(kSteps)
                    step = kSteps{idx};
                    if isequal(step,procStep)
                        prevStep = kSteps{idx-1};
                        return;
                    end
                end
            else
                for idx = 1:numel(rSteps)
                    step = rSteps{idx};
                    if isequal(step,procStep)
                        if idx==1
                            %=> first step in rdomain
                            prevStep = [];
                            return;
                        else
                            prevStep = rSteps{idx-1};
                            return;
                        end
                    end
                end
            end
            
        end

        function updateProcStep(obj,procStep)
            arguments
                obj
                procStep ProcStep
            end
            domain = obj.procStepDomain(procStep);
            pInd = obj.procStepInd(procStep);
            if strcmp(domain,'k')
                obj.proc.kProcSteps{pInd} = procStep;
            else
                obj.proc.rProcSteps{pInd} = procStep;
            end
        end

        function inputData = getProcStepInput(obj,procStep)
            arguments
                obj
                procStep ProcStep
            end
            %allows access of data state immediately before the given
            %processing step. 
            domain = obj.procStepDomain(procStep);
            prevStep = obj.prevProcStep(procStep,"restrictDomain",1);
            
            %edge cases:
            if strcmp(domain,'k')&&isempty(prevStep)
                inputData = obj.kDataRaw;
            elseif strcmp(domain,'r')&&isempty(prevStep)
                inputData = K_R_Tform(obj.kData,obj.sysParams.kspaceTforms);
            else
                %if previous state was cached, grab it
                if prevStep.cacheable
                    inputData = prevStep.cachedState;
                    return;
                end
                %set previous state to be cacheable, run forced update and
                %break out after previous proc is finished, get that cached
                %state, and revert cacheing status
                prevStep.cacheable = true;
                obj.updateProcStep(prevStep);
                prevInd = obj.procStepInd(prevStep);
                obj.updateProc("force",1,"breakAtStep",prevStep);
                step = getProcByInd(prevInd);
                step.cacheable = false;
                obj.updateProcStep(step);
            end
            
        end
       
        function initProc(obj)
            obj.proc = struct('kProcSteps',[],...
                              'rProcSteps',[],...
                              'cache',struct('kData',[],...
                                             'rData',[]));
            %start with default processing steps:
            
            %% Blanking:
            function blankedData = applyBlank(procObj,~,data)
                %blankInd = blankInd{1};
                if isempty(procObj.params)
                    blankedData = data;
                    return;
                end
                blankInd = procObj.params{1};
                blankedData = shift_data(data,blankInd);
            end
            blankStep = ProcStep(@applyBlank,'global', ...
                                              'cacheable',false, ...
                                              'params',{},...
                                              'tag','Blanking',...
                                              'dataObj',obj);
            obj.addProcStep('k',blankStep,-1);
            %%

            %% Line Broadening:
            function lbData = applyLB(procObj,dataObj,data)
                %Performs exponential line broadening on k-space data
                if isempty(procObj.params)
                    lbData = data;
                    return;
                end
                lb = procObj.params{1};
                ppmBW = dataObj.sysParams.ppmBW;
                mhzCF = dataObj.sysParams.mhzCF;
                dt = (1/(ppmBW*mhzCF));
	            lbData = apod(data,lb,dt);
            end
            lbStep = ProcStep(@applyLB,'global',...
                                        'cacheable',false, ...
                                        'params',{},...
                                        'tag','Line Broadening',...
                                        'dataObj',obj);
            obj.addProcStep('k',lbStep,-1);
            %%

            %% Zero Fill:
            function zfData = applyZF(procObj,dataObj,data)
                % Performs zf on k-space data
                %Ensure zf = [fFill,xFill,yFill,zFill]
                %default: [1,1,1,1] => no zf on any dimensions
                if isempty(procObj.params)
                    zfData = data;
                    return;
                end
                zf = ones(4,1);
                zfParam = procObj.params{1};
                allProcSteps = [dataObj.proc.kProcSteps(:)',...
                                dataObj.proc.rProcSteps(:)'];
                zfStepInd = [];
                downstreamLocalProcs = false;
                for idx = 1:numel(allProcSteps)
                    procStep = allProcSteps{idx};
                    if isequal(procStep,procObj)
                        zfStepInd = idx;
                    end
                    if ~isempty(zfStepInd)
                        if idx>zfStepInd&&...
                           strcmp(procStep.scope,'local')&&...
                           ~all(cellfun(@isempty, procStep.params))
                            downstreamLocalProcs = true;
                        end
                    end
                end
                proceed = true;
                if downstreamLocalProcs
                    deciding = true;
                    while deciding
                        res = input(sprintf('WARNING: changing the zero fill will destroy downstream local processing steps. Proceed? (y/n): '),'s');
                        switch res
                            case 'y'
                                deciding = false;
                            case 'n'
                                proceed = false;
                                deciding = false;
                            otherwise
                                disp('Unrecognized Response');
                        end

                    end
                end
                zfData = [];
                if proceed
                    zf(1:numel(zfParam)) = zfParam;
                    if all(zf==1)
                        zfData = data;
                    else
                        zfData = zFill(data,zf);
                    end
                end
            end
            zfStep = ProcStep(@applyZF,'global',...
                                        'cacheable',false, ...
                                        'params',{},...
                                        'tag','zero-fill',...
                                        'dataObj',obj);
            obj.addProcStep('k',zfStep,-1);
            %%

            %% Phase Correction
            function psData = applyPhases(procObj,~,data)
                %TODO: integrate sparse matricies for parameters
                %assume first dimension is spectral
                nPts = size(data,1);
                if isempty(procObj.params)
                    %if no phasing has been done, return data unchanged
                    psData = data;
                    return;
                end
                phi0s = procObj.params{1};
                phi1s = procObj.params{2};
                pivots = procObj.params{3};
                

                if ~all(isequal(size(data,2:ndims(data)),size(phi0s)))
                    %data size has changed, unable to apply phasing
                    disp('WARNING: Data size has changed, clearing phasing parameters!');
                    procObj.params = {};
                    psData = data;
                    return;
                end
                phi0s = reshape(repmat(phi0s,[nPts,1]),[size(data)]);
                phi1s = reshape(repmat(phi1s,[nPts,1]),[size(data)]);
                pivots = reshape(repmat(pivots,[nPts,1]),[size(data)]);
                if isempty(phi1s)
                    phase = phi0s;
                else
                    phase = repmat((1:nPts)',size(data,2:ndims(data)));
                    phase = (phase-pivots).*phi1s+phi0s;
                end
                psData = data.*exp(1i*deg2rad(phase));
            end
            % function setPhases(procObj,dataObj)
            % %% junk
            % %     function applyPsFun(~,~,psObj,userData)
            % %         psObj.applyPhaseButton.Enable = 'off';
            % %         procObj_ = userData{1};
            % %         dataObj_ = userData{2};
            % %         data_ = userData{3};
            % %         phi0 = psObj.phi0;
            % %         phi1 = psObj.phi1;
            % %         pivot = psObj.pivot_ind;
            % %         if isempty(procObj_.params)
            % %             procObj_.params{1} = zeros(size(data_,2:ndims(data_)));
            % %             procObj_.params{2} = zeros(size(data_,2:ndims(data_)));
            % %             procObj_.params{3} = zeros(size(data_,2:ndims(data_)));
            % %         end
            % %         newPhi0 = procObj_.params{1};
            % %         newPhi1 = procObj_.params{2};
            % %         newPivot = procObj_.params{3};
            % %         spatFoc_ = dataObj_.rFocus(2:end);
            % %         if ~procObj_.constInRegion(spatFoc_)
            % %             res_ = input('WARNING: the current focus spans more than one unique phase. Override phases in this region? (y/n) ','s');
            % %             if strcmp(res_,'y')
            % %                 newPhi0 = repmat(phi0,size(newPhi0));
            % %                 newPhi1 = repmat(phi1,size(newPhi1));
            % %                 newPivot = repmat(pivot,size(newPivot));
            % %             else
            % %                 disp('Aborting phase set...')
            % %                 psObj.applyPhaseButton.Enable = 'on';
            % %                 return;
            % %             end
            % %         end
            % % 
            % %         newPhi0(spatFoc_{:}) = phi0;
            % %         newPhi1(spatFoc_{:}) = phi1;
            % %         newPivot(spatFoc_{:}) = pivot;
            % %         procObj_.setParams({newPhi0,newPhi1,newPivot})
            % %         dataObj_.updateProc;
            % %         psObj.applyPhaseButton.Enable = 'on';
            % %     end
            % % 
            % % 
            % %     % if ~isempty(dataObj.psSetter)
            % %     %     setter = dataObj.psSetter;
            % %     %     if isvalid(setter.panel)
            % %     %         setterFig = ancestor(setter.panel,'Figure');
            % %     %         figure(setterFig);
            % %     %         selection = uiconfirm(setterFig,'Close existing instance?','Existing setter');
            % %     %         switch selection
            % %     %             case 'OK'
            % %     %                 delete(setterFig);
            % %     %             case 'Cancel'
            % %     %                 return;
            % %     %         end
            % %     %     end
            % %     % end
            % % 
            % %     currFoc = dataObj.rFocus;
            % %     prevData = dataObj.getProcStepInput(procObj);
            % %     %calls PhaseAdj and sets applyPhaseFun to route into
            % %     %procObj.setParams
            % %     prevData_foc = prevData(currFoc{:});
            % %     prevData_foc = mean(prevData_foc,2:ndims(prevData));
            % %     phi0s = [];
            % %     phi1s = [];
            % %     pivots = [];
            % %     spatFoc = currFoc(2:end);
            % %     if ~isempty(procObj.params)
            % %         currPhi0s = procObj.params{1};
            % %         currPhi1s = procObj.params{2};
            % %         currPivots = procObj.params{3};
            % %         phi0s = currPhi0s(spatFoc{:});
            % %         phi1s = currPhi1s(spatFoc{:});
            % %         pivots = currPivots(spatFoc{:});
            % %     end
            % % 
            % %     if ~isempty(phi0s)
            % %         if ~procObj.constInRegion(spatFoc)
            % %             res = input('WARNING: the current focus spans more than one unique phase. Reset phases for this region? (y/n) ','s');
            % %             if strcmp(res,'y')
            % %                 phi0s = [];
            % %                 phi1s = [];
            % %                 pivots = [];
            % %             else
            % %                 disp('Aborting phase set...')
            % %                 return;
            % %             end
            % %         else
            % %             phi0s = phi0s(1);
            % %             phi1s = phi1s(1);
            % %             pivots = pivots(1);
            % %         end
            % %     end
            % %     dataObj.psSetter = PhaseAdj(prevData_foc,"ppmAx",dataObj.xppm,...
            % %                           "applyPhaseFun",@applyPsFun,...
            % %                           "userData",{procObj,dataObj,prevData},...
            % %                           "phi0",phi0s,...
            % %                           "phi1",phi1s,...
            % %                           "pivot_ind",pivots);
            % 
            % %%
            % 
            % 
            % end
            
            psStep = ProcStep(@applyPhases,"local","cacheable",false,...
                                                   "params",{},...
                                                   "tag",'phasing',...
                                                   'dataObj',obj);
            psSetter = ProcSetter(psStep,obj,@psSetterInit,@psSetterUpdate,@psSetterApply,@psSetterIsActive);
            psStep.setter = psSetter;
            obj.addProcStep("r",psStep,-1);
            %%

            %% Baseline Correction
            function bsData = applyBaselines(procObj,~,data)
                if isempty(procObj.params)
                    %no baseline correction
                    bsData = data;
                    return;
                end
                lambdas = procObj.params{1};
                ratios = procObj.params{2};
                itermaxes = procObj.params{3};
                
                if ~all(isequal(size(data,2:ndims(data)),size(lambdas)))
                    disp('WARNING: Data size has changed, clearing baseline parameters!');
                    procObj.params = {};
                    bsData = data;
                    return;
                end
                nPts = size(data,1);
                dataSize = size(data);
                nOtherDims = sum(dataSize(dataSize~=1))-nPts;
                data_flat = reshape(data,[nPts,nOtherDims]);
                lambdas = lambdas(:);
                ratios = ratios(:);
                itermaxes = itermaxes(:);
                for idx = 1:nOtherDims
                    if all(~isempty([lambdas(idx),ratios(idx),itermaxes(idx)]))
                        data_flat(:,idx) = arpls(data_flat(:,idx),lambdas(idx),...
                                                                ratios(idx),...
                                                                itermaxes(idx));
                    end
                end
                bsData = reshape(data_flat,size(data));
            end
            bsStep = ProcStep(@applyBaselines,"local","cacheable",false,...
                                                      "dataObj",obj,...
                                                      "params",{},...
                                                      "tag",'baseline');
            obj.addProcStep("r",bsStep,-1);
            %%

            obj.proc.cache.kData = obj.kDataRaw;
            obj.proc.cache.rData = K_R_Tform(obj.kDataRaw,obj.sysParams.kspaceTforms);
        end

        function val = get.xppm(obj)
            %Using get func for xppm allows axis to adapt to procs like zf
            val = NaN;
            if ~isempty(obj.sysParams.ppmBW)
			    xppmAxis = (obj.sysParams.ppmBW/obj.dimF)*(1:obj.dimF);
			    val = xppmAxis-(obj.sysParams.ppmBW/2-obj.sysParams.ppmCF-obj.prefs.ppmShift);
            end
        end
        
        function setDims(obj,dataRef)
            arguments
                obj
                dataRef = [];
            end
            if ~isempty(dataRef)
                refSize = size(dataRef);
            else
                refSize = size(obj.kData);
            end
            obj.dimF = refSize(1);
            obj.dimX = refSize(2);
            obj.dimY = refSize(3);
            obj.dimZ = refSize(4);
            obj.dimFG = refSize(5:end);
            obj.nDims = ndims(dataRef);
        end

        function initFocus(obj)
            obj.rFocus = repmat({':'},obj.nDims,1);
            obj.kFocus = repmat({':'},obj.nDims,1);
        end

        % function [f,x,y,z,fg] = getFocus(obj,domain)
        %     %this should not be used
        %     arguments
        %         obj
        %         domain {mustBeMember(domain,{'k','r'})}
        %     end
        %     if strcmp(domain,'k')
        %         focus = obj.kFocus;
        %     else
        %         focus = obj.rFocus;
        %     end
        %     dimSizes = {obj.dimF,obj.dimX,obj.dimY,obj.dimZ,obj.dimFG};
        %     for dim = 1:numel(focus)
        %         if strcmp(focus{dim},':')
        %             focus{dim} = 1:dimSizes{dim};
        %         end
        %     end
        %     f = focus{1};
        %     x = focus{2};
        %     y = focus{3};
        %     z = focus{4};
        %     fg = focus{5};
        % end
        
        % function params = get.rProcParams(obj)
        %    %Parses rProcParams array and returns param structure of voxel
        %    %indicated by focus.
        %    [~,x,y,z,rep] = obj.getFocus("r");
        %    if ~isscalar(x)||...
        %       ~isscalar(y)||...
        %       ~isscalar(z)||...
        %       ~isscalar(rep)
        % 
        %         %warning('WARNING: Unable to access rProcParams for nonSingular focus!');
        %         params = [];
        %         return
        %    end
        %    paramsArr = obj.rProcParamsCell(:,x,y,z,rep);
        %    params = struct('phi0',paramsArr(1), ...
        %                    'phi1',paramsArr(2), ...
        %                    'pivotVal',paramsArr(3), ...
        %                    'pivotMode',paramsArr(4), ...
        %                    'appliedPhase',paramsArr(5),...
        %                    'arpls_lambda',paramsArr(6),...
        %                    'arpls_ratio',paramsArr(7),...
        %                    'arpls_itermax',paramsArr(8),...
        %                    'baseline',paramsArr(9));
        % end

        % function set.rProcParams(obj,s)
        %     %Since rProcParams are stored in an array, editing the stuct
        %     %requires setting rProcParams = struct. (i.e. unable to set
        %     %individual fields as you would with normal struct)
        %     arguments
        %         obj
        %         s 
        %     end
        %     [x,y,z,rep] = obj.getFocus('r');
        %     if ~isscalar(x)||...
        %        ~isscalar(y)||...
        %        ~isscalar(z)||...
        %        ~isscalar(rep)
        % 
        %         warning('WARNING: Unable to set rProcParams for nonSingular focus!');
        %         return
        %     end
        %     sFields = fieldnames(s);
        %     fields = fieldnames(obj.rProcParams);
        %     paramsArr = squeeze(obj.rProcParamsCell(:,x,y,z,rep));
        %     for idx = (1:length(sFields))
        %         ind = find(strcmp(fields,sFields{idx}), 1);
        %         if ~isempty(ind)
        %             paramsArr(idx) = {s.(sFields{idx})};
        %         end
        %     end
        %     obj.rProcParamsCell(:,x,y,z,rep) = paramsArr;
        % end
        
        %%%%%%%%%%%%% RESETTING/UPDATING DATA %%%%%%%%%%%%%%%%%

        % function revert(obj,toRevert,region)
        %     % Allows for reversion of processing parameters by default this
        %     % will operate on the whole data set. If you want to revert
        %     % certain voxels use region = {(x1,...,xn),
        %     %                              (y1,...,zn),
        %     %                              (z1,...,zn),
        %     %                              (rep1,...repn)}
        %     %   NOTE: if zf is reverted then the obj focus will be reset
        %     %   since it cannot be guarenteed that the existing focus won't
        %     %   be out of range for the new data size.
        %     arguments
        %         obj;
        %         toRevert {mustBeMember(toRevert,{'all', ...
        %                                          'blank', ...
        %                                          'lb', ...
        %                                          'zf', ...
        %                                          'Foc_Baseline', ...
        %                                          'Foc_Phase',...
        %                                          'Region_Baselines',...
        %                                          'Region_Phases'})} = 'all'
        %         region = [];
        %     end
        %     if isempty(region)
        %         region = {1:obj.dimX;...
        %                   1:obj.dimY;...
        %                   1:obj.dimZ;...
        %                   1:obj.dimFG};
        %     end
        %     [x,y,z,~] = obj.getFocus("r");
        %     switch toRevert
        %         case 'all'
        %             obj.kProcParams.blank = [];
        %             obj.kProcParams.zf = [];
        %             obj.kProcParams.lb = [];
        %             obj.resetPhasing(region);
        %             obj.resetBaselines(region);
        %             obj.resetFocus;
        %         case 'blank'
        %             obj.kProcParams.blank = [];
        %         case 'lb'
        %             obj.kProcParams.lb = [];
        %         case 'zf'
        %             obj.kProcParams.zf = [];
        %             obj.resetFocus;
        %         case 'Foc_Baseline'
        %             region = {x,y,z,1:obj.dimFG};
        %             obj.resetBaselines(region);
        %         case 'Foc_Phase'
        %             region = {x,y,z,1:obj.dimFG};
        %             obj.resetPhasing(region);
        %         case 'Region_Baselines'
        %             obj.resetBaselines(region);
        %         case 'Region_Phases'
        %             obj.resetPhasing(region);
        %         otherwise
        %             warning('Not a valid revert request!');
        %     end
        %     obj.updateProc;
        % end
        % 
        % function resetBaselines(obj,region)
        %     %Clear baselines in specified region 
        %     %   (by default region is whole dataset)
        %     arguments
        %         obj 
        %         region = [];
        %     end
        %     if isempty(region)
        %         region = {1:obj.dimX;...
        %                   1:obj.dimY;...
        %                   1:obj.dimZ;...
        %                   1:obj.dimFG};
        %     end
        %     regionSize = [1,length(region{1}),length(region{2}),...
        %                   length(region{3}),length(region{4})];
        %     obj.rProcParamsCell(6:9,region{:}) = cell(regionSize);
        % end
        % 
        % function resetPhasing(obj,region)
        %     %Clear phasing in specified region 
        %     %   (by default region is whole dataset)
        %     arguments
        %         obj 
        %         region = [];
        %     end
        %     if isempty(region)
        %         region = {1:obj.dimX;...
        %                   1:obj.dimY;...
        %                   1:obj.dimZ;...
        %                   1:obj.dimFG};
        %     end
        %     regionSize = [5,length(region{1}),length(region{2}),...
        %                   length(region{3}),length(region{4})];
        %     obj.rProcParamsCell(1:5,region{:}) = cell(regionSize);
        % end

        function updateProc(obj,opts)
            %reprocess data according to k/r proc parameters.
            arguments
                obj
                opts.force = false %force update all steps
                opts.breakAtStep = []; %abort update at given step
            end
            breakStep = opts.breakAtStep;
            if ~isempty(breakStep)
                assert(isa(breakStep,'ProcStep'));
            end
            %get all processing steps:
            kProcSteps = obj.proc.kProcSteps;
            rProcSteps = obj.proc.rProcSteps;
            if ~opts.force
                %Use currency tags to find most current point in proc stream:
                forkPoint = [];
                for idx = 1:numel(kProcSteps)
                    step = kProcSteps{idx};
                    if ~step.current
                        forkPoint = idx;
                        break;
                    end
                end
                if isempty(forkPoint)
                    for idx = 1:numel(rProcSteps)
                        step = rProcSteps{idx};
                        if ~step.current
                            forkPoint = idx+numel(kProcSteps);
                        end
                    end
                end
                if isempty(forkPoint)
                    %all steps are current
                    return;
                end
                
                %Work back from fork point to see if there are any usable
                %states to restart processing stream from:
                revertState = [];
                revertProcInd = [];
                for idx = forkPoint:-1:1
                    state = [];
                    if idx>numel(kProcSteps)
                        if ~isempty(rProcSteps)
                            state = rProcSteps{idx-numel(kProcSteps)}.cachedState;
                        end
                    else
                        if ~isempty(kProcSteps)
                            state = kProcSteps{idx}.cachedState;
                        end
                    end
                    if ~isempty(state)
                        %Found valid restart point. Set and exit search
                        revertState = state;
                        revertProcInd = idx;
                        break;
                    end
                end
                %State cached by default at fft step. Check if fork point
                %is after this step. If so, use the cached kData as new
                %starting point
                if isempty(revertState)&&...
                    ~isempty(obj.proc.cache.kData)&&...
                    forkPoint>numel(kProcSteps)
    
                    revertState = obj.proc.cache.kData;
                    revertProcInd = numel(kProcSteps)+1;
                end
                if isempty(revertState)
                    %All cached states are invalid => start from raw
                    revertState = obj.kDataRaw;
                    revertProcInd = 1;
                end
            else
                revertState = obj.kDataRaw;
                revertProcInd = 1;
            end
            %Determine which steps are needed to apply to k and r domains:
            toDo_kProcs = revertProcInd:numel(kProcSteps);
            toDo_rProcs = max(revertProcInd-numel(kProcSteps),1):numel(rProcSteps);
            %currState holds entire dataset as it moves through processing
            %stream
            currState = revertState;
            if ~isempty(toDo_kProcs)
                %If there is processing to be dones on the k-space, do this
                %processing:
                for idx = toDo_kProcs
                    %do each specified kProc and cache along the way
                    procStep = kProcSteps{idx};
                    currState = procStep.processData(currState,'updateParams',true,...
                                                                   'attemptCache',true);
                    if isempty(currState)
                        if ~isempty(procStep.tag)
                            fprintf('Update aborted in k domain at %s step\n',procStep.tag);
                        else
                            fprintf('Update aborted in k domain at step %d\n',idx);
                        end
                        return;
                    end
                    if isequal(breakStep,procStep)
                        if ~isempty(procStep.tag)
                            fprintf('Update aborted at requested break step (%s)\n',procStep.tag);
                        else
                            fprintf('Update aborted at requested break step #%d\n',idx);
                        end
                        return;
                    end
                    kProcSteps{idx} = procStep;
                end
            end
            
            %Always cache the final k-space before fft:
            kData_cache = currState;
            %Apply specified transforms to move to r-space:
            currState = K_R_Tform(currState,obj.sysParams.kspaceTforms);
            if ~isempty(toDo_rProcs)
                for idx = toDo_rProcs
                    %do each specified rProc and cache along the way
                    procStep = rProcSteps{idx};
                    currState = procStep.processData(currState,'updateParams',true,...
                                                                   'attemptCache',true);
                    if isempty(currState)
                        if ~isempty(procStep.tag)
                            fprintf('Update Aborted in r domain at %s step\n',procStep.tag);
                        else
                            fprintf('Update Aborted in r domain at step %d\n',idx);
                        end
                        return;
                    end
                    if isequal(breakStep,procStep)
                        if ~isempty(procStep.tag)
                            fprintf('Update aborted at requested break step (%s)\n',procStep.tag);
                        else
                            fprintf('Update aborted at requested break step #%d\n',idx);
                        end
                        return;
                    end
                    rProcSteps{idx} = procStep;
                end
            end
            %Update list of kProc steps:
            obj.proc.kProcSteps = kProcSteps;
            obj.proc.cache.kData = kData_cache;
            obj.proc.rProcSteps = rProcSteps;
            %Always save final state:
            obj.proc.cache.rData = currState;
            %Update data dimensions:
            obj.setDims(currState);
            
            if ~isempty(toDo_rProcs)||~isempty(toDo_kProcs)
                %something has been updated => notify listener
                notify(obj,'procChanged');
            end
        end

        %%%%%%%%%%%%% CORE PROCESSING FUNCTIONS %%%%%%%%%%%%%%%%%

        % function psData = applyPhases(obj,data)
        %     %grabs phase data from obj.rProcParamsCell and returns phased
        %     %data
        %     phaseMat_curr = obj.rProcParamsCell(5,:,:,:,:,:);
        %     phaseMat_curr(cellfun('isempty',phaseMat_curr)) = {zeros(obj.dimF,1)};
        %     psData = data.*exp(1i*deg2rad(cell2mat(phaseMat_curr)));
        % end
        % 
        % function bsData = applyBaselines(obj,data)
        %     %grabs baseline data from obj.rProcParamsCell and returns phased
        %     %data
        %     baseMat_curr = obj.rProcParamsCell(6,:,:,:,:,:);
        %     baseMat_curr(cellfun('isempty',baseMat_curr)) = {zeros(obj.dimF,1)};
        %     bsData = data - cell2mat(baseMat_curr);
        % end
        % 
        % function setBlanking(obj,blankInd)
        %     obj.kProcParams.blank = blankInd;
        %     obj.setProcFunState('bk',false);
        %     obj.updateProc;
        % end
        % 
        % function setLB(obj,lb)
        %     obj.kProcParams.lb = lb;
        %     obj.setProcFunState('lb',false);
        %     obj.updateProc;
        % end
        % 
        % function setZF(obj,zf)
        % 
        %     if ~all(cellfun(@isempty,obj.rProcParamsCell),"all")
        %         res = input('WARNING: Existing processing in the real domain will be cleared. Proceed? (y/n)','s');
        %         if ~strcmp(res,'y')
        %             return;
        %         end
        %     end
        % 
        %     obj.kProcParams.zf = zf;
        % 
        %     obj.setProcFunState('zf',false);
        %     obj.updateProc;
        % end
        % 
        
        % function obj = applyPhase_old(obj,zeroOrder,pivotVal,pivotSetting,firstOrder)
        %     %Apply a linear phase to the voxel specified by obj.focus
        %     % - zeroOrder: phi0 zeroth order phase parameter in degrees
        %     % - pivotVal: value around which to center linear phasing. can
        %     %   be a ppm value or integer index
        %     % - pivotSetting: specifies the type of pivotVal
        %     %       (either 'ppm' or 'ind')
        %     % - firstOrder: phi1 first order phase parameter
        %     % opts.show: (F => supresses listener)
        % 
        %     arguments
        %         obj
        %         zeroOrder = NaN %deg
        %         pivotVal = NaN;
        %         pivotSetting = NaN % 'ppm' or 'ind'
        %         firstOrder = NaN %deg
        %     end
        %     % obj.suppressFShow = true;
        %     [x,y,z,rep] = obj.getFocus("r");
        %     params = obj.rProcParams;
        % 
        %     if isnan(zeroOrder)
        %         zeroOrder = params.phi0; 
        %     end
        % 
        %     if isnan(firstOrder) 
        %         firstOrder = params.phi1; 
        %     end
        %     params.phi0 = zeroOrder;
        %     params.phi1 = firstOrder;
        % 
        %     if isnan(pivotSetting)
        %         pivotSetting = params.pivotMode;
        %     else
        %         params.pivotMode = pivotSetting;
        %     end
        % 
        %     if isnan(pivotVal)
        %         pivotVal = params.pivotVal;
        %     else
        %         params.pivotVal = pivotVal;
        %     end
        %     if ~isnan(zeroOrder)     
        %         if ~isnan(firstOrder)
        %             if isnan(pivotSetting)
        %                 error("A pivot mode must be set for higher order phasing!");
        %             end
        %             if isnan(pivotVal)
        %                 error("A pivot value must be set for higher order phasing!");
        %             end
        %             switch pivotSetting
        %                 case 'ppm'
        %                     pivotInd = ppm2ind(obj.xppm,pivotVal);
        %                 case 'ind'
        %                     pivotInd = pivotVal;
        %                 otherwise
        %                     error("Valid pivot settings are: 'ppm' or 'ind'");
        %             end
        %             [~,phase] = ps(obj.rData(:,x,y,z,rep),zeroOrder,pivotInd,firstOrder);
        %             params.appliedPhase = phase;
        %         else
        %             [~,phase] = ps(obj.rData(:,x,y,z,rep),zeroOrder);
        %             params.appliedPhase = phase;
        %         end
        %     end
        %     obj.rProcParams = params;
        %     obj.updateProc;
        % end
                
        %%%%%%%%%%%%% INTERACTIVE PROCESSING FUNCTIONS %%%%%%%%%%%%%%

        % function uisetfoc(obj,domain)
        %     arguments
        %         obj
        %         domain {mustBeMember(domain,{'k','r'})}
        %     end
        % 
        %     function loadFoc(~,~,focObj)
        %         focNavAx = focObj.dispAx;
        %         if isvalid(focNavAx)
        %             currFoc = focNavAx.FocNav.focus;
        %             if strcmp(domain,'k')
        %                 obj.kFocus = currFoc;
        %             else
        %                 obj.rFocus = currFoc;
        %             end
        %         end
        %     end
        %     function focStopped(~,~)
        %         switch domain
        %             case 'k'
        %                 obj.kFocAx = [];
        %             case 'r'
        %                 obj.rFocAx = [];
        %         end
        %     end
        %     axMaps = {obj.xppm,...
        %               1:obj.dimX,...
        %               1:obj.dimY,...
        %               1:obj.dimZ,...
        %               1:obj.dimFG};
        % 
        %     if strcmp(domain,'k')
        %         if ~isempty(obj.kFocAx)
        %             warning('Already setting kFocus!');
        %             return;
        %         end
        %         initFoc = obj.kFocus;
        %         axMaps{1} = 1:obj.dimF;
        %         data = obj.kData;
        %         dimLbls = {'kt','kx','ky','kz','frames'};
        %     else
        %         if ~isempty(obj.rFocAx)
        %             warning('Already setting rFocus!');
        %             return;
        %         end
        %         initFoc = obj.rFocus;
        %         data = obj.rData;
        %         dimLbls = {'Chemical Shift (ppm)','x','y','z','frames'};
        %     end
        % 
        %     focNav = ndMRViewer(data,"axMaps",axMaps, ...
        %                              "initFoc",initFoc, ...
        %                              "FocChangedFcn",@loadFoc, ...
        %                              "dimLbls",dimLbls,...
        %                              'intensityLbl',"MR Signal (a.u.)");
        %     switch domain
        %         case 'k'
        %             obj.kFocAx = focNav.dispAx;
        %         case 'r'
        %             obj.rFocAx = focNav.dispAx;
        %     end
        %     fig = ancestor(focNav.dispAx,'figure');
        %     fig.DeleteFcn = @(src,evt) focStopped(src,evt);
        % end

        function fig = autoBase(obj,reps,opts)
            %Performs Auto-Baselining to real voxel specified by obj.focus
            %using Asymmetrically Reweighted Penalized Least Squares 
            %algorithm translated from: 
            %https://nirpyresearch.com/two-methods-baseline-correction-spectral-data/
            %
            % - reps: which reps of voxel to apply baseline to. by default
            %   a baseline is calculated for all reps but the first rep in
            %   the series is used for display
            % 
            % - opts.lambda: smoothing parameter used by arpls algoritm
            %       - term scales non-linearly so pass it as exp(##).
            % - opts.ratio: convergence ratio used to initiate early break 
            %   out of iterative loop in arpls
            % - opts.itermax: integer max number of iterations used by
            %   arpls algorithm
            %
            % - opts.show (F => disables listener)
            % - opts.interact: (T => input dialogue implemented to allow
            %   user to visualize baseline)
            % - opts.keepfig: 
            %   (T => plot used in interactive process is kept
            %   after method termination)
            %   (F => plot is automatically deleted after method
            %   termination)
            arguments
                obj 
                reps = [];
                opts.lambda {mustBeNumeric} = exp(4);
                opts.ratio {mustBeNumeric} = 0.05;
                opts.itermax {mustBeInteger} = 100;
                opts.show logical = true;
                opts.interact logical = true;
                opts.keepFig logical = false;
            end
            [x,y,z,~] = obj.getFocus('r');
            specStackRaw = squeeze(obj.rData(:,x,y,z,:));
            specStack = specStackRaw;
            if isempty(reps)
                reps = (1:obj.dimFG);
            end
            working = true;
            lambda = opts.lambda;
            ratio = opts.ratio;
            itermax = opts.itermax;
            if opts.interact
                ax = axes(figure);
            end
            focRep = obj.focus.viewRep;
            baselines = zeros(size(specStack));
            applyBase = false;
            step = 1;
            params = [0,0,0];
            while working
                if ~all(params==[lambda,ratio,itermax])
                    specStack = specStackRaw;
                    for rep = reps
                        baselines(:,rep) = arpls(squeeze(real(specStack(:,rep))), ...
                                    lambda,ratio,itermax);
                        specStack(:,rep) = specStack(:,rep)-baselines(:,rep);
                    end
                end
                params = [lambda,ratio,itermax];

                if opts.interact
                    xLim = ax.XLim;
                    yLim = ax.YLim;
                    resize = ~isempty(ax.Children);
                    cla(ax);
                    hold(ax,"on");
                    plot(ax,obj.xppm,real(specStackRaw(:,focRep)));
                    plot(ax,obj.xppm,real(specStack(:,focRep)));
                    plot(ax,obj.xppm,baselines(:,focRep),LineStyle="--",Color='black');
                    hold(ax,'off');
                    axis(ax,'padded');
                    zoom(ax,'reset');
                    if resize
                        ax.XLim = xLim;
                        ax.YLim = yLim;
                    end
                    obj.setupPlot(ax,'type','rPlot','mode','real','xAx','ppm');
                    legend(ax,{'Raw Spectrum','Subtracted Spectrum','baseline'});
                end
                lam_exp = log(lambda);
                if opts.interact
                    res = input(sprintf('Baseline [lambda,ratio,itermax,step] = [exp(%0.2f),%0.2f,%d,%.3f]',lam_exp,ratio,itermax,step),"s");
                    switch res
                        case 'w'
                            lam_exp = lam_exp+step;
                            lambda = exp(lam_exp);
                        case 'q'
                            if lam_exp-step>0
                                lam_exp = lam_exp-step;
                                lambda = exp(lam_exp);
                            else
                                disp('Lambda exponent must be positive!');
                            end
                        case 's'
                            ratio = ratio+step;
                        case 'a'
                            if ratio-step>0
                                ratio = ratio-step;
                            end
                        case 'x'

                            if isinteger(int8(itermax+step))
                                itermax = itermax+step;
                            else
                                disp('Itermax must be Integer!')
                            end
                        case 'z'
                            if isinteger(int8(itermax-step))&&itermax-step>0
                                itermax = itermax-step;
                            else
                                disp('Itermax must be a positve Integer!')
                            end
                        case 'i'
                            step = step*10;
                        case 'k'
                            step = step/10;
                        case 'apply'
                            working = false;
                            applyBase = true;
                        case 'help'
                            fprintf(['\nlambda  (inc/dec) = (w/q)\n' ...
                                       'ratio   (inc/dec) = (s/a)\n' ...
                                       'itermax (inc/dec) = (x/z)\n' ...
                                       'step    (inc/dec) = (i/k)\n' ...
                                       'apply => apply processing\n' ...
                                       'esc => exit processing\n\n']);
                        case 'esc'
                            working = false;
                        otherwise
                            disp('Invalid response');
                    end
                else
                    working = false;
                    applyBase = true;
                end
                
            end
            
            if ~applyBase && opts.interact
                deciding = true;
                while deciding
                    inpt = input('Would you like to save the baseline from this session? (y/n): ','s');
                    switch inpt
                        case 'y'
                            applyBase = true;
                            deciding = false;
                        case 'n'
                            deciding = false;
                        otherwise
                            disp('Unrecognized response.');
                    end
                end
            end
            if opts.interact && isvalid(ax) && ~opts.keepFig
                delete(ax.Parent);
                fig = [];
            else
                if opts.interact && isvalid(ax)
                    fig = ax.Parent;
                end
            end

            if applyBase
                for rep = reps
                    obj.rProcParamsCell{6,x,y,z,rep} = baselines(:,rep);
                end
                obj.rData(:,x,y,z,reps) = specStack(:,reps);
                obj.updateProc;
            end
        end
        
        function manualPhase(obj,reps)
            %Allows user to perform interactive linear phasing on voxel
            %specified by obj.focus.
            % - reps: which reps of voxel to apply phasing to. by default
            %   phasing is calculated for all reps but the current viewRep
            %   is used for display
            arguments
                obj;
                reps = [];
            end
            [x,y,z,rep] = obj.getFocus("r");
            params = obj.rProcParams;
            if isempty(reps)
                reps = (1:obj.dimFG);
            end
            if isempty(params.pivotMode)
                params.pivotMode = 'ppm';
            end
            keepGoing = true;
            phi0 = params.phi0;
            phi1 = params.phi1;
            step = 10;
            pivotVal = params.pivotVal;
            if ~isempty([phi0,phi1,pivotVal])
                obj.revert("Region_Phases",{x,y,z,reps});
                specData = obj.rData(:,x,y,z,rep);
                obj.applyPhase_old(phi0,pivotVal,params.pivotMode,phi1);
            else
                specData = obj.rData(:,x,y,z,rep);
            end
            if isempty(phi0)
                phi0 = 0;
            end
            if isempty(phi1)
                phi1 = 0;
            end
            if isempty(pivotVal)
                pivotVal = 0;
            end
            
            proceed = false;
            if ~isempty(params.baseline)
                deciding = true;
                while deciding
                    res = input('Warning! Remove existing baseline? (y/esc)','s');
                    switch res
                        case 'y'
                            obj.revert("Region_Baselines",{x,y,z,reps});
                            proceed = true;
                            deciding = false;
                        case 'esc'
                            deciding  = false;
                        otherwise
                            disp('Unrecognized Response');
                    end
                end
            else
                proceed = true;
            end

            if proceed
                if strcmp(params.pivotMode,'ppm')
                    pivotInd = ppm2ind(obj.xppm,pivotVal);
                else
                    pivotInd = pivotVal;
                end
                ax = axes(figure);
                psSpec = ps(specData,phi0,pivotInd,phi1);
                mrPlot("spiral",psSpec,ax,{obj.xppm});
                ppmStep = max(round((max(obj.xppm)-min(obj.xppm))/(20*5))*5,5);
                obj.setupPlot(ax,"type",'spiral','ppmStep',ppmStep,'xAx','ppm');
                view(ax,0,90);
                axis(ax,'padded');
                zoom(ax,'reset');
                saved = false;
                while keepGoing
                    if strcmp(params.pivotMode,'ppm')
                        pivotInd = ppm2ind(obj.xppm,pivotVal);
                    else
                        pivotInd = pivotVal;
                    end
                    if ~isvalid(ax)
                        ax = axes(figure); %#ok<LAXES>
                    end
                    xLim = ax.XLim;
                    yLim = ax.YLim;
                    v = get(ax,'View');
                    mrPlot("spiral",ps(specData,phi0,pivotInd,phi1),ax,{obj.xppm});
                    view(ax,v(1),v(2));
                    axis(ax,'padded');
                    zoom(ax,'reset');
                    obj.setupPlot(ax,type="spiral",xAx="ppm",ppmStep=ppmStep);
                    ax.XLim = xLim;
                    ax.YLim = yLim;
                    res = input(sprintf("phi0,pivot,phi1,step = [%08.4f,%08.4f,%08.4f,%08.4f]",phi0,pivotVal,phi1,step),"s");
                    switch res
                        case 'w'
                            phi0 = phi0+step;
                        case 'q'
                            phi0 = phi0-step;
                        case 'x'
                            phi1 = phi1+step;
                        case 'z'
                            phi1 = phi1-step;
                        case 'i'
                            step = step*10;
                        case 'k'
                            step = step*0.1;
                        case 's'
                            pivotVal = pivotVal+step;
                        case 'a'
                            pivotVal = pivotVal-step;
                        case 'help'
                            fprintf(['\nphi0  (inc/dec) = (w/q)\n' ...
                                       'pivot (inc/dec) = (s/a)\n' ...
                                       'phi1  (inc/dec) = (x/z)\n' ...
                                       'step  (inc/dec) = (i/k)\n' ...
                                       'pivot => enter value\n' ...
                                       'pivotMode => enter mode\n' ...
                                       'reset => revert phasing\n' ...
                                       'apply => apply processing\n' ...
                                       'esc => exit processing\n\n']);

                        case 'pivotMode'
                            mode = input('Pivot Mode (''ppm''/''ind''): ','s');
                            if strcmp(mode,'ppm')||strcmp(mode,'ind')
                                params.pivotMode = mode;
                            else
                                warning('Invalid Pivot Mode!');
                            end
                        case 'pivot'
                            newPivot = input('Pivot Val: ','s');
                            pivotVal = str2double(newPivot);
                        case 'reset'
                            phi0 = 0;
                            phi1 = 0;
                            step = 10;
                        case 'esc'
                            keepGoing = false;
                        case 'apply'
                            params.phi0 = phi0;
                            params.phi1 = phi1;
                            params.pivotVal = pivotVal;
                            if strcmp(params.pivotMode,'ppm')
                                pivotInd = ppm2ind(obj.xppm,pivotVal);
                            else
                                pivotInd = pivotVal;
                            end
                            for rep = reps
                                [~,phase] = ps(specData,params.phi0,pivotInd,params.phi1);
                                obj.rProcParamsCell{1,x,y,z,rep} = params.phi0;
                                obj.rProcParamsCell{2,x,y,z,rep} = params.phi1;
                                obj.rProcParamsCell{3,x,y,z,rep} = params.pivotVal;
                                obj.rProcParamsCell{4,x,y,z,rep} = params.pivotMode;
                                obj.rProcParamsCell{5,x,y,z,rep} = phase;
                            end                            
                            keepGoing = false;
                            saved = true;
                         otherwise
                            disp('Unrecognized Response');
                    end
                    
                end
                if ~saved
                    deciding = true;
                    while deciding
                        inpt = input('Would you like to save the phasing from this session? (y/n): ','s');
                        switch inpt
                            case 'y'
                                params.phi0 = phi0;
                                params.phi1 = phi1;
                                params.pivotVal = pivotVal;
                                if strcmp(params.pivotMode,'ppm')
                                    pivotInd = ppm2ind(obj.xppm,pivotVal);
                                else
                                    pivotInd = pivotVal;
                                end
                                for rep = reps
                                    [~,phase] = ps(specData,params.phi0,pivotInd,params.phi1);
                                    obj.rProcParamsCell{1,x,y,z,rep} = params.phi0;
                                    obj.rProcParamsCell{2,x,y,z,rep} = params.phi1;
                                    obj.rProcParamsCell{3,x,y,z,rep} = params.pivotVal;
                                    obj.rProcParamsCell{4,x,y,z,rep} = params.pivotMode;
                                    obj.rProcParamsCell{5,x,y,z,rep} = phase;
                                end    
                                deciding = false;
                            case 'n'
                                deciding = false;
                            otherwise
                                disp('Unrecognized response.');
                        end
                    end
                end
                if isvalid(ax)
                    delete(ax.Parent);
                end
            end
            obj.updateProc;
        end
        
        %%%%%%%%%%%%% DATA ANALYSIS %%%%%%%%%%%%%%

        function [ints,specs,zeroPhases] = autoInts(obj,bds,bdsType,reps,opts)
            %Faster/more streamlined version of autoIntsSlow. autoInts is
            %completely self contained and utilizes a more fleshed-out
            %symmetrical scoring method for zeroth order phasing.
            %
            % - bds: bounds surrounding peak. Bounds do not need to be
            %        particularly tight but they should only contain one peak
            % - bdsType: specifies if bds are indecies or ppm values
            % - reps: reps to sum together. if reps = (1:3) then the first
            %         three frames are combined to calculate integrals
            % - thresh: threshold (in units of std of data within bounds
            %       excluding peak) needed for the integral to be
            %       calculated
            % - show: (T => a plot is displayed and is updated as voxel
            %         integrals are calculated)
            
            arguments
                obj 
                bds 
                bdsType 
                reps;
                opts.showProc = true;
                opts.showSpecGrid = false;
                opts.showPhases = false;
            end
            tic;
            [~,~,z,~] = obj.getFocus("r");
            ints = zeros(obj.dimX,obj.dimY);
            if opts.showProc
                ax = axes(figure);
                axis(ax,"square");
            else
                ax = axes(figure,Visible=false);
                delete(ax);
                %shh no comment
            end
            switch bdsType
                case 'ppm'
                    bds(1) = ppm2ind(obj.xppm,bds(1));
                    bds(2) = ppm2ind(obj.xppm,bds(2));
                case 'ind'
                    %do nothing
                otherwise
                    error("Valid bounds types are: 'ppm' or 'ind'");
            end
            bds = sort(bds);
            specs = zeros(numel(bds(1):bds(2)),obj.dimX,obj.dimY,1);
            count = 0;
            zeroPhases = zeros(size(ints));
            specs_raw = squeeze(sum(obj.rData(:,:,:,z,reps),5));
            for x = (1:obj.dimX)
                if isvalid(ax)
                    imagesc(ax,ints');
                    if strcmp(bdsType,'ind')
                        title(ax,sprintf('Phased integrals on range [%0.2f, %0.2f] (ind)',bds(1),bds(2)));
                    else
                        title(ax,sprintf('Phased integrals on range [%0.2f, %0.2f] (ppm)',obj.xppm(bds(1)),obj.xppm(bds(2))))
                    end
                end
                for y = (1:obj.dimY)
                    count = count+1;
                    progress = count/(obj.dimX*obj.dimY);
                    if isvalid(ax)
                        subtitle(ax,sprintf('Progress: %0.f%%',progress*100));
                        drawnow;
                    end
                    
                    data = specs_raw(bds(1):bds(2),x,y);
                    %corse phase rotation to get peak
                    startPhase = 0;
                    maxVal = 0;
                    for p = 0:10:360
                        data_p = real(ps(data,p));
                        %flatten:
                        slope = (data_p(end)-data_p(1))/(numel(data_p)-1);
                        data_flat = data_p(:)' - (slope*(1:numel(data_p))+data_p(1));
                        maxData = max(data_flat);
                        if maxData>maxVal
                            startPhase = p;
                            maxVal = maxData;
                        end
                    end
                    [~,locs,w,~] = findpeaks(real(ps(data,startPhase)),SortStr='descend');
                    
                    
                    if ~isempty(locs)
                        
                        p0Guess = -rad2deg(unwrap(angle(data(locs(1)))));
                        options = optimset('MaxFunEvals',500*numel(data), ...
                                           'MaxIter',500*numel(data),...
                                           'TolFun',1e-5,...
                                           'TolX',1e-5);
                        [p0,~,~] = fminsearch(@(p0)symScore(real(ps(data,p0)),locs(1),100*w(1)),p0Guess,options);
                        
                        zeroPhases(x,y) = p0;
                        psData = real(ps(data,p0));                                
                        base = arpls(psData);
                        psbsData = psData-base;

                        [~,locsPB,wPB,~] = findpeaks(psbsData,SortStr="descend");
                        if ~isempty(locsPB)
                                        
                            loc = locsPB(1);
                            wIntFac = 1;
                            w = wIntFac*wPB(1);
                            peakLoc = max(1,floor(loc-w/2)):...
                                      min(numel(psbsData),ceil(loc+w/2));
                            int = sum(psbsData(peakLoc));
                            ints(x,y) = abs(int);
                            specs(:,x,y) = psbsData;  
                        else
                            ints(x,y) = NaN;
                        end
                    else
                        ints(x,y) = NaN;
                    end
                end
            end
            if isvalid(ax)
                imagesc(ax,ints');
                if strcmp(bdsType,'ind')
                    title(ax,sprintf('Phased integrals on range [%0.2f, %0.2f] (ind)',bds(1),bds(2)));
                else
                    title(ax,sprintf('Phased integrals on range [%0.2f, %0.2f] (ppm)',obj.xppm(bds(1)),obj.xppm(bds(2))))
                end
                drawnow;
            end
            %obj.analysis{end+1} = struct('ints',ints,'bds',bds,'timeStamp',datetime('now'));
            fprintf('Completed with run time: %0.2f (s)\n',toc);
            if opts.showSpecGrid
                specGrid(specs,ints,"baseCmap",'parula');
            end
            if opts.showPhases
                imagesc(axes(figure),zeroPhases');
            end
        end

        function intsArr = peakInts(obj,intBds,bdsType,dataType,opts)
            % Performs integral between bounds of R-space voxel specified
            % by obj.focus.
            %   NOTE: 'integral' is not normalized by bounds. it is
            %   calculated simply as the sum of data over bounds range
            %
            % - intBds: bounds over which to integrate, 2x1 array with ppm
            %           or index values
            % - bdsType: use to specify the type of bounds used in intBds
            %           (either 'ppm' or 'ind')
            % - dataType: 'abs','real', or 'imag'. used to specify if the
            %             integral should be taken over the absolute, 
            %             real, or imaginary component of the spectrum.
            % - flipAdjust: whether to apply a correction to the flip angle
            %               used
            % - decayCorr: whether to correct for successive depletion of
            %              initial magnetization
            % - stack: 
            %   (T => integrals will be calculated for each
            %   repitition of specified voxel)
            %   (F => integral for only one repition specified by
            %   obj.focus.viewrep
            arguments
                obj
		        intBds (2,1) {mustBeNumeric};
                bdsType {mustBeMember(bdsType,{'ppm','ind'})};
                dataType {mustBeMember(dataType,{'abs','real','imag'})} = 'real';
		        opts.flipAdjust logical = false %correct integrals using flip ang
                opts.decayCorr logical = false %correct for polarization decay from measurements
                opts.stack logical = false;
            end
            [x,y,z,rep] = obj.getFocus('r');
            if opts.stack
                specStack = obj.rData(:,x,y,z,:);
            else
                specStack = obj.rData(:,x,y,z,rep);
            end
            switch bdsType
                case 'ppm'
                    [~,intStartInd] = min(abs(obj.xppm-min(intBds)));
			        [~,intEndInd] = min(abs(obj.xppm-max(intBds)));
                case 'ind'
                    intStartInd = min(intBds);
                    intEndInd = max(intBds);
            end
            switch dataType
                case 'abs'
			        intsArr = sum(abs(specStack((intStartInd:intEndInd),:)),1);
                case 'real'
                    intsArr = sum(real(specStack((intStartInd:intEndInd),:)),1);
                case 'imag'
                    intsArr = sum(imag(specStack((intStartInd:intEndInd),:)),1);
            end

			if opts.flipAdjust %#ok<ALIGN>
                if isnan(obj.sysParams.flipAng)
                    error('A flip angle is required to apply integral corrections!');
                else
  				    flipAngRad = obj.sysParams.flipAng*pi/180;	
				    for i = (1:length(intsArr)) %#ok<ALIGN>
                        if obj.sysParams.flipAng == 0
                            return
                        else
					        intsArr(i) = intsArr(i)/sin(flipAngRad);
                            if opts.decayCorr
                                if obj.sysParams.flipAng ~= 90
                                    intsArr(i) = intsArr(i)/(cos(flipAngRad)^(i-1));
                                end
                            end
                        end
                    end
                end
            end
        end
                        
        function tbl = analyze(obj,mode,opts)
            % Allows the user to perform interactive peak integration of
            % the real space spectrum specified by obj.focus. Results from
            % this analysis will be stored in the cell array obj.analysis.
            % Specifying a 'noise' region allows for reporting of stdev and
            % mean for assessing baselines
            % - stack: 
            %   (T => integrals will be calculated for each
            %   repitition of specified voxel)
            %   (F => integral for only one repition specified by
            %   obj.focus.viewrep
            % - opts.flipAdjust: whether to apply a correction to the flip angle
            %               used
            % - opts.decayCorr: whether to correct for successive depletion of
            %              initial magnetization
            % - opts.mode: complex component to use in analysis
            arguments
                obj 
                mode {mustBeMember(mode,{'real','abs','imag'})};
                opts.sig_squish logical = true;
                opts.sig_offset logical = true;
                opts.stack logical = true; 
                opts.flipAdjust logical = false;
                opts.decayCorr logical = false;
            end
            [x,y,z,rep] = obj.getFocus('r');
            specStack = obj.rData(:,x,y,z,:);
            ax = axes(figure);
            switch mode
                case 'real'
                    plot(ax,obj.xppm,real(specStack(:,rep)));
                case 'abs'
                    plot(ax,obj.xppm,abs(specStack(:,rep)));
                case 'imag'
                    plot(ax,obj.xppm,imag(specStack(:,rep)));
            end
            obj.setupPlot(ax,"type","rPlot","mode",mode,"xAx","ppm");
            working = true;
            intRegions = {};
            noiseRegions = {};
            overlays = {};
            localAnalysis = struct('ints',NaN,'noise',NaN,...
                'timeStamp',datetime('now'));
            savedAnalysis = false;
            while working
                for ind = (1:length(overlays))
                    if isvalid(overlays{ind})
                        delete(overlays{ind});
                    end
                end
                if ~isempty(intRegions)
                    delInds = [];
                    for ind = 1:length(intRegions)
                        if isvalid(intRegions{ind})
                            rectPts = intRegions{ind}.Vertices;
                            [xppmMin,xppmMax] = bounds(rectPts(:,1));
                            [yMin,yMax] = bounds(rectPts(:,2));
                            indMin = ppm2ind(obj.xppm,xppmMin);
                            indMax = ppm2ind(obj.xppm,xppmMax);
                            ppmStep = (xppmMax-xppmMin)/(indMax-indMin);
                            curveX = xppmMax:-ppmStep:xppmMin;
                            curveY = zeros(length(curveX),1);
                            switch mode
                                case 'real'
                                    curveY(1) = real(specStack(ppm2ind(obj.xppm,curveX(1)),rep));
                                case 'abs'
                                    curveY(1) = abs(specStack(ppm2ind(obj.xppm,curveX(1)),rep));
                                case 'imag'
                                    curveY(1) = imag(specStack(ppm2ind(obj.xppm,curveX(1)),rep));
                            end
                            
                            for idx = 2:length(curveX)
                                ppm = curveX(idx);
                                ii = ppm2ind(obj.xppm,ppm);
                                switch mode
                                    case 'real'
                                        curveY(idx) = curveY(idx-1)+...
                                                real(specStack(ii,rep));
                                    case 'abs'
                                        curveY(idx) = curveY(idx-1)+...
                                                abs(specStack(ii,rep));
                                    case 'imag'
                                        curveY(idx) = curveY(idx-1)+...
                                                imag(specStack(ii,rep));
                                end
                            end
                            if opts.sig_squish
                                curveSquish = (yMax-yMin)/(max(curveY)-min(curveY));
                                curveY = curveY.*curveSquish;
                            end
                            if opts.sig_offset
                                offset = 1.2*(yMax-yMin);
                            else
                                offset = yMin;
                            end
                            curveY = curveY+offset;
                            hold(ax,'on');
                            overlay = plot(ax,curveX,curveY,'Color',[0.8500,0.3250 ,0.0980]);
                            overlays{end+1} = overlay; %#ok<AGROW>
                            hold(ax,'off');
                        else
                            delInds(end+1) = ind; %#ok<AGROW>
                        end
                    end
                    for ind = (1:length(delInds))
                        intRegions(ind) = []; %#ok<AGROW>
                    end
                end
                response = input('regions(int/noise/apply)','s');
                switch response
                    case 'int'
                        try
                            disp('Select Integration Region');
                            intRegions{end+1} = drawrectangle(ax); %#ok<AGROW>
                        catch
                            return
                        end
                    case 'noise'
                        try
                            disp('Select Noise Region');
                            noiseRegions{end+1} = drawrectangle(ax,'Color','r'); %#ok<AGROW>
                        catch
                            return
                        end
                    case 'esc'
                        working = false;
                    case 'apply'
                        obj.analysis{end+1} = localAnalysis;
                        savedAnalysis = true;
                        working = false;
                end
                if ~isempty(noiseRegions)
                    noiseMeans = {};
                    noiseStdevs = {};
                    noiseBds = {};
                    for ind = 1:length(noiseRegions)
                        rectPts = noiseRegions{ind}.Position;
                        bds = [rectPts(1),rectPts(1)+rectPts(3)];
                        noiseBds{end+1} = bds; %#ok<AGROW>
                        [~,intStartInd] = min(abs(obj.xppm-min(bds)));
	                    [~,intEndInd] = min(abs(obj.xppm-max(bds)));
                        switch mode
                            case 'real'
                                noiseStdevs{end+1} = std(real(specStack(intStartInd:intEndInd,rep))); %#ok<AGROW>
                                noiseMeans{end+1} = mean(real(specStack(intStartInd:intEndInd,rep))); %#ok<AGROW>
                            case 'abs'
                                noiseStdevs{end+1} = std(abs(specStack(intStartInd:intEndInd,rep))); %#ok<AGROW>
                                noiseMeans{end+1} = mean(abs(specStack(intStartInd:intEndInd,rep))); %#ok<AGROW>
                            case 'imag'
                                noiseStdevs{end+1} = std(imag(specStack(intStartInd:intEndInd,rep))); %#ok<AGROW>
                                noiseMeans{end+1} = mean(imag(specStack(intStartInd:intEndInd,rep))); %#ok<AGROW>
                        end
                    end
                    tbl = table(noiseBds',noiseMeans',noiseStdevs','VariableNames',["Bounds (ppm)","Mean",'Stdev']);
                    localAnalysis.noise = tbl;
                end     
    
                if ~isempty(intRegions)
                    ints = {};
                    intBds = {};
                    for ind = 1:length(intRegions)
                        rectPts = intRegions{ind}.Position;
                        intBds{end+1} = [rectPts(1),rectPts(1)+rectPts(3)]; %#ok<AGROW>
                        ints{end+1} = obj.peakInts([rectPts(1),rectPts(1)+rectPts(3)],'ppm',mode, ...
                                                    flipAdjust=opts.flipAdjust,decayCorr=opts.decayCorr,stack=opts.stack); %#ok<AGROW>
                    end
                    tbl = table(intBds',ints','VariableNames',["Bounds (ppm)","Integrals"]);
                    localAnalysis.ints = tbl;
                end    
            end
            if ~savedAnalysis
                deciding = true;
                while deciding
                    inpt = input('Would you like to save the analysis from this session? (y/n): ','s');
                    switch inpt
                        case 'y'
                            obj.analysis{end+1} = localAnalysis;
                        case 'n'
                            deciding = false;
                        otherwise
                            disp('Unrecognized response.');
                    end
                end
            end
            for idx = 1:length(intRegions)
                if isvalid(intRegions{idx})
                    delete(intRegions{idx});
                end
            end
        end

        function dynAx = showAnalysis(obj,analysisInd,opts)
            % Display mode for viewing obj.analysis entries. This method is
            % intended to be used to view dynamic curves (or in general the
            % time evolution of peak integrals). Options can be set to
            % calculate T1 values for peak decays.
            %
            % - analysisInd: index corresponding to the index of the
            %                desired analysis entry in obj.analysis
            % - opts.showData: 
            %       (T => data points will be overlayed in addition to curves)
            %       (F => only curves will be displayed)
            % - opts.labels: labels to add to dynamic curves plot. Pass
            %                label names as you would to the legend()
            %                function
            % - opts.calcT1
            %       (T => user will be prompted to select temporal bounds
            %       which the function will then use to calculate T1 values
            %       for all curves which have data within these bounds)
            
            arguments
                obj 
                analysisInd {mustBeGreaterThanOrEqual(analysisInd,1),mustBeInteger}
                opts.xAx = []
                opts.showData logical = true;
                opts.labels = {};
                opts.calcT1 logical = false;
            end
            if isempty(opts.xAx)
                xLbl = 'Frames';
            else
                xLbl = 'Time (s)';
            end
            dynAx = axes(figure);
            if ~isempty(obj.analysis)
                if analysisInd<= length(obj.analysis)
                    ints = obj.analysis{analysisInd}.ints.Integrals;
                    hold(dynAx,"on")
                    if isempty(opts.xAx)
                        xAx = (1:obj.dimFG);
                    else
                        xAx = opts.xAx;
                    end
                    for ind = (1:length(ints))
                        plot(dynAx,xAx,ints{ind});
                    end
                    
                    for ind = (1:length(ints))
                        if opts.showData
                            scatter(dynAx,xAx,ints{ind},4,'black','filled');
                        end
                    end
                    %L.AutoUpdate = "on";
                    legend(dynAx,'NumColumns',2);
                    if ~isempty(opts.labels)
                        dataLbls = cell(1,length(opts.labels));
                        for idx = (1:length(opts.labels))
                           dataLbls{idx} = sprintf('%s data',opts.labels{idx});
                        end
                        lbls = cat(2,opts.labels,dataLbls);
                        legend(dynAx,lbls);
                    end
                    title(dynAx,'Dynamic Curves');
                    ylabel(dynAx,'MR Signal (a.u.)');
                    xlabel(dynAx,xLbl)
                    
                    if opts.calcT1
                        disp('Draw Region to use in T1 calculation');
                        region = drawrectangle(dynAx);
                        [xmin,xmax] = bounds(region.Vertices(:,1));
                        delete(region);
                        fits = cell(length(ints),1);
                        for ind = (1:length(ints))
                            intSeries = ints{ind};
                            xfit = xAx(xmin<xAx & xAx<xmax)';
                            f = fit(xfit,intSeries(xmin<xAx & xAx<xmax)','exp1');
                            plot(dynAx,xfit,f(xfit),'LineStyle','--',Color='black',DisplayName=sprintf('Fit (T1=%0.2f s)',-1/f.b));
                            fits{ind} = f;
                        end
                        dynAx.Legend.NumColumns = 3;
                    end
                    
                    hold(dynAx,"off");

                else
                    error('Requested analysis is out of range!');
                end
            end
            

        end
        
        function angs = angles(obj,reps)
            arguments
                obj
                reps = []
            end
            % Returns the phase of the spectra in the voxel specified by
            % obj.focus
            % (I guess this isn't really an analysis function but I just
            % stuck it here for now)
            if isempty(reps)
                reps = 1:obj.dimFG;
            end
            angs = zeros(obj.dimF,reps);
            [x,y,z,~] = obj.getFocus("r");
            for rep = reps
                angs(:,rep) = rad2deg(unwrap(angle(obj.rData(:,x,y,z,rep))));
            end
        end

        %%%%%%%%%%%%% LINKED PLOTS / VISUALIZATION %%%%%%%%%%%%%%%%%

        function setupPlot(obj,ax,params)
            % Reformats plot axes (ax) according to convention.
            %
            % - ax: axes handle to plot you would like to format
            % - params.type: plot type. one of:{'kImage', ...
            %                                   'rImage', ...
            %                                   'kPlot', ...
            %                                   'rPlot', ...
            %                                   'rStack' ...
            %                                   'spiral'})}
            % - params.xAx: Frequency axes to use (either 'ppm' or 'ind')
            % - params.ppmStep: tick step to use if plotting with ppm scale
            arguments
                obj
                ax
                params.type {mustBeMember(params.type,{'kImage', ...
                                                       'rImage', ...
                                                       'kPlot', ...
                                                       'rPlot', ...
                                                       'rStack' ...
                                                       'spiral'})}
                params.mode {mustBeMember(params.mode,{'real','abs','imag'})};
                params.xAx {mustBeMember(params.xAx,{'ind','ppm'})};
                params.ppmStep {mustBeInteger,mustBeGreaterThan(params.ppmStep,0)} = 5
                
            end
            
            switch params.type
                    case 'kImage'
                        title(ax,'K-Space');
                        subtitle(ax,sprintf('Time index: %d', ...
                            obj.focus.kInd));
                        xlabel(ax,'kx');
                        ylabel(ax,'ky');
                    case 'rImage'
                        title(ax,'Real-Space');
                        subtitle(ax,sprintf('Freq. index: %d', ...
                            obj.focus.rInd));
                        xlabel(ax,'X');
                        ylabel(ax,'Y');
                    case 'kPlot'
                        title(ax,sprintf('FID (%s)',params.mode));
                        subtitle(ax,sprintf('K-Space Voxel: [%d,%d]', ...
                            obj.focus.kXYZ(1),obj.focus.kXYZ(2)));
                        xlabel(ax,'Time (index)');
                        ylabel(ax,'MR Signal (a.u.)');
                    case 'rPlot'
                        title(ax,sprintf('Spectrum (%s)',params.mode));
                        subtitle(ax,sprintf('R-Space Voxel: [%d,%d]', ...
                            obj.focus.rXYZ(1),obj.focus.rXYZ(2)));
                        if strcmp(params.xAx,'ind')
                            xlabel('Frequency (index)');
                            ylabel('MR Signal (a.u.)');
                        else
                            xticks(ax,round((obj.xppm(1):params.ppmStep:obj.xppm(end))/params.ppmStep)*params.ppmStep);
                            set(ax,'xdir','reverse');
                            xlabel(ax,'Chemical Shift (ppm)');
                            ylabel(ax,'MR Signal (a.u.)');
                        end
                    case 'spiral'
                        if strcmp(params.xAx,'ind')
                            xlabel('Frequency (index)');
                            ylabel(ax,'In-Phase MR Signal (a.u.)');
                            zlabel(ax,'Quadriture MR Signal (a.u.)');
                        else
                            xticks(ax,round((obj.xppm(1):params.ppmStep:obj.xppm(end))/params.ppmStep)*params.ppmStep);
                            set(ax,'xdir','reverse');
                            xlabel(ax,'Chemical Shift (ppm)');
                            ylabel(ax,'In-Phase MR Signal (a.u.)');
                            zlabel(ax,'Quadriture MR Signal (a.u.)');
                        end

                    case 'rStack'
                        title(ax,sprintf('Spectral Stack (%s)',params.mode));
                        subtitle(ax,sprintf('R-Space Voxel: [%d,%d]', ...
                            obj.focus.rXYZ(1),obj.focus.rXYZ(2)));
                        if strcmp(params.xAx,'ind')
                            xlabel(ax,'Frequency (index)');
                            ylabel(ax,'Frames');
                            zlabel(ax,'MR Signal (a.u.)')
                        else
                            xticks(ax,round((obj.xppm(1):params.ppmStep:obj.xppm(end))/params.ppmStep)*params.ppmStep);
                            set(ax,'xdir','reverse');
                            xlabel(ax,'Chemical Shift (ppm)');
                            yticks(ax,(1:obj.dimFG));
                            ylabel(ax,'Frames');
                            zlabel(ax,'MR Signal (a.u.)');
                        end  
            end
        end
        
        function plotFocus(obj,ax,type,opts)
            % Plots an indicator to specify the current focus. For images
            % the indicator is a red box surrounding the focus voxel. For
            % 2D plots a vertical line will be drawn at the focus index.
            %
            % - ax: axes handle to the plot where you would like the focus
            %       drawn
            % - type: Valid plot types where the focus can be drawn
            %         clearly ('kPlot','rPlot','kImage','rImage')
            
            arguments
                obj 
                ax 
                type {mustBeMember(type,{'kPlot','rPlot','kImage','rImage'})}; 
                opts.xAx {mustBeMember(opts.xAx,{'ind','ppm'})}='ind';
            end
            switch type
                case 'kPlot'
                    xline(ax,obj.focus.kInd,'r');
                case 'rPlot'
                    if strcmp(opts.xAx,'ind')
                        xline(ax,obj.focus.rInd,'r');
                    else
                        xline(ax,obj.xppm(obj.focus.rInd),'r');
                    end
                case 'kImage'
                    x = obj.focus.kXYZ(1);
                    y = obj.focus.kXYZ(2);
                    outlinePix(ax,x,y,'r','linewidth',2);
                case 'rImage'
                    x = obj.focus.rXYZ(1);
                    y = obj.focus.rXYZ(2);
                    outlinePix(ax,x,y,'r','linewidth',2);
            end
        end

        % function updateLinkedPlots(obj,~)
        %     % Updates all active linked plots, purges invalid linked plots,
        %     % and automatically formats linked plots by calling setupPlot.
        %     % This is the function called by the 'showEdits' listener.
        %     [kx,ky,kz,~] = obj.getFocus("k");
        %     [rx,ry,rz,rep] = obj.getFocus("r");
        % 
        %     rInd = obj.focus.rInd;
        %     kInd = obj.focus.kInd;
        %     %purge linkedPlots:
        %     obj.linkedPlots = obj.linkedPlots(~cellfun(@isempty,obj.linkedPlots));
        %     for ind = (1:length(obj.linkedPlots))
        %         linkedPlot = obj.linkedPlots{ind};
        %         ax = linkedPlot.ax;
        %         if ~isvalid(ax)
        %             obj.linkedPlots{ind} = [];
        %             continue
        %         end
        %         plotParams = linkedPlot.params;
        %         switch plotParams.type
        %             case 'kPlot'
        %                 mrPlot("line",obj.kData(:,kx,ky,kz,rep),ax,"mode",plotParams.mode);
        %             case 'rPlot'
        %                 if strcmp(plotParams.xAx,'ppm')
        %                     mrPlot("line",obj.rData(:,rx,ry,rz,rep),ax,{obj.xppm},...
        %                                    "mode",plotParams.mode);
        %                 else
        %                     mrPlot("line",obj.rData(:,rx,ry,rz,rep),ax,"mode",plotParams.mode);
        %                 end
        %             case 'spiral'
        %                 if strcmp(plotParams.xAx,'ppm')
        %                     mrPlot("spiral",obj.rData(:,rx,ry,rz,rep),ax,{obj.xppm},...
        %                                    "mode",plotParams.mode);
        %                 else
        %                     mrPlot("spiral",obj.rData(:,rx,ry,rz,rep),ax,"mode",plotParams.mode);
        %                 end
        %             case 'kImage'
        %                 mrPlot("image",obj.kData(kInd,:,:,kz,rep),ax,"mode",plotParams.mode);
        %             case 'rImage'
        %                 mrPlot("image",obj.rData(rInd,:,:,rz,rep),ax,"mode",plotParams.mode);
        %             case 'rStack'
        %                 if strcmp(plotParams.xAx,'ppm')
        %                     mrPlot("line_stack",obj.rData(:,rx,ry,rz,:),ax,{obj.xppm,1:obj.dimFG},"mode",plotParams.mode);
        %                 else
        %                     mrPlot("line_stack",obj.rData(:,rx,ry,rz,:),ax,"mode",plotParams.mode);
        %                 end
        %             otherwise
        %                 error('Invalid Linked Plot Type');
        %         end
        %         reHold = ishold(ax);
        %         if obj.prefs.showFoc
        %             hold(ax,'on');
        %             try
        %                 obj.plotFocus(ax,plotParams.type,'xAx',plotParams.xAx);
        %             end
        %             hold(ax,'off');
        %         end
        %         if reHold
        %             hold(ax,'on');
        %         end
        %         ppmStep = 5;
        %         if strcmp(plotParams.mode,'rStack')
        %             ppmStep = 10;
        %         end
        %         obj.setupPlot(linkedPlot.ax,type=plotParams.type, ...
        %                                     mode=plotParams.mode, ...
        %                                     xAx = plotParams.xAx, ...
        %                                     ppmStep=ppmStep);
        %     end
        %     %purge linkedPlots:
        %     obj.linkedPlots = obj.linkedPlots(~cellfun(@isempty,obj.linkedPlots));
        % end
        
        % function showLayout(obj,type)
        %     % Add commonly used linkedPlot setups here. This is simply a
        %     % wrapper function to create arrangements of linked plots
        %     % within tiled layouts. Currently supported layouts are:
        %     %
        %     % - 'K_RGrid': 2x2 grid of plots to visualize k-space
        %     %   processing and how it affects R-space
        %     %           ('kImage') ('rImage')
        %     %           ('kPlot' ) ('rPlot' )
        %     % - 'fid': 2x1 layout to display processing of a single FID and
        %     %          its corresponding spectrum
        %     %                 ('kPlot')
        %     %                 ('rPlot')
        %     arguments
        %         obj 
        %         type {mustBeMember(type,{'K_RGrid','fid','specSpace'})};
        %     end
        %     fig = figure;            
        %     switch type
        %         case 'K_RGrid'
        %            tiles = tiledlayout(fig,2,2);
        %            tiles.Padding = "compact";
        %            tiles.TileSpacing = 'compact';
        %            obj.linkPlot(nexttile,"type","kImage","mode","abs");
        %            obj.linkPlot(nexttile,'type','rImage','mode','abs');
        %            obj.linkPlot(nexttile,'type','kPlot','mode','abs','xAx','ppm');
        %            obj.linkPlot(nexttile,'type','rPlot','mode','abs','xAx','ppm');
        %         case 'fid'
        %            tiles = tiledlayout(fig,2,2);
        %            tiles.Padding = "compact";
        %            tiles.TileSpacing = 'compact';
        %            obj.linkPlot(nexttile,'type','kPlot','mode','abs');
        %            obj.linkPlot(nexttile,'type','rStack','mode','abs','xAx','ppm');
        %            obj.linkPlot(nexttile,'type','rPlot','mode','abs','xAx','ppm');
        %            obj.linkPlot(nexttile,'type','rPlot','mode','real','xAx','ppm');
        % 
        %         case 'specSpace'
        %            tiles = tiledlayout(fig,2,2);
        %            tiles.Padding = "compact";
        %            tiles.TileSpacing = 'compact';
        %            obj.linkPlot(nexttile,"type","rImage","mode","abs");
        %            obj.linkPlot(nexttile,'type','rStack','mode','abs','xAx','ppm');
        %            obj.linkPlot(nexttile,'type','rPlot','mode','abs','xAx','ppm');
        %            obj.linkPlot(nexttile,'type','rPlot','mode','real','xAx','ppm');
        %         otherwise
        %             warning('Unknown layout parameter!');
        % 
        %     end
        % end
         
        % function setKVoxel(obj)
        %     % Interactive method to allow the user to select a k-space
        %     % voxel which will then become the focused k_vox
        %     % - opts.show: (F => supresses listener)
        % 
        %     ax = axes(figure);
        %     kInd = obj.focus.kInd;
        %     [~,~,kz,rep] = obj.getFocus("k");
        %     imagesc(ax,squeeze(abs(obj.kData( ...
        %                                 kInd,:,:,kz,rep)))');
        %     title(ax,'PLEASE SELECT K-VOXEL');
        %     obj.plotFocus(ax,"kImage");
        %     try
        %         vox = drawpoint(ax);
        %     catch
        %         return
        %     end
        %     obj.focus.kXYZ = [round(vox.Position(1)),round(vox.Position(2)),kz];
        %     delete(ax.Parent);
        %     % fprintf('New k-Voxel: [%d,%d,%d]\n',obj.focus.kXYZ(1), ...
        %     %     obj.focus.kXYZ(2),obj.focus.kXYZ(3));
        % end
        
        % function setRVoxel(obj)
        %     % Interactive method to allow the user to select an r-space
        %     % voxel which will then become the focused r_vox
        % 
        %     ax = axes(figure);
        %     [~,~,rz,rep] = obj.getFocus("r");
        %     rInd = obj.focus.rInd;
        %     imagesc(ax,squeeze(abs(obj.rData( ...
        %                                 rInd,:,:,rz,rep)))');
        %     title(ax,'PLEASE SELECT R-VOXEL');
        %     obj.plotFocus(ax,"rImage");
        %     try
        %         vox = drawpoint(ax);
        %     catch
        %         return
        %     end
        %     obj.focus.rXYZ = [round(vox.Position(1)),round(vox.Position(2)),rz];
        %     delete(ax.Parent);
        % end

        % function linkPlot(obj,ax,opts)
        %     % Function used to add linked plots. Linked plots will
        %     % automatically updated when the showEdits listener is called
        %     % and can be manually updated by calling obj.updateLinkedPlots
        %     %
        %     % - opts.type: type of plot to be linked. valid types:
        %     %     ('kPlot','rPlot','kImage','rImage','rStack','spiral')
        %     % - opts.mode: mode of plot to be linked. ('abs','real','imag')
        %     % - opts.xAx: axis to use for the frequency domain ('ind' or
        %     %             'ppm')
        %     % Function will automatically call updateLinkedPlots to
        %     % instantiate the new plot and update all others.
        % 
        %     arguments
        %         obj 
        %         ax 
        %         opts.type {mustBeMember(opts.type,{'kPlot','rPlot','kImage','rImage','rStack','spiral'})};
        %         opts.mode {mustBeMember(opts.mode,{'abs','real','imag'})} = 'abs';
        %         opts.xAx {mustBeMember(opts.xAx,{'ind','ppm'})} = 'ind';
        %     end
        %     if isvalid(ax)
        %         delInds = [];
        %         for idx = (1:length(obj.linkedPlots))
        %             if ~isempty(obj.linkedPlots{idx})
        %                 if obj.linkedPlots{idx}.ax == ax
        %                     delInds(end+1) = idx; %#ok<AGROW>
        %                 end
        %             end
        %         end
        %         for ind = (1:length(delInds))
        %             if ind<=length(obj.linkedPlots)
        %                 obj.linkedPlots(delInds(ind)) = [];
        %             end
        %             obj.linkedPlots = squeeze(obj.linkedPlots);
        %         end
        %         plotParams = struct('mode',opts.mode, ...
        %                             'type',opts.type, ...
        %                             'xAx',opts.xAx);
        %         obj.linkedPlots{end+1} = struct('ax',ax, ...
        %                                         'params',plotParams);
        %         obj.updateLinkedPlots;
        %     else
        %         error('ERROR: Invalid axes handle!');
        %     end
        % end
        % 
        % function visualizeDecay(obj,opts)
        %     % Method intended to help the user visualize how a spectrum (or
        %     % specific regions of a spectrum) decay over time. The
        %     % spectrum is specified by obj.focus. VisualizeDecay will 
        %     % return a movie object (M) which can be used to reproduce 
        %     % the animation.
        %     %
        %     % - opts.mode: mode to use for animation ('real','imag','abs')
        %     % - opts.pickRegion: set flag true to allow the user to select
        %     %                    a rectangular region which will be used to
        %     %                    crop down the animation bounds. If set
        %     %                    false then the entire spectrum will be
        %     %                    displayed
        %     % - opts.dt: timestep in seconds between frames
        %     arguments
        %         obj 
        %         opts.mode {mustBeMember(opts.mode,{'real','abs','imag'})} = 'real';
        %         opts.pickRegion logical = false;
        %         opts.dt = 0.5;
        %         opts.reps = [];
        %     end
        %     ax = axes(figure);
        %     [x,y,z,rep] = obj.getFocus("r");
        %     [xmin,xmax] = bounds(obj.xppm);
        %     if isempty(opts.reps)
        %         reps = 1:obj.dimFG;
        %     else
        %         reps = opts.reps;
        %     end
        %     ymins = zeros(size(reps));
        %     ymaxs = zeros(size(reps));
        %     for idx = reps
        %         switch opts.mode
        %             case 'real'
        %                 [ymin_local,ymax_local] = bounds(real(obj.rData(:,x,y,z,idx)));
        %             case 'abs'
        %                 [ymin_local,ymax_local] = bounds(abs(obj.rData(:,x,y,z,idx)));
        %             case 'imag'
        %                 [ymin_local,ymax_local] = bounds(imag(obj.rData(:,x,y,z,idx)));
        %         end
        %         ymins(idx) = ymin_local;
        %         ymaxs(idx) = ymax_local;
        %     end
        %     ymin = min(ymins);
        %     ymax = max(ymaxs);
        %     if opts.pickRegion
        %         switch opts.mode
        %             case 'real'
        %                 plot(ax,obj.xppm,real(obj.rData(:,x,y,z,rep)));
        %             case 'imag'
        %                 plot(ax,obj.xppm,imag(obj.rData(:,x,y,z,rep)));
        %             case 'abs'
        %                 plot(ax,obj.xppm,abs(obj.rData(:,x,y,z,rep)));
        %         end
        %         obj.setupPlot(ax,"type","rPlot","mode",opts.mode,"xAx","ppm");
        %         drawnow;
        %         region = drawrectangle(ax);
        %         [xmin,xmax] = bounds(region.Vertices(:,1));
        %         [ymin,ymax] = bounds(region.Vertices(:,2));
        %     end
        %     for rep = reps
        %         try
        %             switch opts.mode
        %                 case 'real'
        %                     plot(ax,obj.xppm,real(obj.rData(:,x,y,z,rep)));
        %                 case 'imag'
        %                     plot(ax,obj.xppm,imag(obj.rData(:,x,y,z,rep)));
        %                 case 'abs'
        %                     plot(ax,obj.xppm,abs(obj.rData(:,x,y,z,rep)));
        %             end  
        %             obj.setupPlot(ax,"type","rPlot","mode","real","xAx","ppm");
        %             subtitle(ax,sprintf('Rep %d',rep));
        %             xlim(ax,[xmin,xmax]);
        %             ylim(ax,[ymin,ymax]);
        %             drawnow;
        %             pause(opts.dt);
        %         catch
        %             %assume cause: ax no longer valid
        %             continue
        %         end
        %     end
        %     if isvalid(ax)
        %         delete(ax.Parent);
        %     end
        % end
        % 
    end
end
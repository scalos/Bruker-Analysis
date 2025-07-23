classdef DataRecon < handle

    properties
        rData
        kData
        kDataRaw
        rDataRaw
        nPoints = NaN
        dimX = NaN
        dimY = NaN
        dimZ = NaN
        nSlices = NaN;
        nReps = NaN
        analysis = {};
        kProcParams;
        linkedPlots = {};
        sysParams = struct
       
    end

    properties (Access = private)
        rProcParamsCell;
        kProc_cashed;
        rProc_cashed;
        loadType;
    end

    properties (Dependent)
        xppm;
        rProcParams;
    end

    properties (SetObservable)
        focus;
        prefs = struct('showFocChg',true, ...
                       'showFoc',true, ...
                       'ppmShift',0);
    end

    events
        showEdits
    end

    methods (Access = private)
        function handlePropEvents(obj,src,evnt)
            switch evnt.EventName
                case 'PostSet'
                    switch src.Name
                        case 'focus'
                            if obj.prefs.showFocChg
                                notify(obj,'showEdits')
                            end
                        case 'prefs'
                            notify(obj,'showEdits')
                    end
            end
        end
    end

    methods
        %%%%%%%%%%%%% CONSTRUCTOR %%%%%%%%%%%%%%%%%

        function obj = DataRecon(data,dataType,params)
            arguments
                data;
                dataType {mustBeMember(dataType,{'K','R'})};

                %allParams should be a struct with fields below
                params.allParams = [];
                
                %Any of these params will override those within allParams if
                %both are passed to the constructor
                params.hzBW = [];
                params.mhzCF = [];
                params.ppmCF = [];
                params.flipAng = [];
                params.ppmBW = [];
                params.TR = [];
                params.dataShape = [];
                params.kspaceTforms = {{'fftshift','fft'},...
                                      {'ifftshift','ifft','ifftshift'},...
                                      {'ifftshift','ifft','ifftshift'},...
                                      {'ifftshift','ifft','ifftshift'},...
                                      {},{}}; % transforms from k-space to real space
            end
            
            % initially set sysParams to any fields within allParams with
            % names matching expected fieldNames
            obj.sysParams = rmfield(params,'allParams');
            if ~isempty(params.allParams)
                paramFields = fieldnames(params.allParams);
                for idx = (1:length(paramFields))
                    fieldName = paramFields{idx};
                    if isfield(obj.sysParams,fieldName)
                        obj.sysParams.(fieldName) = params.allParams.(fieldName);
                    end
                end
            end
            % If any name/value parameters are passed explicitly outside of
            % allParams, override with explicit values:
            explicitParams = rmfield(params,'allParams');
            fields = fieldnames(explicitParams);
            for ind = (1:length(fields))
                fieldName = fields{ind};
                if ~isempty(explicitParams.(fieldName))
                    obj.sysParams.(fieldName) = explicitParams.(fieldName);
                end
            end
            
            %Set up k/r data variables
            if strcmp(dataType,'K')
                obj.kData = data;
                obj.kDataRaw = data;
                obj.rDataRaw = K_R_Tform(data,obj.sysParams.kspaceTforms);
                obj.rData = obj.rDataRaw;
                obj.loadType = 'K';
            else
                obj.rData = data;
                obj.rDataRaw = data;
                obj.kDataRaw = K_R_Tform(data,obj.sysParams.kspaceTforms,true);
                obj.kData = obj.kDataRaw;
                obj.loadType = 'R';
                
            end
            %initialize focus (all vals = 1)
            obj.resetFocus;
            
            %initialize data dimensions: 
            %   if data size is len 5 it is assumed to already be in the 
            %   right shape unless different datashape is also passed to the constructor
            if isempty(obj.sysParams.dataShape)
                if length(size(data))~=6
                    error(['Data must be of shape: nPoints x dimX x dimY x dimZ x nSlices x nReps' ...
                        ' or shape must be specified']);
                else
                    obj.setDims;
                end
            else
                obj.setDims(obj.sysParams.dataShape);
            end

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
            
            obj.kProcParams = struct('blank',[],'lb',[],'zf',[]);
            obj.kProc_cashed = obj.kProcParams;
            obj.resetRProc;

            obj.setListeners;
        end

        %%%%%%%%%%%%% GETS AND SETS %%%%%%%%%%%%%%%%%

        function setListeners(obj)
            %Reset listeners needed for auto-updating plots
            %   (if DataRecon obj is loaded from .mat file, run this to
            %   restart listeners)
            addlistener(obj,'showEdits',@updateLinkedPlots);
            addlistener(obj,'prefs','PostSet',@obj.handlePropEvents);
            addlistener(obj,'focus','PostSet',@obj.handlePropEvents);
        end
        
        function params = get.rProcParams(obj)
           %Parses rProcParams array and returns param structure of voxel
           %indicated by focus.
           [x,y,z,slice,rep] = obj.getFocus("r");
           paramsArr = obj.rProcParamsCell(:,x,y,z,slice,rep);
           params = struct('phi0',paramsArr(1), ...
                           'phi1',paramsArr(2), ...
                           'pivotVal',paramsArr(3), ...
                           'pivotMode',paramsArr(4), ...
                           'appliedPhase',paramsArr(5),...
                           'baseline',paramsArr(6));
        end

        function set.rProcParams(obj,s)
            %Since rProcParams are stored in an array, editing the stuct
            %requires setting rProcParams = struct. (i.e. unable to set
            %individual fields as you would with normal struct)
            arguments
                obj
                s 
            end
            sFields = fieldnames(s);
            fields = fieldnames(obj.rProcParams);
            [x,y,z,slice,rep] = obj.getFocus('r');
            paramsArr = squeeze(obj.rProcParamsCell(:,x,y,z,slice,rep));
            for idx = (1:length(sFields))
                ind = find(strcmp(fields,sFields{idx}), 1);
                if ~isempty(ind)
                    paramsArr(idx) = {s.(sFields{idx})};
                end
            end
            obj.rProcParamsCell(:,x,y,z,slice,rep) = paramsArr;
        end
        
        function val = get.xppm(obj)
            %Using get func for xppm allows axis to adapt to procs like zf
            val = NaN;
            if ~isempty(obj.sysParams.ppmBW)
			    xppmAxis = (obj.sysParams.ppmBW/obj.nPoints)*(1:obj.nPoints);
			    val = xppmAxis-(obj.sysParams.ppmBW/2-obj.sysParams.ppmCF-obj.prefs.ppmShift);
            end
        end

        function [x,y,z,slice,rep] = getFocus(obj,r_k)
            arguments
                obj 
                r_k {mustBeMember(r_k,{'r','k'})};
            end
            if strcmp(r_k,'r')
                x = obj.focus.rXYZ(1);
                y = obj.focus.rXYZ(2);
                z = obj.focus.rXYZ(3);
            else
                x = obj.focus.kXYZ(1);
                y = obj.focus.kXYZ(2);
                z = obj.focus.kXYZ(3);
            end
            slice = obj.focus.slice;
            rep = obj.focus.viewRep;
        end
        
        function setDims(obj,shape)
            %if shape is given:
            %   k/r data (proc and raw) are reshaped and 
            %   nPoints, dimX/Y/Z, nReps are all updated
            %if shape is not given:
            %   nPoints, dimX/Y/Z, nReps are all updated but data is not
            %   reshaped
            arguments
                obj
                shape = NaN;
            end
            if ~isnan(shape)
                obj.kData = reshape(obj.kData,shape);
                obj.kDataRaw = reshape(obj.kDataRaw,shape);
                obj.rData = reshape(obj.rData,shape);
                obj.rDataRaw = reshape(obj.rDataRaw,shape);
                [obj.nPoints,obj.dimX,obj.dimY,obj.dimZ,obj.nSlices,obj.nReps] = size(obj.kData);
                
            else
                [obj.nPoints,obj.dimX,obj.dimY,obj.dimZ,obj.nSlices,obj.nReps] = size(obj.kData);                
            end
        end

        function resetRProc(obj)
            obj.setDims;
            procSize = [6,obj.dimX,obj.dimY,obj.dimZ,obj.nSlices,obj.nReps];
            obj.rProcParamsCell = cell(procSize);
        end
        
        %%%%%%%%%%%%% RESETTING/UPDATING DATA %%%%%%%%%%%%%%%%%

        function revert(obj,toRevert,region)
            % Allows for reversion of processing parameters by default this
            % will operate on the whole data set. If you want to revert
            % certain voxels use region = {(x1,...,xn),
            %                              (y1,...,zn),
            %                              (z1,...,zn),
            %                              (slice1,...,slicen),
            %                              (rep1,...repn)}
            %   NOTE: if zf is reverted then the obj focus will be reset
            %   since it cannot be guarenteed that the existing focus won't
            %   be out of range for the new data size.
            %
            %   TODO: if data is loaded with 'R' flag in constructor it
            %   doesn't make sense to allow reversion of k-space proc
            %   params blank,lb,zf so these should be restricted.
            arguments
                obj;
                toRevert {mustBeMember(toRevert,{'all', ...
                                                 'blank', ...
                                                 'lb', ...
                                                 'zf', ...
                                                 'Foc_Baseline', ...
                                                 'Foc_Phase',...
                                                 'All_Baselines',...
                                                 'All_Phases'})} = 'all'
                region = [];
            end
            if isempty(region)
                region = {1:obj.dimX;...
                          1:obj.dimY;...
                          1:obj.dimZ;...
                          1:obj.nSlices;...
                          1:obj.nReps};
            end
            [x,y,z,~] = obj.getFocus("r");
            switch toRevert
                case 'all'
                    obj.kProcParams.blank = [];
                    obj.kProcParams.zf = [];
                    obj.kProcParams.lb = [];
                    obj.resetPhasing(region);
                    obj.resetBaselines(region);
                    obj.resetFocus;
                case 'blank'
                    obj.kProcParams.blank = [];
                case 'lb'
                    obj.kProcParams.lb = [];
                case 'zf'
                    obj.kProcParams.zf = [];
                    obj.resetFocus;
                case 'Foc_Baseline'
                    region = {x,y,z,1:obj.nSlices,1:obj.nReps};
                    obj.resetBaselines(region);
                case 'Foc_Phase'
                    region = {x,y,z,1:obj.nSlices,1:obj.nReps};
                    obj.resetPhasing(region);
                case 'All_Baselines'
                    obj.resetBaselines(region);
                case 'All_Phases'
                    obj.resetPhasing(region);
                otherwise
                    warning('Not a valid revert request!');
            end
            obj.updateProc;
        end

        function resetBaselines(obj,region)
            %Clear baselines in specified region 
            %   (by default region is whole dataset)
            arguments
                obj 
                region = [];
            end
            if isempty(region)
                region = {1:obj.dimX;...
                          1:obj.dimY;...
                          1:obj.dimZ;...
                          1:obj.nSlices;...
                          1:obj.nReps};
            end
            regionSize = [1,length(region{1}),length(region{2}),...
                          length(region{3}),length(region{4}),length(region{5})];
            obj.rProcParamsCell(6,region{:}) = cell(regionSize);
        end

        function resetPhasing(obj,region)
            %Clear phasing in specified region 
            %   (by default region is whole dataset)
            arguments
                obj 
                region = [];
            end
            if isempty(region)
                region = {1:obj.dimX;...
                          1:obj.dimY;...
                          1:obj.dimZ;...
                          1:obj.nSlices;...
                          1:obj.nReps};
            end
            regionSize = [5,length(region{1}),length(region{2}),...
                          length(region{3}),length(region{4}),length(region{5})];
            obj.rProcParamsCell(1:5,region{:}) = cell(regionSize);
        end

        function update(obj)
            obj.updateLinkedPlots;
            obj.updateProc;
        end

        function updateProc(obj)
            %reprocess data according to k/r proc parameters.
            % 
            % WARNING: for large datasets or data sets with extensive
            %          processing this method may have a long run time
            arguments
                obj
            end

            if strcmp(obj.loadType,'K')
                if ~isequal(obj.kProcParams,obj.kProc_cashed)
                    obj.kData = obj.kDataRaw;
                    if ~isempty(obj.kProcParams.blank)
                        obj.kData = shift_data(obj.kData,obj.kProcParams.blank);
                    end
    
                    if ~isempty(obj.kProcParams.lb)
                        dt = (1/(obj.sysParams.ppmBW*obj.sysParams.mhzCF));
		                obj.kData = apod(obj.kData,obj.kProcParams.lb,dt);
                    end
    
                    if ~isempty(obj.kProcParams.zf)
                        obj.kData = zFill(obj.kData,obj.kProcParams.zf);
                        obj.setDims;
                        obj.resetRProc;
                    end
                end
                
                obj.rData = K_R_Tform(obj.kData,obj.sysParams.kspaceTforms);
            else
                obj.rData = obj.rDataRaw;
            end

            if isequal(obj.kProcParams.zf,obj.kProc_cashed.zf) || strcmp(obj.loadType,'R')
                phaseMat_curr = obj.rProcParamsCell(5,:,:,:,:,:);
                phaseMat_curr(cellfun('isempty',phaseMat_curr)) = {zeros(obj.nPoints,1)};
        
                baseMat_curr = obj.rProcParamsCell(6,:,:,:,:,:);
                baseMat_curr(cellfun('isempty',baseMat_curr)) = {zeros(obj.nPoints,1)};
    
                obj.rData = obj.rData.*exp(1i*deg2rad(cell2mat(phaseMat_curr)));
                obj.rData = obj.rData - cell2mat(baseMat_curr);
            end

            obj.kProc_cashed = obj.kProcParams;
            notify(obj,'showEdits');
        end

        function resetFocus(obj)
            %Set/Initialize focus to default
            obj.focus = struct('viewRep',1,'kInd',1,'rInd',1,'kXYZ',[1,1,1],'rXYZ',[1,1,1],'slice',1);
        end

        %%%%%%%%%%%%% CORE PROCESSING FUNCTIONS %%%%%%%%%%%%%%%%%

        function obj =  blank(obj, blankInd)
            %Perform blanking on k-space.
            % - blankInd: integer corresponding to number of data points to
            %   shift by.
			arguments
				obj
                blankInd {mustBeInteger,mustBeGreaterThan(blankInd,0)}
            end
            obj.kProcParams.blank = blankInd;
            obj.updateProc;
        end
		
		function obj = lbExp(obj,lb)
            %Performs exponential line broadening on k-space data
            % - lb: line broadening factor in Hz
            %
            % WARNING: function requires sysParmams: ppmBW and mhzCF to
            %          calculate line broadening function.
			arguments
				obj
				lb {mustBeInteger,mustBeGreaterThan(lb,0)} 
            end
            if anynan([obj.sysParams.ppmBW,obj.sysParams.mhzCF])
                error("Missing parameters: 'ppmBW' and 'mhzCF' required" + ...
                    "for line broadening");
            end
            obj.kProcParams.lb = lb;
            obj.updateProc;
        end

		function obj = zf(obj,fillFac)
            % Performs zf on k-space data
            % - fillFac: [fFill,xFill,yFill,zFill]. Can be any subset of
            %   these but will be read L->R
            %       (e.x: fillFac = 2 => only fFill = 2)
			arguments
				obj
				fillFac {mustBeInteger,mustBeGreaterThan(fillFac,0)} 
			end;
            %Ensure zf = [fFill,xFill,yFill,zFill]
            %default: [1,1,1,1] => no zf on any dimensions
            zf = ones(4,1);
            zf(1:length(fillFac)) = fillFac;
            obj.kProcParams.zf = zf;
            obj.updateProc;
        end
          
        function obj = applyPhase(obj,zeroOrder,pivotVal,pivotSetting,firstOrder)
            %Apply a linear phase to the voxel specified by obj.focus
            % - zeroOrder: phi0 zeroth order phase parameter in degrees
            % - pivotVal: value around which to center linear phasing. can
            %   be a ppm value or integer index
            % - pivotSetting: specifies the type of pivotVal
            %       (either 'ppm' or 'ind')
            % - firstOrder: phi1 first order phase parameter
            % opts.show: (F => supresses listener)
            
            arguments
                obj
                zeroOrder = NaN %deg
                pivotVal = NaN;
                pivotSetting = NaN % 'ppm' or 'ind'
                firstOrder = NaN %deg
            end
            % obj.suppressFShow = true;
            [x,y,z,slice,rep] = obj.getFocus("r");
            params = obj.rProcParams;
            
            if isnan(zeroOrder)
                zeroOrder = params.phi0; 
            end

            if isnan(firstOrder) 
                firstOrder = params.phi1; 
            end
            params.phi0 = zeroOrder;
            params.phi1 = firstOrder;

            if isnan(pivotSetting)
                pivotSetting = params.pivotMode;
            else
                params.pivotMode = pivotSetting;
            end

            if isnan(pivotVal)
                pivotVal = params.pivotVal;
            else
                params.pivotVal = pivotVal;
            end
            if ~isnan(zeroOrder)     
                if ~isnan(firstOrder)
                    if isnan(pivotSetting)
                        error("A pivot mode must be set for higher order phasing!");
                    end
                    if isnan(pivotVal)
                        error("A pivot value must be set for higher order phasing!");
                    end
                    switch pivotSetting
                        case 'ppm'
                            [~,pivotInd] = min(abs(obj.xppm-pivotVal));
                        case 'ind'
                            pivotInd = pivotVal;
                        otherwise
                            error("Valid pivot settings are: 'ppm' or 'ind'");
                    end
                    [~,phase] = ps(obj.rData(:,x,y,z,slice,rep),zeroOrder,pivotInd,firstOrder);
                    params.appliedPhase = phase;
                else
                    [~,phase] = ps(obj.rData(:,x,y,z,slice,rep),zeroOrder);
                    params.appliedPhase = phase;
                end
            end
            obj.rProcParams = params;
            obj.updateProc;
        end
                
        %%%%%%%%%%%%% AUTO/INTERACTIVE PROCESSING FUNCTIONS %%%%%%%%%%%%%%

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
            [x,y,z,slice,~] = obj.getFocus('r');
            specStackRaw = squeeze(obj.rData(:,x,y,z,slice,:));
            specStack = specStackRaw;
            if isempty(reps)
                reps = (1:obj.nReps);
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
                            if isinteger(int8(itermax-step))
                                itermax = itermax-step;
                            else
                                disp('Itermax must be Integer!')
                            end
                            if itermax-step>0
                                itermax = itermax-step;
                            else
                                disp('Itermax must be Positive!')
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
                    obj.rProcParamsCell{6,x,y,z,slice,rep} = baselines(:,rep);
                end
                obj.rData(:,x,y,z,slice,reps) = specStack(:,reps);
                obj.updateProc;
            end
        end
        
        function manualPhase(obj,reps)
            %Allows user to perform interactive linear phasing on voxel
            %specified by obj.focus.
            % - reps: which reps of voxel to apply phasing to. by default
            %   phasing is calculated for all reps but the first rep in
            %   the series is used for display
            % - opts.show (F => supress listener)
            arguments
                obj;
                reps = [];
            end
            [x,y,z,slice,rep] = obj.getFocus("r");
            params = obj.rProcParams;
            if isempty(reps)
                reps = (1:obj.nReps);
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
                obj.revert("All_Phases",{x,y,z,slice,reps});
                specData = obj.rData(:,x,y,z,slice,rep);
                obj.applyPhase(phi0,pivotVal,params.pivotMode,phi1);
            else
                specData = obj.rData(:,x,y,z,slice,rep);
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
                            obj.revert("All_Baselines",{x,y,z,slice,reps});
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
                plot(ax,obj.xppm,real(psSpec));
                axis(ax,'padded');
                zoom(ax,'reset');
                saved = false;
                while keepGoing
                    if strcmp(params.pivotMode,'ppm')
                        pivotInd = ppm2ind(obj.xppm,pivotVal);
                    else
                        pivotInd = pivotVal;
                    end
                    xLim = ax.XLim;
                    yLim = ax.YLim;
                    plot(ax,obj.xppm,real(ps(specData,phi0,pivotInd,phi1)));
                    axis(ax,'padded');
                    zoom(ax,'reset');
                    obj.setupPlot(ax,type="rPlot",mode="real",xAx="ppm");
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
                                obj.rProcParamsCell{1,x,y,z,slice,rep} = params.phi0;
                                obj.rProcParamsCell{2,x,y,z,slice,rep} = params.phi1;
                                obj.rProcParamsCell{3,x,y,z,slice,rep} = params.pivotVal;
                                obj.rProcParamsCell{4,x,y,z,slice,rep} = params.pivotMode;
                                obj.rProcParamsCell{5,x,y,z,slice,rep} = phase;
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
                                    obj.rProcParamsCell{1,x,y,z,slice,rep} = params.phi0;
                                    obj.rProcParamsCell{2,x,y,z,slice,rep} = params.phi1;
                                    obj.rProcParamsCell{3,x,y,z,slice,rep} = params.pivotVal;
                                    obj.rProcParamsCell{4,x,y,z,slice,rep} = params.pivotMode;
                                    obj.rProcParamsCell{5,x,y,z,slice,rep} = phase;
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
            [~,~,z,slice,~] = obj.getFocus("r");
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
                    [~,bds(1)] = min(abs(obj.xppm-bds(1)));
                    [~,bds(2)] = min(abs(obj.xppm-bds(2)));
                case 'ind'
                    %do nothing
                otherwise
                    error("Valid bounds types are: 'ppm' or 'ind'");
            end
            bds = sort(bds);
            specs = zeros(numel(bds(1):bds(2)),obj.dimX,obj.dimY,z);
            count = 0;
            zeroPhases = zeros(size(ints));
            specs_raw = squeeze(sum(obj.rData(:,:,:,z,slice,reps),5));
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
                    [~,locs,w,~] = findpeaks(abs(data),SortStr='descend');
                    if ~isempty(locs)
                        p0Guess = -rad2deg(unwrap(angle(data(locs(1)))));
                        options = optimset('Display','none');
                        p0 = fminsearch(@(p0)symScore(real(ps(data,p0)),locs(1),w(1)),p0Guess,options);
                        zeroPhases(x,y) = p0;
                        psData = real(ps(data,p0));                                
                        base = arpls(psData);
                        psbsData = psData-base;

                        [~,locsPB,wPB,~] = findpeaks(psbsData,SortStr="descend");
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
                end
            end
            if isvalid(ax)
                imagesc(ax,ints');
                title(ax,sprintf('Phased integrals on range [%0.2f,%0.2f]',bds(1),bds(2)))
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
            [x,y,z,slice,rep] = obj.getFocus('r');
            if opts.stack
                specStack = obj.rData(:,x,y,z,slice,:);
            else
                specStack = obj.rData(:,x,y,z,slice,rep);
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
            [x,y,z,slice,rep] = obj.getFocus('r');
            specStack = obj.rData(:,x,y,z,slice,:);
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

        function dynAx = showAnalysis(obj,analysisInd,dt,opts)
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
                dt;
                opts.showData logical = true;
                opts.labels = {};
                opts.calcT1 logical = false;
            end
            tStep = dt;
            dynAx = axes(figure);
            if ~isempty(obj.analysis)
                if analysisInd<= length(obj.analysis)
                    ints = obj.analysis{analysisInd}.ints.Integrals;
                    hold(dynAx,"on")
                    
                    
                    if ~isnan(tStep)
                        xAx = (1:obj.nReps)*tStep;
                    else
                        xAx = (1:obj.nReps);
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
                    if ~isnan(tStep)
                        xlabel(dynAx,'Time (s)')
                    else
                        xlabel(dynAx,'Frames');
                    end
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
                reps = 1:obj.nReps;
            end
            angs = zeros(obj.nPoints,reps);
            [x,y,z,slice,~] = obj.getFocus("r");
            for rep = reps
                angs(:,rep) = rad2deg(unwrap(angle(obj.rData(:,x,y,z,slice,rep))));
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
                            yticks(ax,(1:obj.nReps));
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

        function updateLinkedPlots(obj,~)
            % Updates all active linked plots, purges invalid linked plots,
            % and automatically formats linked plots by calling setupPlot.
            % This is the function called by the 'showEdits' listener.
            [kx,ky,kz,~,~] = obj.getFocus("k");
            [rx,ry,rz,slice,rep] = obj.getFocus("r");

            rInd = obj.focus.rInd;
            kInd = obj.focus.kInd;
            obj.linkedPlots = obj.linkedPlots(~cellfun(@isempty,obj.linkedPlots));
            for ind = (1:length(obj.linkedPlots))
                linkedPlot = obj.linkedPlots{ind};
                ax = linkedPlot.ax;
                if ~isvalid(ax)
                    obj.linkedPlots{ind} = [];
                    continue
                end
                plotParams = linkedPlot.params;
                switch plotParams.type
                    case 'kPlot'
                        mrPlot("line",obj.kData(:,kx,ky,kz,slice,rep),ax,"mode",plotParams.mode);
                    case 'rPlot'
                        if strcmp(plotParams.xAx,'ppm')
                            mrPlot("line",obj.rData(:,rx,ry,rz,slice,rep),ax,{obj.xppm},...
                                           "mode",plotParams.mode);
                        else
                            mrPlot("line",obj.rData(:,rx,ry,rz,slice,rep),ax,"mode",plotParams.mode);
                        end
                    case 'spiral'
                        if strcmp(plotParams.xAx,'ppm')
                            mrPlot("spiral",obj.rData(:,rx,ry,rz,slice,rep),ax,{obj.xppm},...
                                           "mode",plotParams.mode);
                        else
                            mrPlot("spiral",obj.rData(:,rx,ry,rz,slice,rep),ax,"mode",plotParams.mode);
                        end
                    case 'kImage'
                        mrPlot("image",obj.kData(kInd,:,:,kz,slice,rep),ax,"mode",plotParams.mode);
                    case 'rImage'
                        mrPlot("image",obj.rData(rInd,:,:,rz,slice,rep),ax,"mode",plotParams.mode);
                    case 'rStack'
                        if strcmp(plotParams.xAx,'ppm')
                            mrPlot("line_stack",obj.rData(:,rx,ry,rz,slice,:),ax,{obj.xppm,1:obj.nReps},"mode",plotParams.mode);
                        else
                            mrPlot("line_stack",obj.rData(:,rx,ry,rz,slice,:),ax,"mode",plotParams.mode);
                        end
                    otherwise
                        error('Invalid Linked Plot Type');
                end
                reHold = ishold(ax);
                if obj.prefs.showFoc
                    hold(ax,'on');
                    try
                        obj.plotFocus(ax,plotParams.type,'xAx',plotParams.xAx);
                    end
                    hold(ax,'off');
                end
                if reHold
                    hold(ax,'on');
                end
                ppmStep = 5;
                if strcmp(plotParams.mode,'rStack')
                    ppmStep = 10;
                end
                obj.setupPlot(linkedPlot.ax,type=plotParams.type, ...
                                            mode=plotParams.mode, ...
                                            xAx = plotParams.xAx, ...
                                            ppmStep=ppmStep);
            end
        end
        
        function showLayout(obj,type)
            % Add commonly used linkedPlot setups here. This is simply a
            % wrapper function to create arrangements of linked plots
            % within tiled layouts. Currently supported layouts are:
            %
            % - 'K_RGrid': 2x2 grid of plots to visualize k-space
            %   processing and how it affects R-space
            %           ('kImage') ('rImage')
            %           ('kPlot' ) ('rPlot' )
            % - 'fid': 2x1 layout to display processing of a single FID and
            %          its corresponding spectrum
            %                 ('kPlot')
            %                 ('rPlot')
            arguments
                obj 
                type {mustBeMember(type,{'K_RGrid','fid','specSpace'})};
            end
            fig = figure;            
            switch type
                case 'K_RGrid'
                   tiles = tiledlayout(fig,2,2);
                   tiles.Padding = "compact";
                   tiles.TileSpacing = 'compact';
                   obj.linkPlot(nexttile,"type","kImage","mode","abs");
                   obj.linkPlot(nexttile,'type','rImage','mode','abs');
                   obj.linkPlot(nexttile,'type','kPlot','mode','abs','xAx','ppm');
                   obj.linkPlot(nexttile,'type','rPlot','mode','abs','xAx','ppm');
                case 'fid'
                   tiles = tiledlayout(fig,2,2);
                   tiles.Padding = "compact";
                   tiles.TileSpacing = 'compact';
                   obj.linkPlot(nexttile,'type','kPlot','mode','abs');
                   obj.linkPlot(nexttile,'type','rStack','mode','abs','xAx','ppm');
                   obj.linkPlot(nexttile,'type','rPlot','mode','abs','xAx','ppm');
                   obj.linkPlot(nexttile,'type','rPlot','mode','real','xAx','ppm');

                case 'specSpace'
                   tiles = tiledlayout(fig,2,2);
                   tiles.Padding = "compact";
                   tiles.TileSpacing = 'compact';
                   obj.linkPlot(nexttile,"type","rImage","mode","abs");
                   obj.linkPlot(nexttile,'type','rStack','mode','abs','xAx','ppm');
                   obj.linkPlot(nexttile,'type','rPlot','mode','abs','xAx','ppm');
                   obj.linkPlot(nexttile,'type','rPlot','mode','real','xAx','ppm');
                otherwise
                    warning('Unknown layout parameter!');
                
            end
        end

        function setKVoxel(obj)
            % Interactive method to allow the user to select a k-space
            % voxel which will then become the focused k_vox
            % - opts.show: (F => supresses listener)

            ax = axes(figure);
            kInd = obj.focus.kInd;
            [~,~,kz,slice,rep] = obj.getFocus("k");
            imagesc(ax,squeeze(abs(obj.kData( ...
                                        kInd,:,:,kz,slice,rep)))');
            title(ax,'PLEASE SELECT K-VOXEL');
            obj.plotFocus(ax,"kImage");
            try
                vox = drawpoint(ax);
            catch
                return
            end
            obj.focus.kXYZ = [round(vox.Position(1)),round(vox.Position(2)),kz];
            delete(ax.Parent);
            % fprintf('New k-Voxel: [%d,%d,%d]\n',obj.focus.kXYZ(1), ...
            %     obj.focus.kXYZ(2),obj.focus.kXYZ(3));
        end

        function setRVoxel(obj)
            % Interactive method to allow the user to select an r-space
            % voxel which will then become the focused r_vox

            ax = axes(figure);
            [~,~,rz,slice,rep] = obj.getFocus("r");
            rInd = obj.focus.rInd;
            imagesc(ax,squeeze(abs(obj.rData( ...
                                        rInd,:,:,rz,slice,rep)))');
            title(ax,'PLEASE SELECT R-VOXEL');
            obj.plotFocus(ax,"rImage");
            try
                vox = drawpoint(ax);
            catch
                return
            end
            obj.focus.rXYZ = [round(vox.Position(1)),round(vox.Position(2)),rz];
            delete(ax.Parent);
        end

        function linkPlot(obj,ax,opts)
            % Function used to add linked plots. Linked plots will
            % automatically updated when the showEdits listener is called
            % and can be manually updated by calling obj.updateLinkedPlots
            %
            % - opts.type: type of plot to be linked. valid types:
            %     ('kPlot','rPlot','kImage','rImage','rStack','spiral')
            % - opts.mode: mode of plot to be linked. ('abs','real','imag')
            % - opts.xAx: axis to use for the frequency domain ('ind' or
            %             'ppm')
            % Function will automatically call updateLinkedPlots to
            % instantiate the new plot and update all others.

            arguments
                obj 
                ax 
                opts.type {mustBeMember(opts.type,{'kPlot','rPlot','kImage','rImage','rStack','spiral'})};
                opts.mode {mustBeMember(opts.mode,{'abs','real','imag'})};
                opts.xAx {mustBeMember(opts.xAx,{'ind','ppm'})} = 'ind';
            end
            %cla(ax);
            delInds = [];
            for idx = (1:length(obj.linkedPlots))
                if obj.linkedPlots{idx}.ax == ax
                    delInds(end+1) = idx; %#ok<AGROW>
                end
            end
            for ind = (1:length(delInds))
                if ind<=length(obj.linkedPlots)
                    obj.linkedPlots(delInds(ind)) = [];
                end
                obj.linkedPlots = squeeze(obj.linkedPlots);
            end
            plotParams = struct('mode',opts.mode, ...
                                'type',opts.type, ...
                                'xAx',opts.xAx);
            obj.linkedPlots{end+1} = struct('ax',ax, ...
                                            'params',plotParams);
            obj.updateLinkedPlots;
        end
   
        function M = visualizeDecay(obj,opts)
            % Method intended to help the user visualize how a spectrum (or
            % specific regions of a spectrum) decay over time. The
            % spectrum is specified by obj.focus. VisualizeDecay will 
            % return a movie object (M) which can be used to reproduce 
            % the animation.
            %
            % - opts.mode: mode to use for animation ('real','imag','abs')
            % - opts.pickRegion: set flag true to allow the user to select
            %                    a rectangular region which will be used to
            %                    crop down the animation bounds. If set
            %                    false then the entire spectrum will be
            %                    displayed
            % - opts.dt: timestep in seconds between frames
            arguments
                obj 
                opts.mode {mustBeMember(opts.mode,{'real','abs','imag'})} = 'real';
                opts.pickRegion logical = false;
                opts.dt = 0.5;
            end
            ax = axes(figure);
            [x,y,z,slice,rep] = obj.getFocus("r");
            [xmin,xmax] = bounds(obj.xppm);
            ymins = zeros(size(obj.nReps));
            ymaxs = zeros(size(obj.nReps));
            for idx = 1:obj.nReps
                switch opts.mode
                    case 'real'
                        [ymin_local,ymax_local] = bounds(real(obj.rData(:,x,y,z,slice,idx)));
                    case 'abs'
                        [ymin_local,ymax_local] = bounds(abs(obj.rData(:,x,y,z,slice,idx)));
                    case 'imag'
                        [ymin_local,ymax_local] = bounds(imag(obj.rData(:,x,y,z,slice,idx)));
                end
                ymins(idx) = ymin_local;
                ymaxs(idx) = ymax_local;
            end
            ymin = min(ymins);
            ymax = max(ymaxs);
            if opts.pickRegion
                switch opts.mode
                    case 'real'
                        plot(ax,obj.xppm,real(obj.rData(:,x,y,z,slice,rep)));
                    case 'imag'
                        plot(ax,obj.xppm,imag(obj.rData(:,x,y,z,slice,rep)));
                    case 'abs'
                        plot(ax,obj.xppm,abs(obj.rData(:,x,y,z,slice,rep)));
                end
                obj.setupPlot(ax,"type","rPlot","mode",opts.mode,"xAx","ppm");
                drawnow;
                region = drawrectangle(ax);
                [xmin,xmax] = bounds(region.Vertices(:,1));
                [ymin,ymax] = bounds(region.Vertices(:,2));
            end
            M(obj.nReps) = struct('cdata',[],'colormap',[]);
            for rep = (1:obj.nReps)
                try
                    switch opts.mode
                        case 'real'
                            plot(ax,obj.xppm,real(obj.rData(:,x,y,z,slice,rep)));
                        case 'imag'
                            plot(ax,obj.xppm,imag(obj.rData(:,x,y,z,slice,rep)));
                        case 'abs'
                            plot(ax,obj.xppm,abs(obj.rData(:,x,y,z,slice,rep)));
                    end  
                    obj.setupPlot(ax,"type","rPlot","mode","real","xAx","ppm");
                    subtitle(ax,sprintf('Rep %d',rep));
                    xlim(ax,[xmin,xmax]);
                    ylim(ax,[ymin,ymax]);
                    drawnow;
                    pause(opts.dt);
                catch
                    %assume: ax no longer valid
                    continue
                end
            end
            if isvalid(ax)
                delete(ax.Parent);
            end
        end
        
    end
end
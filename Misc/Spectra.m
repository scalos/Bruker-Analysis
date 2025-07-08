classdef Spectra < handle
    properties
        nPoints
        nReps
        xppm = NaN
        dataRaw = NaN
        sysParams = struct;
        procParams = struct('phi0',NaN,'phi1',NaN, ...
            'pivotMode',NaN,'pivotVal',NaN,'phase',NaN,'baselines',NaN);
        viewRep = 1;
        analysis = {};
    end

    properties (Dependent)
        data
    end

    properties (Access = private)
        data_
    end

    properties (Access = public)
        suppressContructorWarnings = false
        showingEdits = false;
        linkedPlots = {}; %linkedPlots{n} = struct{'ax',ax,'params',structParams}
        linkedFigs = {};
        linkedCols = 1;
        linkedRows = 1;
    end

    events
        showEdits
    end

    methods
        function obj = Spectra(data,opts)
            arguments
                data;
                opts.params = [];
                opts.hzBW = [];
                opts.mhzCF = [];
                opts.ppmCF = [];
                opts.flipAng = [];
                opts.TR = [];
                opts.suppressContructorWarnings
            end
            if ~isempty(opts.params)
                obj.sysParams = opts.params;
            else
                obj.sysParams = rmfield(opts,'params');
            end
            obj.data = data; %(nPoints nReps)
            obj.dataRaw = data;
            obj.sysParams.ppmBW = [];
            if ~isempty(obj.sysParams,'hzBW') && ~isempty(obj.sysParams,'mhzCF')
                obj.sysParams.ppmBW = obj.sysParams.hzBW/obj.sysParams.mhzCF;
            end
            
            if isempty(obj.sysParams,'hzBW') ||...
               isempty(obj.sysParams,'mhzCF')||...
               isempty(obj.sysParams,'ppmCF')

                if ~obj.suppressContructorWarnings
                    warning("Couldn't load all spectral parameters!")
                end
            end         
            [obj.nPoints,obj.nReps] = size(data);
            obj.procParams.pivotMode = 'ppm';
            obj.procParams.baselines = cell(obj.nReps,1);
            if ~isempty(obj.sysParams.ppmBW)
			    xppmAxis = (obj.sysParams.ppmBW/obj.nPoints)*(1:obj.nPoints);
			    obj.xppm = fliplr(xppmAxis)-(obj.sysParams.ppmBW/2-obj.sysParams.ppmCF);
            end

            obj.setListeners;
        end
        
        function set.data(obj,val)
            obj.data_ = val;
            notify(obj,'showEdits');
        end

        function val = get.data(obj)
            val = obj.data_;
        end

        function setListeners(obj)
            addlistener(obj,'showEdits',@updateLinkedPlots);
        end
		
        function intsArr = peakInts(obj,intBds,bdsType,dataType,opts)
            arguments
                obj
		        intBds (2,1) {mustBeNumeric};
                bdsType {mustBeMember(bdsType,{'ppm','ind'})};
                dataType {mustBeMember(dataType,{'abs','real','image'})} = 'abs';
		        opts.flipAdjust {mustBeNumericOrLogical} = false %correct integrals using flip ang
                opts.decayCorr {mustBeNumericOrLogical} = false %correct for polarization decay from measurements
            end

            switch bdsType
                case 'ppm'
                    if isnan(obj.xppm)
                        error(['Properties "hzBW" and "mhzCF" must be set' ...
                            'to perform integration over a ppm range!'])
                    end
                    [~,intStartInd] = min(abs(obj.xppm-max(intBds)));
			        [~,intEndInd] = min(abs(obj.xppm-min(intBds)));
                case 'ind'
                    intStartInd = min(intBds);
                    intEndInd = max(intBds);
            end
            switch dataType
                case 'abs'
			        intsArr = sum(abs(obj.data((intStartInd:intEndInd),:)),1);
                case 'real'
                    intsArr = sum(real(obj.data((intStartInd:intEndInd),:)),1);
                case 'imag'
                    intsArr = sum(imag(obj.data((intStartInd:intEndInd),:)),1);
            end

			if opts.flipAdjust
                if isnan(obj.sysParams.flipAng)
                    error('A flip angle is required to apply integral corrections!');
                else
  				    flipAngRad = obj.sysParams.flipAng*pi/180;	
				    for i = (1:length(intsArr))
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

        function obj = revert(obj,toRevert)
            arguments
                obj
                toRevert {mustBeMember(toRevert,{'all','baseline','phase'})} = 'all';
            end
            switch toRevert
                case 'all'
                    obj.resetPhasing;
                    obj.procParams.baselines = cell(obj.nReps,1);
                    notify(obj,'processing');
                case 'baseline'
                    obj.procParams.baselines = cell(obj.nReps,1);
                    notify(obj,'processing');
                case 'phase'
                    obj.resetPhasing;
                    notify(obj,'processing');
                otherwise
                    warning('Not a valid revert request!');
            end
        end

        function resetPhasing(obj)
            obj.procParams.phi0 = NaN;
            obj.procParams.phi1 = NaN;
            obj.procParams.pivotMode = NaN;
            obj.procParams.pivotVal = NaN;
            obj.procParams.phase = NaN;
        end
        
        function updateProcessing(obj,~)
            obj.data = obj.dataRaw;
            if ~isnan(obj.procParams.phase)
                obj.data = obj.data.*exp(1i*deg2rad(obj.procParams.phase));
            end
            
            for rep = (1:obj.nReps)
                if ~isempty(obj.procParams.baselines{rep})
                    base = obj.procParams.baselines{rep};
                    obj.data(:,rep) = obj.data(:,rep)-base;
                end
            end
            notify(obj,'showEdits');
        end

        function setupPpmPlot(obj,ax,varargin)
            ppmStep = 5;
            type = 'plot';
            for ind = (1:length(varargin))
                switch varargin{ind}
                    case 'ppmStep'
                        ppmStep = varargin{ind+1};
                    case 'type'
                        type = varargin{ind+1};
                end
            end
            xticks(ax,round((obj.xppm(end):ppmStep:obj.xppm(1))/ppmStep)*ppmStep);
            set(ax,'xdir','reverse');
            xlabel(ax,'ppm');
            switch type
                case 'plot'
                    ylabel(ax,'Signal');
                case 'waterfall'
                    ylabel(ax,'Time (s)');
                    zlabel(ax,'Signal');
                case 'spiral'
                    ylabel(ax,'In-Phase Signal');
                    zlabel(ax,'Quadrature Signal');
            end
        end
        
        function autoBase(obj,reps,opts)
            arguments
                obj 
                reps = -1;
                opts.lambda {mustBeNumeric} = 1e4;
                opts.ratio {mustBeNumeric} = 0.05;
                opts.itermax {mustBeInteger} = 100;
            end
            if reps == -1
                reps = (1:obj.nReps);
            end
            for rep = reps
                base = arpls(squeeze(real(obj.data(:,rep))), ...
                            opts.lambda,opts.ratio,opts.itermax);
                obj.procParams.baselines{rep} = base;
            end
            notify(obj,'processing');
        end
        
        function obj = manualBaseline(obj,opts)
            %Not recommended. Use autoBase instead.
            arguments
                obj
                opts.snapY {mustBeNumericOrLogical} = true;
                opts.interpMode char {mustBeMember(opts.interpMode,{'linear','spline'})} = 'spline'
                opts.tailStep {mustBeNumeric} = 2;
            end
            ax = axes(figure,Visible='off');
            working = true;
            plot(ax,real(obj.data(:,obj.viewRep)));
            savedBaseline = false;
            try
                drawnLine = drawpolyline(ax,'lineWidth',1.5);
                if ~isvalid(drawnLine)
                    return
                end
            catch
                return
            end
            while working
                if ~isvalid(drawnLine)
                    try
                        drawnLine = drawpolyline(ax,'lineWidth',1.5);
                        if ~isvalid(drawnLine)
                            return
                        end
                    catch
                        return
                    end
                end
                drawnXs = drawnLine.Position(:,1);
                drawnYs = drawnLine.Position(:,2);
                if exist('baseCurve','var')
                    if isvalid(baseCurve)
                        delete(baseCurve);
                    end
                end
                if exist('newSpecCurve','var')
                    if isvalid(newSpecCurve)
                        delete(newSpecCurve);
                    end
                end
                xs = drawnXs;
                ys = drawnYs;
                if opts.snapY
                    for ind = 1:length(xs)
                        %snap ys to data
                        ys(ind) = real(obj.data(round(xs(ind)),obj.viewRep));
                    end
                end
                step = opts.tailStep;
                ys = cat(1,real(obj.data(1:step:round(min(xs)),obj.viewRep)),ys);
                xs = cat(1,(1:step:round(min(xs)))',xs);
                ys = cat(1,ys,real(obj.data(round(max(xs)):step:obj.nPoints,obj.viewRep)));
                xs = cat(1,xs,(round(max(xs)):step:obj.nPoints)');
    
                baseline = interp1(xs,ys,(1:obj.nPoints),opts.interpMode,'extrap')';
                hold(ax,'on');
                baseCurve = plot(ax,real(baseline),'Color',"#A2142F");
                newSpecCurve = plot(ax,real(obj.data(:,obj.viewRep)-baseline),'Color',"#77AC30");
                hold(ax,'off');
                inpt = input('Recalculate/Confirm (r/c): ','s');
                switch inpt
                    case 'r'
                        continue;
                    case 'c'
                        
                        working = false;
                        obj.procParams.baseline = baseline;
                        notify(obj,'processing');
                        notify(obj,'showEdits');
                        savedBaseline = true;
                    case 'exit'
                        working = false;
                end
            end
            if ~savedBaseline
                deciding = true;
                while deciding
                    inpt = input('Would you like to save the baseline from this session? (y/n): ','s');
                    switch inpt
                        case 'y'
                            obj.procParams.baseline = baseline;
                            notify(obj,'processing');
                            notify(obj,'showEdits');
                        case 'n'
                            deciding = false;
                        otherwise
                            disp('Unrecognized response.');
                    end
                end
            end
        end

        function angs = angles(obj)
            angs = zeros(size(obj.data));
            for rep = (1:obj.nReps)
                angs(:,rep) = rad2deg(unwrap(angle(obj.data(:,rep))));
            end
        end
        
        % function writeParams(obj)
        %     obj.paramFile = 'spectra_procParams.txt';
        %     paramTbl = struct2table(obj.procParams,AsArray=true);
        %     paramTbl.baseline = 'LinearInterp';
        %     paramTbl.Date = {datetime("now","Format","MM/dd/uuuu")};
        %     paramTbl = removevars(paramTbl,'phase');
        %     disp(paramTbl);
        %     writetable(paramTbl,obj.paramFile,'delimiter', '\t');
        %     obj.baselineFile = 'specBaseline.txt';
        %     writematrix(obj.procParams.baseline,obj.baselineFile);
        % end

        function updateLinkedPlots(obj,~)
            delInds = [];
            if obj.showingEdits
                for ind = (1:length(obj.linkedPlots))
                    linkedPlot = obj.linkedPlots{ind};
                    ax = linkedPlot.ax;
                    if ~isvalid(ax)
                        delInds(end+1) = ind;
                        continue
                    end
                    cla(ax);
                    pltParams = linkedPlot.params;
                    overlay = false;
                    if iscellstr(pltParams.mode)
                        overlay = true;
                    end
                    if overlay && strcmp(pltParams.type,'waterfall')
                        error('Overlay not available for waterfall plots!');
                    end
                    if ~overlay
                        modes = {pltParams.mode};
                    else
                        modes = pltParams.mode;
                    end
                    
                    hold(ax,'on');
                    if strcmp(pltParams.type,'spiral')
                        plot3(ax,obj.xppm, ...
                            real(squeeze(obj.data(:,obj.viewRep)))',...
                            imag(squeeze(obj.data(:,obj.viewRep)))');
                    else
                        for idx = 1:numel(modes)
                            mode = modes{idx};
                            switch mode
                                case 'real'
                                    switch pltParams.type
                                        case 'plot'
                                            plot(ax,obj.xppm,real(obj.data(:, ...
                                                obj.viewRep)));
                                        case 'waterfall'
                                            waterfall(ax,obj.xppm,(1:obj.nReps)*obj.sysParams.TR,real(obj.data)');
                                        otherwise
                                            error('Invalid Linked Plot Type');
                                    end
                                case 'abs'
                                    switch pltParams.type
                                        case 'plot'
                                            plot(ax,obj.xppm,abs(obj.data(:, ...
                                                obj.viewRep)));
                                        case 'waterfall'
                                            waterfall(ax,obj.xppm,(1:obj.nReps)*obj.sysParams.TR,abs(obj.data)');
                                        otherwise
                                            error('Invalid Linked Plot Type');
                                    end
                                case 'imag'
                                    switch pltParams.type
                                        case 'plot'
                                            plot(ax,obj.xppm,imag(obj.data(:, ...
                                                obj.viewRep)));
                                        case 'waterfall'
                                            waterfall(obj.linkedPlots,obj.xppm, ...
                                                (1:obj.nReps)*obj.sysParams.TR,imag(obj.data)');
                                        otherwise
                                            error('Invalid Linked Plot Type');
                                    end
                                case 'phase'
                                    angs = obj.angles;
                                    switch pltParams.type
                                        case 'plot'
                                            plot(ax,obj.xppm,angs(:, ...
                                                obj.viewRep));
                                        case 'waterfall'
                                            waterfall(obj.linkedPlots,obj.xppm, ...
                                                (1:obj.nReps)*obj.sysParams.TR,angs');
                                        otherwise
                                            error('Invalid Linked Plot Type');
                                    end
                            end
                        end
                    end
                    obj.setupPpmPlot(linkedPlot.ax,'type',linkedPlot.params.type);
                    hold(ax,'off');
                end
                for ind = (1:length(delInds))
                    obj.linkedPlots(delInds(ind)) = [];
                end
            end
        end

        function interactivePhase(obj,opts)
            arguments
                obj
                opts.makeFig {mustBeNumericOrLogical} = false;
            end
            obj.procParams.pivotMode = 'ppm';
            keepGoing = true;
            phi0 = obj.procParams.phi0;
            phi1 = obj.procParams.phi1;
            step = 10;
            pivot = obj.procParams.pivotVal;
            if opts.makeFig
                obj.linkPlot(axes(figure));
            end
            if isnan(phi0)
                phi0 = 0;
            end
            if isnan(phi1)
                phi1 = 0;
            end
            if isnan(pivot)
                pivot = 0;
            end
            while keepGoing
                res = input(sprintf("phi0,pivot,phi1,step = [%08.4f,%08.4f,%08.4f,%08.4f]",phi0,pivot,phi1,step),"s");
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
                        pivot = pivot+step;
                    case 'a'
                        pivot = pivot-step;
                    case 'pivotMode'
                        mode = input('Pivot Mode (''ppm''/''ind''): ','s');
                        if strcmp(mode,'ppm')||strcmp(mode,'ind')
                            obj.procParams.pivotMode = mode;
                        else
                            warning('Invalid Pivot Mode!');
                        end
                    case 'pivotVal'
                        newPivot = input('Pivot Val: ','s');
                        pivot = str2double(newPivot);
                    case 'reset'
                        obj.revert;
                        phi0 = 0;
                        phi1 = 0;
                        step = 10;
                    case 'exit'
                        keepGoing = false;
                end
                obj.applyPhase(phi0,pivot,obj.procParams.pivotMode,phi1);
                drawnow;
            end
        end

        function showWindows(obj,fig,rep,varargin)
            obj.linkedPlots = {};
            for ind = (1:length(varargin))
                switch varargin{ind}
                    case 'all'
                       obj.linkedCols = 2;
                       obj.linkedRows = 2;
                       tiles = tiledlayout(fig, ...
                           obj.linkedCols,obj.linkedRows);

                       rPlot = nexttile(tiles,1);
                       obj.linkPlot(rPlot,'type','plot','mode','real', ...
                           'linkedRep',rep);

                       aPlot = nexttile(tiles,2);
                       obj.linkPlot(aPlot,'type','plot','mode','abs', ...
                           'linkedRep',rep);

                       pPlot = nexttile(tiles,3);
                       obj.linkPlot(pPlot,'type','plot','mode','phase', ...
                           'linkedRep',rep);

                       wPlot = nexttile(tiles,4);
                       obj.linkPlot(wPlot,'type','waterfall','mode','abs', ...
                           'linkedRep',rep);
                end
            end
        end

        function linkPlot(obj,ax,varargin)
            plotParams = struct('mode','real','type','plot');
            for ind = (1:length(varargin))
                try
                    name = string(varargin{ind});
                catch
                    continue
                end
                switch name
                    case 'mode'
                    plotParams.mode = varargin{ind+1};
                    case 'type'
                    switch varargin{ind+1}
                        case 'plot'
                            plotParams.type = 'plot';
                        case 'waterfall'
                            plotParams.type = 'waterfall';
                        case 'spiral'
                            plotParams.type = 'spiral';
                        otherwise
                            warning('Not a recognized plot type!');
                    end
                end
            end
            obj.linkedPlots{end+1} = struct('ax',ax,'params',plotParams);
            obj.showingEdits = true;
            obj.updateLinkedPlots;
        end

        function removeLinkedPlot(obj,ax)
            for ind = (1:length(obj.linkedPlots))
                if obj.linkedPlots{ind}.ax == ax
                    obj.linkedPlots(ind) = [];
                end
            end
        end
       
        function loadBaseline(obj)
            [filename, path] = uigetfile('*.txt');
            if filename ~= 0
                obj.procParams.baseline = readmatrix(fullfile(path,filename));
                notify(obj,'processing')
            end
        end

        function obj = applyPhase(obj,zeroOrder,pivotVal,pivotSetting,firstOrder)
            arguments
                obj
                zeroOrder = NaN %deg
                pivotVal = NaN;
                pivotSetting = NaN % 'ppm' or 'ind'
                firstOrder = NaN %deg
            end
            
            if isnan(zeroOrder) 
                zeroOrder = obj.procParams.phi0; 
            end

            if isnan(firstOrder) 
                firstOrder = obj.procParams.phi1; 
            end
            obj.procParams.phi0 = zeroOrder;
            obj.procParams.phi1 = firstOrder;

            if isnan(pivotSetting)
                pivotSetting = obj.procParams.pivotMode;
            else
                obj.procParams.pivotMode = pivotSetting;
            end

            if isnan(pivotVal)
                pivotVal = obj.procParams.pivotVal;
            else
                obj.procParams.pivotVal = pivotVal;
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
                end
                if isnan(firstOrder)
                    phase = zeroOrder;
                else
                    phase = ((1:obj.nPoints)'-pivotInd)*firstOrder+zeroOrder;
                end
                obj.procParams.phase = phase;
                notify(obj,'processing');
            end
        end
    
        function int = localAutoProc(obj,bounds,boundsType,noiseThresh,opts)
            arguments
                obj
                bounds (2,1) {mustBeNumeric};
                boundsType {mustBeNonzeroLengthText};
                noiseThresh {mustBeNumeric} = 3; %# of std above mean;
                opts.showProc {mustBeNumericOrLogical} = false;
                opts.baseline {mustBeNumericOrLogical} = true;
                opts.integrate {mustBeNumericOrLogical} = true;
                opts.adoptProc {mustBeNumericOrLogical} = false;
                opts.showBase {mustBeNumericOrLogical} = false;
                opts.flipCorr {mustBeNumericOrLogical} = true;
                opts.interpMode char {mustBeMember(opts.interpMode,{'linear','spline'})} = 'linear'
            end
            int = NaN;
            if opts.integrate && ~opts.baseline
                warning('Cannot compute integral without baseline subtraction!');
            end
            switch boundsType
                case 'ppm'
                    [~,bounds(1)] = min(abs(obj.xppm-bounds(1)));
                    [~,bounds(2)] = min(abs(obj.xppm-bounds(2)));
                case 'ind'
                    %do nothing
                otherwise
                    error("Valid bounds types are: 'ppm' or 'ind'");
            end
            bounds = sort(bounds);
            
            bestPeak = NaN;
            bestPhi0 = 0;
            bestBaseline = NaN;
            diff = 10e10;
            foundPhi0 = false;

            if opts.showProc
                fig = figure;
                tiles = tiledlayout(fig,2,2);
                unproc = nexttile(tiles,1);
                title(unproc,'Unprocessed Spectrum within bounds');
                proc = nexttile(tiles,2);
                title(proc,'Flattened Spectrum within bounds');
                sides = nexttile(tiles,3,[1,2]);
                title(sides,'Left and right sides of the detected peak')
            end
            dataRangeRaw = obj.dataRaw(min(bounds):max(bounds),obj.viewRep);
            %autophase:
            for phi0 = (-180:1:180)
                %improve phase scanning
                    %initial steps by 10 -> then reduce to 1 when reaches
                    %thresh
                dataRange = real(dataRangeRaw.*exp(1i*deg2rad(phi0)));
                rangeSlope = (dataRange(end)-dataRange(1))/length(dataRange);
                rangeLine = rangeSlope*((1:length(dataRange))...
                    -round(length(dataRange)/2))+dataRange(round(length(dataRange)/2));
                rangeFlat = dataRange-rangeLine';

                [pks,locs,w,p] = findpeaks(rangeFlat);
                %TODO: fit gaussian to maxProm peak
                    % => get better estimate of relevant peak width
                if ~isempty(locs)
                    x = (1:length(dataRange))';
                    [~,maxP] = max(p);
                    peak = struct('ind',locs(maxP),'height',pks(maxP),'width',w(maxP),'prom',p(maxP));
                    range_noPeak = rangeFlat(x(x<(locs(maxP)-w(maxP)/2)| ...
                                             x>(locs(maxP)+w(maxP)/2)));
                    thresh = mean(range_noPeak)+ ...
                            noiseThresh*abs(std(range_noPeak));
                    if opts.showProc
                        title(tiles,'Phasing...')
                        subtitle(tiles,sprintf('phi0 = %d | Best: %d',phi0,bestPhi0));
                        plot(unproc,dataRange);
                        title(unproc,'Unprocessed Spectrum');

                        plot(proc,x,rangeFlat,x(locs(locs~=peak.ind)),pks(pks~=peak.height),'pg')
                        hold(proc,'on')
                        scatter(proc,peak.ind,peak.height,'filled','v','LineWidth',1,'color','r');
                        hold(proc,'off');
                        title(proc,'Flattened Spectrum');

                        nThresh = yline(proc,thresh, ...
                            'DisplayName','Noise Thresh', ...
                            'color',[0.4660 0.6740 0.1880], ...
                            'LineWidth',2);
                        xline(proc,peak.ind);
                        legend(proc,nThresh);
                        drawnow;
                    end
                    
    
                    if peak.height>thresh
                        leftSide = rangeFlat(1:peak.ind);
                        rightSide = rangeFlat(peak.ind:end);
                        
                        minSize = min(size(leftSide),size(rightSide));
                        %Crop sides to be of equal length
                            % Should ideally crop all the way down to
                            % relevent peak width (once there's better
                            % estimate from gaussian fitting
                        rightSide = rightSide(1:minSize(1));
                        leftSide = leftSide(end-minSize(1)+1:end);
                        leftFlipped = flip(leftSide);

                        localDiff = abs(trapz(leftFlipped-rightSide));
                        if opts.showProc
                            cla(sides);
                            hold(sides,'on');
                            plot(sides,rightSide,'LineWidth',3);
                            plot(sides,leftFlipped,'LineWidth',3);
                            x = (1:length(rightSide))';
                            patch(sides,cat(1,x,flip(x)), ...
                                cat(1,rightSide,flip(leftFlipped)), ...
                                [0.9290 0.6940 0.1250],'FaceAlpha',0.3);
                            title(sides,'Left and right sides of the detected peak')
                            subtitle(sides,sprintf('Area: %0.2d | Best: %0.2d',localDiff,diff));
                            legend(sides,{'right','left','area'});
                            hold(sides,'off');
                        end
    
                        
                        if localDiff<diff
                           diff = localDiff;
                           foundPhi0 = true;
                           bestPeak = peak;
                           bestPhi0 = phi0;
                        end
                    end
                end
            end

            if foundPhi0 
                if opts.baseline
                    tailSize = (bounds(2)-bounds(1));
                    baselineBds = [bounds(1)-tailSize,...
                                   bounds(2)+tailSize];
                    baselineRangeRaw = obj.dataRaw(min(baselineBds):max(baselineBds),obj.viewRep);
                    baselineRange = real(baselineRangeRaw.*exp(1i*deg2rad(bestPhi0)));
                    
                    
                    stepSize = 3;
                    xs = (1:stepSize:length(baselineRange))';
                    peakWidth = 4*bestPeak.width/2;
                    % TODO: use relevant peak width from phasing here:
                    xs = xs(xs<tailSize+bestPeak.ind-peakWidth|xs>tailSize+bestPeak.ind+peakWidth);
                    % TODO: for remaining baselineRange -> use windowed
                    % mean to get better baseline
                        % - should also improve spline fitting
                        % - should also remove fiddly baseline parameters
                    if length(xs)>1
                        ys = baselineRange(xs);
                        xs = xs+baselineBds(1)-1;
                        bestBaseline = interp1(xs,ys,min(xs):max(xs),opts.interpMode,'extrap')';
                        bestBaseline = cat(1,zeros(min(xs)-1,1),bestBaseline);
                        bestBaseline = cat(1,bestBaseline,zeros(obj.nPoints-max(xs),1));
                        if length(bestBaseline)~=obj.nPoints
                            error('oops')
                        end
                        if opts.showBase
                            ax = axes(figure);
                            hold(ax,'on')
                            fullDataRange = real(obj.dataRaw(1:obj.nPoints,obj.viewRep).*exp(1i*deg2rad(bestPhi0)));
                            plot(ax,fullDataRange);
                            plot(ax,real(bestBaseline));
                            scatter(ax,real(xs),real(ys));
                            plot(ax,fullDataRange-real(bestBaseline));
                            legend(ax,{'No Baseline','Baseline','Baseline Points','After Baseline'})
                            hold(ax,'off');
                        end
                    
                    end
                    
                    if opts.integrate
                        params_0 = obj.procParams;
                        obj.applyPhase(bestPhi0);
                        obj.procParams.baseline = bestBaseline;
                        obj.updateProcessing;
                        % add option to display integration bounds
                        % report stdev?
                        if opts.flipCorr
                            ints = obj.peakInts(bounds,'ind','real',flipAdjust=true);
                            int = ints(1);
                        else
                            ints = obj.peakInts(bounds,'ind','real',flipAdjust=false);
                            int = ints(1);
                        end
                        obj.procParams = params_0;
                        obj.updateProcessing;
                    end
                end
            else
                int = mean(real(dataRangeRaw));
            end
            if opts.adoptProc
                obj.applyPhase(bestPhi0);
                obj.procParams.baseline = bestBaseline;
                obj.updateProcessing;
            end
        end

        function tbl = analyze(obj)
            ax = axes(figure,Visible='off');
            plot(ax,obj.xppm,real(mean(obj.data(:,obj.viewRep),2)));
            obj.setupPpmPlot(ax);
            %obj.linkPlot(ax,'type','plot','mode','real');
            drawnow;
            working = true;
            intRegions = {};
            noiseRegions = {};
            plot(ax,obj.xppm,real(mean(obj.data(:,obj.viewRep),2)));
            obj.setupPpmPlot(ax);
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
                            rectPts = intRegions{ind}.Position;
                            intBds = [rectPts(1),rectPts(1)+rectPts(3)];
                            [~,intStartInd] = min(abs(obj.xppm-max(intBds)));
                            [~,intEndInd] = min(abs(obj.xppm-min(intBds)));
                            step = (round(intBds(end))-round(intBds(1)))/...
                                (intEndInd-intStartInd);
                            curveX = round(min(intBds)):step:round(max(intBds));
                            curveX = flip(curveX);
                            curveY = real(obj.data(intStartInd,obj.viewRep));
                            for ppm = curveX(2:end)
                                [~,bdInd] = min(abs(obj.xppm-ppm));
                                curveY(end+1) = curveY(end)+...
                                    real(obj.data(bdInd,obj.viewRep));
                            end
                            curveSquish = rectPts(4)/(max(curveY)-min(curveY));
                            curveY = curveY.*curveSquish;
                            offset = 1.2*(rectPts(2)+rectPts(4));
                            curveY = curveY+offset;
                            hold(ax,'on');
                            overlay = plot(ax,curveX,curveY);
                            overlays{end+1} = overlay;
                            hold(ax,'off');
                        else
                            delInds(end+1) = ind;
                        end
                    end
                    for ind = (1:length(delInds))
                        intRegions(ind) = [];
                    end
                end
                response = input('regions(int/noise/confirm)','s');
                switch response
                    case 'int'
                        try
                            disp('Select Integration Region');
                            intRegions{end+1} = drawrectangle(ax);
                        catch
                            return
                        end
                    case 'noise'
                        try
                            disp('Select Noise Region');
                            noiseRegions{end+1} = drawrectangle(ax,'Color','r');
                        catch
                            return
                        end
                    case 'exit'
                        working = false;
                    case 'confirm'
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
                        noiseBds{end+1} = bds;
                        [~,intStartInd] = min(abs(obj.xppm-max(bds)));
	                    [~,intEndInd] = min(abs(obj.xppm-min(bds)));
                        noiseStdevs{end+1} = std(real(obj.data(intStartInd:intEndInd,obj.viewRep)));
                        noiseMeans{end+1} = mean(real(obj.data(intStartInd:intEndInd,obj.viewRep)));
                    end
                    tbl = table(noiseBds',noiseMeans',noiseStdevs','VariableNames',["Bounds (ppm)","Mean",'Stdev']);
                    localAnalysis.noise = tbl;
                    
                end     
    
                if ~isempty(intRegions)
                    ints = {};
                    intBds = {};
                    for ind = 1:length(intRegions)
                        rectPts = intRegions{ind}.Position;
                        intBds{end+1} = [rectPts(1),rectPts(1)+rectPts(3)];
                        ints{end+1} = obj.peakInts([rectPts(1),rectPts(1)+rectPts(3)],'ppm','real',flipAdjust=true,decayCorr=false);
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
        end
    
        function dynAx = showAnalysis(obj,analysisInd,opts)
            arguments
                obj 
                analysisInd {mustBeGreaterThanOrEqual(analysisInd,1),mustBeInteger}
                opts.showData {mustBeNumericOrLogical} = true;
                opts.labels = {};
            end

            dynAx = axes(figure);
            if ~isempty(obj.analysis)
                if analysisInd<= length(obj.analysis)
                    ints = obj.analysis{analysisInd}.ints.Integrals;
                    hold(dynAx,"on")
                    time = (1:obj.nReps)*obj.sysParams.TR;
                    for ind = (1:length(ints))
                        plot(dynAx,time,ints{ind});
                    end
                    if ~isempty(opts.labels)
                        L = legend(dynAx,opts.labels);
                        L.AutoUpdate = "off";
                    end
                    for ind = (1:length(ints))
                        if opts.showData
                            scatter(dynAx,time,ints{ind},4,'black','filled');
                        end
                    end
                    hold(dynAx,'off');
                    title(dynAx,'Dynamic Curves');
                    ylabel(dynAx,'Signal');
                    xlabel(dynAx,'Time (s)');
                else
                    error('Requested analysis is out of range!');
                end
            end
            

        end
    
    end
end
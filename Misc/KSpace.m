classdef KSpace < handle

    properties
        fData
        dataRaw
        nPoints = NaN
        dimX = NaN
        dimY = NaN
        dimZ = NaN
        nReps = NaN
        sysParams = struct
        spaceTforms;
        showFocus = true;
        procParams = struct('blank',NaN,'lb',NaN,'zf',NaN);
    end

    properties (Access = private)
        % backing variables
        data_
        focus_
    end
    
    properties (Dependent)
        data
        focus
    end

    properties (Access = public)
        linkedPlots = {}; %linkedPlots{n} = struct{'ax',ax,'params',structParams}
        linkedFigs = {};
    end

    events
        showEdits
    end

    methods
        function obj = KSpace(data,opts)
            arguments
                data;
                opts.params = [];
                opts.hzBW = [];
                opts.mhzCF = [];
                opts.ppmCF = [];
                opts.flipAng = [];
                opts.TR = [];
                opts.dataShape = [];
            end
            % Data must be of shape: kt x kx x ky x kz x nReps
            obj.data = data; 
            obj.dataRaw = data;
            obj.focus = struct('viewRep',1,'kInd',1,'fInd',1,'kXYZ',[1,1,1],'fXYZ',[1,1,1]);
            if ~isempty(opts.params)
                obj.sysParams = opts.params;
            else
                obj.sysParams = rmfield(opts,'params');
            end
            if isempty(obj.sysParams.dataShape)
                if length(size(data))~=5
                    error(['Data must be of shape: kt x kx x ky x kz x nReps' ...
                        ' or shape must be specified']);
                else
                    obj.setDims;
                end
            else
                obj.setDims(obj.sysParams.dataShape);
            end

            if ~isempty(obj.sysParams.hzBW) && ~isempty(obj.sysParams.mhzCF)
                obj.sysParams.ppmBW = obj.sysParams.hzBW/obj.sysParams.mhzCF;
            end
            
            if isempty(obj.sysParams.hzBW) ||...
               isempty(obj.sysParams.mhzCF)||...
               isempty(obj.sysParams.ppmCF)

                warning(['Some methods will not be accessable without ' ...
                    'parameters "hzBW", "mhzCF","ppmCF".'])
            end
            obj.spaceTforms = {{'S','T'},...
                              {'S','T','S'},...
                              {'S','T','S'},...
                              {'S','T','S'},...
                              {}}; % transforms from k-space to real space
                                            % S-> ifftshift/fftshift,
                                            % T-> ifft/fft
            
            obj.setFData;
            
            addlistener(obj,'showEdits',@updateLinkedPlots);
        end

        function obj = revert(obj,toRevert)
            arguments
                obj
                toRevert {mustBeMember(toRevert,{'all','blank','lb','zf'})} = 'all'
            end
            switch toRevert
                case 'all'
                    obj.procParams.blank = NaN;
                    obj.procParams.zf = NaN;
                    obj.procParams.lb = NaN;
                    obj.focus = struct('viewRep',1,'kInd',100,'fInd',1, ...
                        'kXYZ',[1,1,1],'fXYZ',[1,1,1]);
                    obj.recalcProc;
                case 'blank'
                    obj.procParams.blank = NaN;
                    obj.data = obj.dataRaw;
                    obj.recalcProc;
                case 'lb'
                    obj.procParams.lb = NaN;
                    obj.recalcProc;
                case 'zf'
                    obj.procParams.zf = NaN;
                    obj.focus = struct('viewRep',1,'kInd',100,'fInd',1, ...
                        'kXYZ',[1,1,1],'fXYZ',[1,1,1]);
                    obj.recalcProc;
                otherwise
                    warning('Not a valid revert request!');
            end
        end

        function recalcProc(obj)
            obj.data = obj.dataRaw;
            if ~isnan(obj.procParams.blank)
                obj.blank(obj.procParams.blank);
            end
            if ~isnan(obj.procParams.lb)
                obj.lbExp(obj.procParams.lb);
            end
            if ~isnan(obj.procParams.zf)
                obj.zf(obj.procParams.zf);
            end
        end

        function obj = setDims(obj,shape)
            arguments
                obj
                shape = NaN;
            end
            if ~isnan(shape)
                obj.data = reshape(obj.data,shape);
                obj.dataRaw = reshape(obj.dataRaw,shape);
            end
            [obj.nPoints,obj.dimX,obj.dimY,obj.dimZ,obj.nReps] = size(obj.data);
        end

        function obj =  blank(obj, blankInd)
			arguments
				obj
                blankInd {mustBeInteger,mustBeGreaterThan(blankInd,0)}
            end
                obj.data = shift_data(obj.data,blankInd);
        end
		
		function obj = lbExp(obj,lb)
			arguments
				obj
				lb {mustBeInteger,mustBeGreaterThan(lb,0)} 
            end
            if anynan([obj.sysParams.ppmBW,obj.sysParams.mhzCF])
                error("Missing parameters: 'ppmBW' and 'mhzCF' required" + ...
                    "for line broadening");
            end
            
            obj.procParams.lb = lb;
            dt = (1/(obj.sysParams.ppmBW*obj.sysParams.mhzCF));
		    obj.data = apod(obj.data,lb,dt);
        end
		
        function set.data(obj,val)
            obj.data_ = val;
            obj.setFData;
            notify(obj,'showEdits');
        end

        function val = get.data(obj)
            val = obj.data_;
        end

        function set.focus(obj,val)
            obj.focus_ = val;
            notify(obj,'showEdits');
        end

        function val = get.focus(obj)
            val = obj.focus_;
        end

		function obj = zf(obj,fillFac)
			arguments
				obj
				fillFac {mustBeInteger,mustBeGreaterThan(fillFac,1)}    
			end;
            %Ensure zf = [fFill,xFill,yFill,zFill]
            %default: [1,1,1,1] => no zf on any dimensions
            zf = ones(4,1);
            zf(1:length(fillFac)) = fillFac;
            obj.procParams.zf = zf;
            obj.data = zFill(obj.data,fillFac);
        end

        function obj = setFData(obj)
            realTForms = {{'S','T'},...
                          {'S','T','S'},...
                          {'S','T','S'},...
                          {'S','T','S'},...
                          {}};
            obj.fData = K_R_Tform(obj.data,realTForms,"k");
        end
    
        function setupKPlot(obj,ax,varargin)
            for ind = (1:length(varargin))
                switch varargin{ind}
                    case 'type'
                        switch varargin{ind+1}
                            case 'kImage'
                                title(ax,'K-Space');
                                subtitle(ax,sprintf('Time index: %d', ...
                                    obj.focus.kInd));
                                xlabel(ax,'kx');
                                ylabel(ax,'ky');
                            case 'fImage'
                                title(ax,'Real-Space');
                                subtitle(ax,sprintf('Freq. index: %d', ...
                                    obj.focus.fInd));
                                xlabel(ax,'X');
                                ylabel(ax,'Y');
                            case 'kPlot'
                                title(ax,'FID');
                                subtitle(ax,sprintf('K-Space Voxel: [%d,%d]', ...
                                    obj.focus.kXYZ(1),obj.focus.kXYZ(2)));
                                xlabel(ax,'Time (index)');
                                ylabel(ax,'Signal');
                            case 'fPlot'
                                title(ax,'Absolute Spectrum');
                                subtitle(ax,sprintf('F-Space Voxel: [%d,%d]', ...
                                    obj.focus.fXYZ(1),obj.focus.fXYZ(2)));
                                xlabel('Frequency (index)');
                                ylabel('Signal');
                        end
                end
            end
        end

        function plotFocus(obj,ax,type)
            switch type
                case 'kPlot'
                    xline(ax,obj.focus.kInd);
                case 'fPlot'
                    xline(ax,obj.focus.fInd);
                case 'kImage'
                    x = obj.focus.kXYZ(1);
                    y = obj.focus.kXYZ(2);
                    outlinePix(ax,x,y,'r','linewidth',2);
                case 'fImage'
                    x = obj.focus.fXYZ(1);
                    y = obj.focus.fXYZ(2);
                    outlinePix(ax,x,y,'r','linewidth',2);
            end
        end

        function updateLinkedPlots(obj,~)
            delInds = [];
            for ind = (1:length(obj.linkedPlots))
                linkedPlot = obj.linkedPlots{ind};
                ax = linkedPlot.ax;
                if ~isvalid(ax)
                    delInds(end+1) = ind;
                    continue
                end
                plotParams = linkedPlot.params;
                kx = obj.focus.kXYZ(1);
                ky = obj.focus.kXYZ(2);
                kz = obj.focus.kXYZ(3);

                fx = obj.focus.fXYZ(1);
                fy = obj.focus.fXYZ(2);
                fz = obj.focus.fXYZ(3);
                rep = obj.focus.viewRep;
                fInd = obj.focus.fInd;
                kInd = obj.focus.kInd;
                cla(ax);
                switch plotParams.mode
                    case 'abs'
                        switch plotParams.type
                            case 'kPlot'
                                plot(ax,squeeze(abs( ...
                                    obj.data(:,kx,ky,kz,rep))))
                            case 'fPlot'
                                plot(ax,squeeze(abs( ...
                                    obj.fData(:,fx,fy,fz,rep))))
                            case 'kImage'
                                imagesc(ax,squeeze(abs(obj.data( ...
                                    kInd,:,:,kz,rep)))')
                            case 'fImage'
                                imagesc(ax,squeeze(abs(obj.fData( ...
                                    fInd,:,:,fz,rep)))')
                            otherwise
                                error('Invalid Linked Plot Type');
                        end
                    case 'real'
                        switch plotParams.type
                            case 'kPlot'
                                plot(ax,squeeze(real( ...
                                    obj.data(:,kx,ky,kz,rep))));
                            case 'fPlot'
                                plot(ax,squeeze(real( ...
                                    obj.fData(:,fx,fy,fz,rep))));
                            case 'kImage'
                                imagesc(ax,squeeze(real(obj.data( ...
                                    kInd,:,:,kz,rep)))');
                            case 'fImage'
                                imagesc(ax,squeeze(real(obj.fData( ...
                                    fInd,:,:,fz,rep)))');
                            otherwise
                                error('Invalid Linked Plot Type');
                        end
                        
                    case 'imag'
                        switch plotParams.type
                            case 'kPlot'
                                plot(ax,squeeze(imag( ...
                                    obj.data(:,kx,ky,kz,rep))));
                            case 'fPlot'
                                plot(ax,squeeze(imag( ...
                                    obj.fData(:,fx,fy,fz,rep))));
                            case 'kImage'
                                imagesc(ax,squeeze(imag(obj.data( ...
                                    kInd,:,:,kz,rep)))');
                            case 'fImage'
                                imagesc(ax,squeeze(imag(obj.fData( ...
                                    fInd,:,:,fz,rep)))');
                            otherwise
                                error('Invalid Linked Plot Type');
                        end
                        
                end
                hold(ax,'on');
                if obj.showFocus
                    obj.plotFocus(ax,plotParams.type);
                end
                hold(ax,'off');
                obj.setupKPlot(linkedPlot.ax,'type',linkedPlot.params.type);
            end
            for ind = (1:length(delInds))
                obj.linkedPlots(delInds(ind)) = [];
            end
        
        end
        
        function showWindows(obj,fig,varargin)
            obj.linkedPlots = {};
            for ind = (1:length(varargin))
                switch varargin{ind}
                    case 'csi'
                       linkedCols = 2;
                       linkedRows = 2;
                       tiledlayout(fig,linkedCols,linkedRows);
                       kImg = nexttile;
                       obj.linkPlot(kImg,"type","kImage","mode","abs");
                       fImg = nexttile;
                       obj.linkPlot(fImg,'type','fImage','mode','abs');
                       kPlot = nexttile;
                       obj.linkPlot(kPlot,'type','kPlot','mode','abs');
                       fPlot = nexttile;
                       obj.linkPlot(fPlot,'type','fPlot','mode','abs');
                    case 'fid'
                       linkedCols = 2;
                       linkedRows = 1;
                       tiledlayout(fig,linkedCols,linkedRows);
                       kPlot = nexttile;
                       obj.linkPlot(kPlot,'type','kPlot','mode','abs');
                       fPlot = nexttile;
                       obj.linkPlot(fPlot,'type','fPlot','mode','abs');
                    otherwise
                        warning('Unknown layout parameter!');
                
                end
            end
        end

        function setKVoxel(obj)
            ax = axes(figure,Visible='off');
            kInd = obj.focus.kInd;
            kz = obj.focus.kXYZ(3); 
            rep = obj.focus.viewRep;
            imagesc(ax,squeeze(abs(obj.data( ...
                                        kInd,:,:,kz,rep)))')
            title(ax,'PLEASE SELECT K-VOXEL')
            try
                vox = drawpoint(ax);
            catch
                return
            end
            obj.focus.kXYZ = [round(vox.Position(1)),round(vox.Position(2)),1];
            delete(ax.Parent);
            fprintf('New k-Voxel: [%d,%d,%d]\n',obj.focus.kXYZ(1), ...
                obj.focus.kXYZ(2),obj.focus.kXYZ(3));
        end

        function setFVoxel(obj)
            ax = axes(figure,Visible='off');
            fInd = obj.focus.fInd;
            fz = obj.focus.fXYZ(3); 
            rep = obj.focus.viewRep;
            imagesc(ax,squeeze(abs(obj.fData( ...
                                        fInd,:,:,fz,rep)))')
            title(ax,'PLEASE SELECT F-VOXEL')
            try
                vox = drawpoint(ax);
            catch
                return
            end
            obj.focus.fXYZ = [round(vox.Position(1)),round(vox.Position(2)),1];
            delete(ax.Parent);
        end

        function linkPlot(obj,ax,opts)
            arguments
                obj 
                ax 
                opts.type {mustBeMember(opts.type,{'kPlot','fPlot','kImage','fImage'})} = 'kImage';
                opts.mode {mustBeMember(opts.mode,{'abs','real','imag'})} = 'abs';
                opts.trail {mustBeInteger,mustBeGreaterThan(opts.trail,0)} = 1;
            end
            plotParams = struct('mode',opts.mode, ...
                                'type',opts.type, ...
                                'trail',opts.trail);
            
            obj.linkedPlots{end+1} = struct('ax',ax, ...
                                            'params',plotParams);
            obj.updateLinkedPlots;
        end
   
    end
end
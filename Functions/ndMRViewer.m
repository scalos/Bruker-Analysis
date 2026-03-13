classdef ndMRViewer <handle
    properties (SetObservable)
        data
        dispAx = gobjects(0);
        focus = [];
        dimLbls = [];
        intensityLbl = [];
        axMaps = {};
        cmap = [];
        visDims = [1,1,1];
        plotMode = 'abs';
        plotType = 'Average' 
        showFoc = 1;
    end
    properties (Dependent)
        prettyFocus;
    end

    properties
        currPlotHandle = gobjects(0);
        currFocHandle = gobjects(0);
        FocChangedFcn = [];
        listeners = {};
        reportRedrawRequests = 0;
    end

    properties %Private
        prevVisDims = [];
    end

    methods
        function obj = ndMRViewer(data,opts)
            arguments
                data
                opts.dispAx = gobjects(0); 
                opts.initFoc = []
                opts.dimLbls = {};
                opts.intensityLbl = 'Intensity';
                opts.axMaps = {};
                opts.cmap = parula(256);
                opts.FocChangedFcn = [];
                opts.showFoc = 1;
            end
            obj.data = data;
            obj.cmap = opts.cmap;
            obj.showFoc = opts.showFoc;
            axMaps = opts.axMaps;
            obj.FocChangedFcn = opts.FocChangedFcn;
            obj.intensityLbl = opts.intensityLbl;
            if isempty(axMaps)
                axMaps = cell(ndims(data),1);
                for ii = 1:ndims(data)
                    axMaps{ii} = 1:size(data,ii);
                end
            end
            obj.axMaps = axMaps;
            %TODO: validate Parent
            dispAx = opts.dispAx;
            if isempty(dispAx)
                dispAx = axes(figure);
            end
            obj.dispAx = dispAx;
            initFoc = opts.initFoc;
            if isempty(initFoc)
                initFoc = repmat({':'},[1,ndims(data)]);
            end
            obj.focus = initFoc;

            dimLbls = opts.dimLbls;
            if isempty(dimLbls)
                dimLbls = arrayfun(@(d) sprintf('dim %d', d), 1:ndims(data),'UniformOutput', false);
            end
            obj.dimLbls = dimLbls;
            addprop(obj.dispAx,'FocNav');
            obj.dispAx.FocNav = obj;
            obj.setListeners;
            obj.prevVisDims = obj.visDims;
            obj.setupTypeToggle;
            obj.redraw;


        end

        function set.plotType(obj,val)
            types = {'Average','Stack'};
            if ~ismember(val,types)
                error('ERROR, type options are: {%s}',strjoin(types,' ,'));
            end
            obj.plotType = val;
        end

        function setListeners(obj)
            % Attach listeners to all observable properties
            mc = metaclass(obj);
            props = mc.PropertyList;
            props = props([props.SetObservable]);
            
            excludeProps = {'focus'};
            for k = 1:numel(props)
                if ~ismember(props(k).Name,excludeProps)
                    obj.listeners{k} = addlistener( ...
                        obj, props(k).Name, ...
                        'PostSet', @(src,~) obj.redraw(src));
                end
            end
            
            % Cleanup if axes is deleted
            addlistener(obj.dispAx,'ObjectBeingDestroyed', ...
                @(~,~) delete);
            
            addlistener(obj,'focus','PostSet',@(src,evt) obj.focChg(src,evt));
            function delete(~)
                %todo: clean Listners
            end
        end

        function focChg(obj,src,evt)
            if ~isempty(obj.FocChangedFcn)
                func = obj.FocChangedFcn;
                if isa(func, 'function_handle')
                    func(src,evt,obj);
                end
            end
            obj.redraw(src);
        end

        function prettyFoc = get.prettyFocus(obj)
            prettyFoc = '(';
            for idx = 1:numel(obj.focus)
                entry = obj.focus{idx};
                if ~ischar(entry)
                    if numel(entry)>1
                        entry = sprintf('%d:%d',entry(1),entry(end));
                    else
                        entry = sprintf('%d',entry);
                    end
                end
                if idx>1
                    prettyFoc = sprintf("%s,%s",prettyFoc,entry);
                else
                    prettyFoc = sprintf("%s%s",prettyFoc,entry);
                end
    
            end
            prettyFoc = sprintf("%s)",prettyFoc);
        end
    
        function coords = ind2coord(obj,inds,dim)
            coordMap = obj.axMaps{dim};
            coords = reshape(coordMap(inds(:)),size(inds));
        end

        function dimFocLims = getFocDimLims(obj,dim)
            dimExpression = obj.focus(dim);
            fullRange = 1:size(obj.data,dim);
            dimFocRange = fullRange(dimExpression{:});
            dimFocLims = [dimFocRange(1),dimFocRange(end)];
        end

        function cleanFoc = getCleanFoc(obj,foc)
            cleanFoc = foc;
            for dim = 1:numel(foc)
                dimFoc = foc{dim};
                dimRange = obj.getFocDimLims(dim);
                if isequal(dimFoc,dimRange)
                    foc{dim} = ':';
                end
            end
    
        end

        function axMenuEvents(obj,src,evt)
            switch evt.EventName
                case 'MenuSelected'
                    menuData = getappdata(src);
                    if isfield(menuData,'DimIdx')&&...
                       isfield(menuData,'ControlDims')
                        ControlDims = menuData.ControlDims;
                        dimIdx = menuData.DimIdx;
                        obj.visDims(ControlDims) = dimIdx;
                    end
            end
        
        end

        function focRectEvts(obj,src,evt)
            opts = getappdata(src);

            function [snapPts,snapIdxs] = getSnapPts(validPts,currPts)
                currPts = currPts(:);
                validPts = validPts(:);
                snapPts = currPts;
                snapIdxs = zeros(size(snapPts));
                for idx = 1:numel(currPts)
                    [~,snapIdx] = min(abs(currPts(idx)-validPts));
                    snapPts(idx) = validPts(snapIdx);
                    snapIdxs(idx) = snapIdx;
                end
            end
            
            switch evt.EventName
                case 'ROIMoved'
                    newPos = src.Position;
                    newFoc = obj.focus;
                    xDim_ = obj.visDims(1);
                    yDim_ = obj.visDims(2);
                    snapMids = [1,1,1];
                    if isfield(opts,'snapMids')
                        snapMids = opts.snapMids;
                    end
                    if isfield(opts,'xSnapPts')
                        xSnapPts = opts.xSnapPts;
                        dx = [];
                        if numel(xSnapPts)>1
                            dx = xSnapPts(2)-xSnapPts(1);
                        end
                        if snapMids(1)&&~isempty(dx)
                            xSnapPts(end+1) = xSnapPts(end)+dx;
                            xSnapPts = xSnapPts-dx/2;
                        end
                        if ~isempty(xSnapPts)
                            currXLims = [newPos(1),newPos(1)+newPos(3)];
                            [newXLims,newXInds] = getSnapPts(xSnapPts,currXLims);
                            newPos([1,3]) = [newXLims(1),abs(newXLims(2)-newXLims(1))];
                            if ~isempty(dx)
                                newPos(3) = max(dx,newPos(3));
                            end
                            newFoc{xDim_} = newXInds(1):max(1,newXInds(2)-1);
                        end
                    end
                    if isfield(opts,'ySnapPts')
                        ySnapPts = opts.ySnapPts;
                        dy = [];
                        if numel(ySnapPts)>1
                            dy = ySnapPts(2)-ySnapPts(1);
                        end
                        if snapMids(2)&&~isempty(dy)
                            ySnapPts(end+1) = ySnapPts(end)+dy;
                            ySnapPts = ySnapPts-dy/2;
                        end
                        if ~isempty(ySnapPts)
                            currYLims = [newPos(2),newPos(4)+newPos(2)];
                            [newYLims,newYInds] = getSnapPts(ySnapPts,currYLims);
                            newPos([2,4]) = [newYLims(1),abs(newYLims(2)-newYLims(1))];
                            if ~isempty(dy)
                                newPos(4) = max(dy,newPos(4));
                            end
                            newFoc{yDim_} = newYInds(1):max(1,newYInds(2)-1);
                        end
                    end
                    newFoc = obj.getCleanFoc(newFoc);
                    src.Position = newPos;
                    if ~isequal(obj.focus,newFoc)
                        obj.focus = newFoc;
                    end
                case 'MovingROI'
                    newPos = src.Position;
                    if isfield(opts,'initPos')
                        initPos = opts.initPos;
                        
                        if isfield(opts,'freezeY')
                            if opts.freezeY
                                newPos([2,4]) = initPos([2,4]);
                            end
                        end
                        if isfield(opts,'freezeX')
                            if opts.freezeX
                                newPos([1,3]) = initPos([1,3]);
                            end
                        end
                    end
                    src.Position = newPos;
            end
        end

        function setupTypeToggle(obj)
            ax = obj.dispAx;
            tb = axtoolbar(ax,'default');
            plotTypeToggle = axtoolbarbtn(tb,'state');
            plotTypeToggle.ValueChangedFcn = @(src,evt) obj.togglePlotType(src,evt);
        end

        function togglePlotType(obj,src,~)
            ax = obj.dispAx;
            switch src.Value
                case 'on'
                    obj.plotType = 'Stack';
                    view(ax,3);

                    enableDefaultInteractivity(ax);
                case 'off'
                    obj.plotType = 'Average';
                    view(ax,2);
                    enableDefaultInteractivity(ax);
            end
        end
      
        function redraw(obj,src)
            arguments
                obj
                src = [];
            end
            if obj.reportRedrawRequests
                if exist('src','var')
                    if isempty(src)
                        disp('Redraw called internally');
                    else
                        fprintf('Property: "%s" requested redraw\n',src.Name);
                    end
                end
            end
            allDims = 1:ndims(obj.data);
            currFoc = obj.focus;
            
            dimsChgd = ~isequal(obj.visDims,obj.prevVisDims);


            xDim = obj.visDims(1);
            yDim = obj.visDims(2);
            zDim = obj.visDims(3);
            ax = obj.dispAx;
            cms = {uicontextmenu(ax.Parent),...
                   uicontextmenu(ax.Parent),...
                   uicontextmenu(ax.Parent)};
            for axIdx = 1:3
                cm = cms{axIdx};
                for dIdx = 1:numel(obj.dimLbls)
                    dimLbl = obj.dimLbls{dIdx};
                    dimMenu = uimenu(cm,"Text",dimLbl,'MenuSelectedFcn',@(src,evt) obj.axMenuEvents(src,evt));
                    setappdata(dimMenu,'DimIdx',dIdx);
                    setappdata(dimMenu,'ControlDims',axIdx);
                end
            end
            xyCM = uicontextmenu(ax.Parent);
            for dIdx = 1:numel(obj.dimLbls)
                dimLbl = obj.dimLbls{dIdx};
                dimMenu = uimenu(xyCM,"Text",dimLbl,'MenuSelectedFcn',@(src,evt) obj.axMenuEvents(src,evt));
                setappdata(dimMenu,'DimIdx',dIdx);
                setappdata(dimMenu,'ControlDims',[1,2]);
            end
            xCM = cms{1};
            yCM = cms{2};
            zCM = cms{3};
            plotOptions = {'linePlot','lineStack','image','imageStack'};
            if xDim==yDim
                if strcmp(obj.plotType,'Stack')
                    plotOption = plotOptions{2};
                else
                    plotOption = plotOptions{1};
                end
            else
                if strcmp(obj.plotType,'Stack')
                    plotOption = plotOptions{4};
                else
                    plotOption = plotOptions{3};
                end
            end
            if obj.reportRedrawRequests
                fprintf('Creating %s...\n',plotOption);
            end
            if ~strcmp(plotOption,'imageStack')
                if iscell(obj.currPlotHandle)
                    obj.currPlotHandle = [];
                end
            end
            hold(ax,'on');

            switch plotOption
                case 'linePlot'

                    currFoc{xDim} = ':';
                    focData = obj.data(currFoc{:});
                    plotData = squeeze(mean(focData,allDims(allDims~=xDim)));
                    switch obj.plotMode
                        case 'abs'
                            plotData = abs(plotData);
                        case 'real'
                            plotData = real(plotData);
                        case 'imag'
                            plotData = imag(plotData);
                    end
                    xs = obj.axMaps{xDim}(:);
                    dx = [];
                    if numel(xs)>1
                        dx = xs(2)-xs(1); 
                    end
                    if ~isempty(obj.currPlotHandle)
                        %If there is already a plot handle, check that it is
                        %the right type, if not, clear the handle
                        pltHdl = obj.currPlotHandle;
                        if isvalid(pltHdl)&&isa(pltHdl,'matlab.graphics.chart.primitive.Line')
                            set(pltHdl,'XData',xs);
                            set(pltHdl,'YData',plotData);
                        else
                            obj.currPlotHandle = gobjects(0);
                        end
                    end
    
                    if isempty(obj.currPlotHandle)
                        % if there is no attached handle, set one:
                        cla(ax);
                        obj.currPlotHandle = plot(ax,xs,plotData);
                    end
    
                    %Setup Axes:
                    if ~isempty(dx)&&dimsChgd
                        %xlim(ax,[xs(1),xs(end)]);
                        axis(ax,'padded');
                        zoom(ax,'reset');
                        %axis(ax,'normal');
                        set(ax,'YDir','normal');
                    end
                    xlabel(ax,obj.dimLbls(xDim));
                    ylabel(ax,obj.intensityLbl);
                    ax.XLabel.ContextMenu = xyCM;
                    ax.XLabel.Interactions = [];
                    ax.YLabel.ContextMenu = yCM;
                    ax.YLabel.Interactions = [];
    
                    
                    %Setup FocRect:
                    if obj.showFoc
                        if ~isempty(obj.currFocHandle)&&...
                            isvalid(obj.currFocHandle)&&...
                            isa(obj.currFocHandle,'images.roi.Rectangle')
                            focRect = obj.currFocHandle;
                        else
                            focRect = images.roi.Rectangle(ax);
                            addlistener(focRect,'ROIMoved',@(src,evt) obj.focRectEvts(src,evt));
                            addlistener(focRect,'MovingROI',@(src,evt) obj.focRectEvts(src,evt));
                            obj.currFocHandle = focRect;
                        end
                        focXLims = obj.ind2coord(obj.getFocDimLims(xDim),xDim);
                        focYLims = [min(plotData,[],'all','omitmissing'),max(plotData,[],'all','omitmissing')];

                        rectPos = [focXLims(1),focYLims(1),focXLims(2)-focXLims(1),focYLims(2)-focYLims(1)];
                        if ~isempty(dx)
                            rectPos = rectPos+[-dx/2,0,dx,0];
                        end
                        focRect.Position = rectPos;
                        setappdata(focRect,'xSnapPts',xs);
                        setappdata(focRect,'ySnapPts',[]);
                        setappdata(focRect,'snapMids',[1,1,1]);
                        setappdata(focRect,'freezeX',false);
                        setappdata(focRect,'freezeY',true);
                        setappdata(focRect,'initPos',rectPos);
                        
                        focRect.Rotatable = false;
                    end

                
                case 'lineStack'
                    %line stackplot (waterfall)
                    currFoc{xDim} = ':';
                    currFoc{zDim} = ':';
                    focData = obj.data(currFoc{:});
                    plotDims = 2;
                    if xDim~=zDim
                        focData = permute(focData,[xDim,zDim,allDims(~ismember(allDims,[xDim,zDim]))]);
                    else
                        focData = permute(focData,[xDim,allDims(~ismember(allDims,xDim))]);
                        plotDims = 1;
                    end
                    plotData = squeeze(mean(focData,(plotDims+1):ndims(focData)));
                    %plotData = squeeze(mean(focData,allDims(~ismember(allDims,[xDim,zDim]))));
                    switch obj.plotMode
                        case 'abs'
                            plotData = abs(plotData);
                        case 'real'
                            plotData = real(plotData);
                        case 'imag'
                            plotData = imag(plotData);
                    end
                    xs = obj.axMaps{xDim}(:);
                    if xDim==zDim
                        zs = 1;
                    else
                        zs = obj.axMaps{zDim}(:);
                    end
                    
                    dx = [];
                    if numel(xs)>1
                        dx = xs(2)-xs(1); 
                    end
                    dz = [];
                    if numel(zs)>1
                        dz = zs(2)-zs(1); 
                    end
                    
                    [xs_mesh,zs_mesh] = meshgrid(xs(:),zs(:));

                    if ~isempty(obj.currPlotHandle)
                        %If there is alread a plot handle, check that it is
                        %the right type, if not, clear the handle
                        pltHdl = obj.currPlotHandle;
                        if isvalid(pltHdl)&&isa(pltHdl,'matlab.graphics.primitive.Patch')
                            updateWaterfall(pltHdl,xs_mesh,zs_mesh,plotData');
                        else
                            obj.currPlotHandle = gobjects(0);
                        end
                    end

                    if isempty(obj.currPlotHandle)
                        % if there is no attached handle, set one:
                        cla(ax);
                        if ~isscalar(zs)
                            if ~isscalar(xs)
                                obj.currPlotHandle = waterfall(ax,xs_mesh,zs_mesh,plotData');
                            else
                                obj.currPlotHandle = waterfall(ax,1,zs_mesh,plotData');
                            end
                        else
                            obj.currPlotHandle = waterfall(ax,xs_mesh,1,plotData');
                        end
                    end

                    %Setup Axes:
                    if ~isempty(dx)&&dimsChgd
                        xlim(ax,[xs(1),xs(end)]);
                        %ylim(ax,[zs(1),zs(end)]);
                        [pltMin,pltMax] = bounds(plotData,"all");
                        zlim(ax,[pltMin,pltMax]);
                        axis(ax,'padded');
                        zoom(ax,'reset');
                        %axis(ax,'normal');
                        %set(ax,'YDir','normal');
                    end
                    xlabel(ax,obj.dimLbls(xDim));
                    zlabel(ax,obj.intensityLbl);
                    ylabel(ax,obj.dimLbls(zDim));
                    ax.XLabel.ContextMenu = xyCM;
                    ax.XLabel.Interactions = [];
                    ax.YLabel.ContextMenu = zCM;
                    ax.YLabel.Interactions = [];
                    ax.ZLabel.Interactions = [];
                    ax.ZLabel.ContextMenu = yCM;

                    
                case 'image'
                    currFoc{xDim} = ':';
                    currFoc{yDim} = ':';
                    
                    focData = obj.data(currFoc{:});
                    focData = permute(focData,[xDim,yDim,allDims(~ismember(allDims,[xDim,yDim]))]);
                    plotData = squeeze(mean(focData,3:ndims(focData)));
                    switch obj.plotMode
                        case 'abs'
                            plotData = abs(plotData);
                        case 'real'
                            plotData = real(plotData);
                        case 'imag'
                            plotData = imag(plotData);
                    end
                    xs = obj.axMaps{xDim}(:);
                    ys = obj.axMaps{yDim}(:);
                    dx = [];
                    if numel(xs)>1
                        dx = xs(2)-xs(1);
                    end
                    dy = [];
                    if numel(ys)>1
                        dy = ys(2)-ys(1);
                    end
                    
                    if ~isempty(obj.currPlotHandle)
                        pltHdl = obj.currPlotHandle;
                        if isvalid(pltHdl)&&isa(pltHdl,'matlab.graphics.primitive.Image')
                            set(pltHdl,'XData',[xs(1),xs(end)]);
                            set(pltHdl,'YData',[ys(1),ys(end)]);
                            set(pltHdl,'CData',plotData');
                        else
                            obj.currPlotHandle = gobjects(0);
                        end
                    end
    
                    if isempty(obj.currPlotHandle)
                        % if there is no attached handle, set one:
                        cla(ax);
                        obj.currPlotHandle = imagesc(ax,[xs(1),xs(end)],[ys(1),ys(end)],plotData');
                    end
    
                    %Set up axes:
                    if dimsChgd
                        if ismember(xDim,[2,3,4])&&ismember(yDim,[2,3,4])
                            %=> spatial plot
                            set(ax,'DataAspectRatio',[1,1,1]);
                        else
                            if numel(ys)<numel(xs)
                                if abs(numel(ys)*dy)>eps
                                    set(ax,'DataAspectRatio',[(numel(xs)*dx)/(numel(ys)*dy),1,1]);
                                else
                                    set(ax,'DataAspectRatio',[(numel(xs)*dx),1,1]);
                                end
                            else
                                if abs(numel(xs)*dx)>eps
                                    set(ax,'DataAspectRatio',[1,(numel(ys)*dy)/(numel(xs)*dx),1]);
                                else
                                    set(ax,'DataAspectRatio',[1,(numel(ys)*dy),1]);
                                end
                            end
                        end
                        % xlim([xs(1),xs(end)]);
                        % ylim([ys(1),ys(end)]);
                        axis(ax,'padded');
                        set(ax,'YDir','normal');
                    end
                    
                    %Set up FocRect:
                    if obj.showFoc
                        if ~isempty(obj.currFocHandle)&&...
                            isvalid(obj.currFocHandle)&&...
                            isa(obj.currFocHandle,'images.roi.Rectangle')
                            focRect = obj.currFocHandle;
                        else
                            focRect = images.roi.Rectangle(ax);
                            addlistener(focRect,'ROIMoved',@(src,evt) obj.focRectEvts(src,evt));
                            addlistener(focRect,'MovingROI',@(src,evt) obj.focRectEvts(src,evt));
                            obj.currFocHandle = focRect;
                        end
                        xLims = obj.ind2coord(obj.getFocDimLims(xDim),xDim);
                        yLims = obj.ind2coord(obj.getFocDimLims(yDim),yDim);
                        rectPos = [xLims(1),yLims(1),xLims(2)-xLims(1),yLims(2)-yLims(1)];
                        if ~isempty(dx)
                            rectPos = rectPos+[-dx/2,0,dx,0];
                        end
                        if ~isempty(dy)
                            rectPos = rectPos+[0,-dy/2,0,dy];
                        end
                        focRect.Position = rectPos;
                        setappdata(focRect,'xSnapPts',xs);
                        setappdata(focRect,'ySnapPts',ys);
                        setappdata(focRect,'snapMids',[1,1,1]);
                        setappdata(focRect,'freezeX',false);
                        setappdata(focRect,'freezeY',false);
                        setappdata(focRect,'initPos',rectPos);
                        focRect.Rotatable = false;
                    end
                    colormap(ax,obj.cmap);
                    xlabel(ax,obj.dimLbls(xDim));
                    ylabel(ax,obj.dimLbls(yDim));
                    ax.XLabel.ContextMenu = xCM;
                    ax.XLabel.Interactions = [];
                    ax.YLabel.ContextMenu = yCM;
                    ax.YLabel.Interactions = [];

                case 'imageStack'
                    currFoc{xDim} = ':';
                    currFoc{yDim} = ':';
                    currFoc{zDim} = ':';
                    
                    focData = obj.data(currFoc{:});
                    plotDim = 3;
                    if yDim~=zDim && xDim~=zDim
                        focData = permute(focData,[xDim,yDim,zDim,allDims(~ismember(allDims,[xDim,yDim,zDim]))]);
                    else
                        focData = permute(focData,[xDim,yDim,allDims(~ismember(allDims,[xDim,yDim]))]);
                        plotDim = 2;
                    end
                    plotData = squeeze(mean(focData,(plotDim+1):ndims(focData)));
                    switch obj.plotMode
                        case 'abs'
                            plotData = abs(plotData);
                        case 'real'
                            plotData = real(plotData);
                        case 'imag'
                            plotData = imag(plotData);
                    end
                    xs = obj.axMaps{xDim}(:);
                    ys = obj.axMaps{yDim}(:);
                    if plotDim == 2
                        zs = 1;
                    else
                        zs = obj.axMaps{zDim}(:);
                    end

                    dx = [];
                    if numel(xs)>1
                        dx = xs(2)-xs(1);
                    end
                    dy = [];
                    if numel(ys)>1
                        dy = ys(2)-ys(1);
                    end
                    dz = [];
                    if numel(zs)>1
                        dz = zs(2)-zs(1);
                    end
                    %obj.currPlotHandle = [];
                    zs_mesh = repmat(zs(:),[1,numel(ys)]);
                    ys_mesh = repmat(ys(:),[1,numel(xs)]);
                    if ~iscell(obj.currPlotHandle)
                        obj.currPlotHandle = [];
                    end
                    if ~isempty(obj.currPlotHandle)&&numel(obj.currPlotHandle)>=numel(zs)
                        clearInds = [];
                        for idx = 1:numel(zs)
                            pltHdl = obj.currPlotHandle{idx};
                            if isvalid(pltHdl)&&isa(pltHdl,'matlab.graphics.chart.primitive.Surface')
                                set(pltHdl,'XData',xs(:));
                                set(pltHdl,'YData',zs_mesh(idx,:)');
                                set(pltHdl,'ZData',ys_mesh)
                                set(pltHdl,'CData',plotData(:,:,idx)');
                            else
                                clearInds(end+1) = idx; %#ok agrow
                            end
                        end
                        obj.currPlotHandle(clearInds) = [];
                    else
                        obj.currPlotHandle = [];
                    end
    
                    if isempty(obj.currPlotHandle)
                        % if there is no attached handle, set one:
                        cla(ax);
                        focHandles = cell(numel(zs),1);
                        
                        for idx = 1:numel(zs)
                            h = surf(xs(:),zs_mesh(idx,:)',ys_mesh,plotData(:,:,idx)','EdgeAlpha',0);
                            focHandles{idx} = h;
                        end
                        obj.currPlotHandle = focHandles;
                    end
    
                    %Set up axes:
                    if dimsChgd
                        % if ismember(xDim,[2,3,4])&&ismember(yDim,[2,3,4])
                        %     %=> spatial plot
                        %     set(ax,'DataAspectRatio',[1,1,1]);
                        % else
                        %     if numel(ys)<numel(xs)
                        %         if abs(numel(ys)*dy)>eps
                        %             set(ax,'DataAspectRatio',[(numel(xs)*dx)/(numel(ys)*dy),1,1]);
                        %         else
                        %             set(ax,'DataAspectRatio',[(numel(xs)*dx),1,1]);
                        %         end
                        %     else
                        %         if abs(numel(xs)*dx)>eps
                        %             set(ax,'DataAspectRatio',[1,(numel(ys)*dy)/(numel(xs)*dx),1]);
                        %         else
                        %             set(ax,'DataAspectRatio',[1,(numel(ys)*dy),1]);
                        %         end
                        %     end
                        % end
                        % xlim([xs(1),xs(end)]);
                        ylim([ys(1),ys(end)]);
                        % zlim([zs(1),zs(end)]);
                        axis(ax,'padded');
                        set(ax,'YDir','normal');
                    end
                    colormap(ax,obj.cmap);
                    xlabel(ax,obj.dimLbls(xDim));
                    zlabel(ax,obj.dimLbls(yDim));
                    ylabel(ax,obj.dimLbls(zDim));
                    ax.XLabel.ContextMenu = xCM;
                    ax.XLabel.Interactions = [];
                    ax.YLabel.ContextMenu = zCM;
                    ax.YLabel.Interactions = [];
                    ax.ZLabel.ContextMenu = yCM;
                    ax.ZLabel.Interactions = [];
            end
            hold(ax,'off');
            %lastly: 
            obj.prevVisDims = obj.visDims;
        end

    end
end
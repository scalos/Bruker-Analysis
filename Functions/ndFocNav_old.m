function panel = ndFocNav_old(data,opts)

    arguments
        data
        opts.Parent = [] %must be uipanel
        opts.initFoc = []
        opts.dimLbls = {};
        opts.intensityLbl = 'Intensity';
        opts.axMaps = {};
        opts.cmap = parula(256);
        opts.FocChangedFcn = [];
    end
    axMaps = opts.axMaps;
    if isempty(axMaps)
        axMaps = cell(ndims(data),1);
        for ii = 1:ndims(data)
            axMaps{ii} = 1:size(data,ii);
        end
    end

    %TODO: validate Parent
    parent = opts.Parent;
    if isempty(parent)
        parent = uifigure;
    end
    initFoc = opts.initFoc;
    if isempty(initFoc)
        initFoc = repmat({':'},[1,ndims(data)]);
    end
    dimLbls = opts.dimLbls;
    if isempty(dimLbls)
        dimLbls = arrayfun(@(d) sprintf('dim %d', d), 1:ndims(data),'UniformOutput', false);
    end
    panel = uipanel('Parent',parent,'Units','normalized','Position',[0,0,1,1]);
    setappdata(panel,'FocNav_currFoc',initFoc);
    setappdata(panel,'FocNav_allData',data);
    setappdata(panel,'FocNav_xDim',2);
    setappdata(panel,'FocNav_yDim',3);
    setappdata(panel,'FocNav_zDim',0);
    setappdata(panel,'FocNav_dimLbls',dimLbls);
    setappdata(panel,'FocNav_intensityLbl',opts.intensityLbl);
    setappdata(panel,'FocNav_currFocDim',2);
    setappdata(panel,'FocNav_cmap',opts.cmap);
    setappdata(panel,'FocNav_axMaps',axMaps);
    setappdata(panel,'FocNav_FocChangedFcn',opts.FocChangedFcn)


    ax = uiaxes(panel,'Units','normalized','Position',[0.05,0.3,0.95,0.7]);
    setappdata(panel,'FocNav_mainAx',ax);
    xDimDropdown = uidropdown(panel,'Value',getappdata(panel,'FocNav_xDim'),...
                                    'Tag','xDim',...
                                    'Items',dimLbls,...
                                    'ItemsData',1:numel(dimLbls),...
                                    'ValueChangedFcn',@(src,evt) updatePlotDims(src,evt,panel),...
                                    'Position',[100,100,100,22]);
    uilabel(panel,"Text",'xDim:','Position',xDimDropdown.Position-[40,0,0,0]);
    yDimDropdown = uidropdown(panel,'Value',getappdata(panel,'FocNav_yDim'),...
                                    'Tag','yDim',...
                                    'Items',dimLbls,...
                                    'ItemsData',1:numel(dimLbls),...
                                    'ValueChangedFcn',@(src,evt) updatePlotDims(src,evt,panel),...
                                    'Position',[100,75,100,22]);
    uilabel(panel,"Text",'yDim:','Position',yDimDropdown.Position-[40,0,0,0]);
    zVal = getappdata(panel,'FocNav_zDim');
    if isempty(zVal)
        zVal = 0;
    end
    zDimDropdown = uidropdown(panel,'Value',zVal,...
                                    'Tag','zDim',...
                                    'Items',[{'None'},dimLbls(:)'],...
                                    'ItemsData',0:numel(dimLbls),...
                                    'ValueChangedFcn',@(src,evt) updatePlotDims(src,evt,panel),...
                                    'Position',[100,50,100,22]);
    uilabel(panel,"Text",'zDim:','Position',zDimDropdown.Position-[40,0,0,0]);

    currFocSetDim = getappdata(panel,'FocNav_currFocDim');
    initVals = getFocDimLims(panel,currFocSetDim);
    focDimMap = axMaps{currFocSetDim};
    dfocDim = focDimMap(2)-focDimMap(1);
    initLimits = [1,size(data,currFocSetDim)];
    focSlider = uislider(panel,'range','Position',[375,85,150,3],...
                                              'Limits',initLimits,...
                                              'Step',dfocDim,...
                                              'ValueChangedFcn',@(src,evt) focusChange(src,evt,panel),...
                                              'Value',initVals);
    setappdata(panel,'FocNav_focSlider',focSlider);
    focusDimDropdown = uidropdown(panel,'Value',currFocSetDim,...
                                        'Items',dimLbls,...
                                        'ItemsData',1:numel(dimLbls),...
                                        'ValueChangedFcn',@(src,evt) updateFocDim(src,evt,panel),...
                                        'Position',[250,75,100,22]);
    
    

    setVoxFoc = uibutton(panel,"state", ...
                               'Text','Select Voxel', ...
                               'ValueChangedFcn',@(src,evt) setVoxFocus(src,evt,panel),...
                               'Position',[250,50,100,22]);
    lbl = uilabel(panel,"Text",sprintf('Current Focus: %s',getPrettyFocus(initFoc)),'Position',[250,30,400,22]);
    setappdata(panel,'FocNav_focLbl',lbl);
    updateDisplay(panel);

    function prettyFoc = getPrettyFocus(focus)
        prettyFoc = '(';
        for idx = 1:numel(focus)
            entry = focus{idx};
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

    function updateFocus(panel,newFoc)
        setappdata(panel,'FocNav_currFoc',newFoc);
        updateFocSlider(panel);
        updateDisplay(panel);
        focUpdateFunc = getappdata(panel,'FocNav_FocChangedFcn');
        if ~isempty(focUpdateFunc)
            focUpdateFunc(panel);
        end
    end

    function setVoxFocus(src,evt,panel)
        if evt.Value == 1
            panelData = getappdata(panel);
            ax_ = panelData.FocNav_mainAx;
            currFoc = panelData.FocNav_currFoc;
            xDim = panelData.FocNav_xDim;
            yDim = panelData.FocNav_yDim;
            if isequal(xDim,yDim)
                src.Value = 0;
                return;
            end
            prevText = src.Text;
            src.Text = 'Cancel';
            try
                ax_.Toolbar.Visible = false;
                vox = drawpoint(ax_);
            catch
                src.Value = 0;
                src.Text = prevText;
                return;
            end
            src.Value = 0;
            src.Text = prevText;
            ax_.Toolbar.Visible = true;
            if isempty(vox.Position)
                return;
            end
            focVox = [round(vox.Position(1)),round(vox.Position(2))];

            currFoc{xDim} = coord2ind(panel,focVox(1),xDim);
            currFoc{yDim} = coord2ind(panel,focVox(2),yDim);
            src.Value = 0;
            src.Text = prevText;
            updateFocus(panel,currFoc);
        end
    end

    function dimFocLims = getFocDimLims(panel,dim)
        panelData = getappdata(panel);
        currFoc = panelData.FocNav_currFoc;
        allData = panelData.FocNav_allData;
        dimExpression = currFoc(dim);
        fullRange = 1:size(allData,dim);
        dimFocRange = fullRange(dimExpression{:});
        dimFocLims = [dimFocRange(1),dimFocRange(end)];
    end

    function updateFocSlider(panel)
        panelData = getappdata(panel);
        currFoc = panelData.FocNav_currFoc;
        currFocDim = panelData.FocNav_currFocDim;
        focMap = panelData.FocNav_axMaps{currFocDim};

        
        slider = panelData.FocNav_focSlider;
        foc = currFoc{currFocDim};
        allData = panelData.FocNav_allData;
        if size(allData,currFocDim)>1
            slider.Visible = 'on';
            dfocDim_ = focMap(2)-focMap(1);
            slider.Step = dfocDim_;
            slider.Limits = [1,size(allData,currFocDim)];
        else
            slider.Visible = 'off';
        end
        if strcmp(foc,':')
            slider.Value = slider.Limits;
        else
            slider.Value = [foc(1),foc(end)];
        end
    end

    function focusChange(src,~,panel)
        panelData = getappdata(panel);
        currFoc = panelData.FocNav_currFoc;
        currFocDim = panelData.FocNav_currFocDim;
        newFocRange = src.Value;
        fullFocRange = src.Limits;
        
        if isequal(newFocRange,fullFocRange)
            currFoc{currFocDim} = ':';
        else
            currFoc{currFocDim} = coord2ind(panel,newFocRange(1):newFocRange(end),currFocDim);
        end
        updateFocus(panel,currFoc);
    end

    function updateFocDim(src,~,panel)
        newValIdx = src.ValueIndex;
        dimData = src.ItemsData;
        newDim = dimData(newValIdx);
        setappdata(panel,'FocNav_currFocDim',newDim);
        updateFocSlider(panel);
    end

    function updatePlotDims(src,~,panel)
        newValIdx = src.ValueIndex;
        dimData = src.ItemsData;
        newDim = dimData(newValIdx);
        switch src.Tag
            case 'xDim'
                setappdata(panel,'FocNav_xDim',newDim);
            case 'yDim'
                setappdata(panel,'FocNav_yDim',newDim);
            case 'zDim'
                setappdata(panel,'FocNav_zDim',newDim);
        end
        updateDisplay(panel);
    end

    function [V,F] = getPatchData(xLim,yLim,zLim)
        x0 = xLim(1);
        dx = xLim(2)-xLim(1);
        y0 = yLim(1);
        dy = yLim(2)-yLim(1);
        z0 = zLim(1);
        dz = zLim(2)-zLim(1);
        
        V = [
            x0      y0      z0
            x0+dx   y0      z0
            x0+dx   y0+dy   z0
            x0      y0+dy   z0
            x0      y0      z0+dz
            x0+dx   y0      z0+dz
            x0+dx   y0+dy   z0+dz
            x0      y0+dy   z0+dz
        ];
        
        F = [
            1 2 3 4
            5 6 7 8
            1 2 6 5
            2 3 7 6
            3 4 8 7
            4 1 5 8
        ];

    end

    function coords = ind2coord(panel,inds,dim)
        panelData = getappdata(panel);
        axMaps_ = panelData.FocNav_axMaps;
        coordMap = axMaps_{dim};
        coords = reshape(coordMap(inds(:)),size(inds));
    end

    function inds = coord2ind(panel,coords,dim)
        panelData = getappdata(panel);
        axMaps_ = panelData.FocNav_axMaps;
        coordMap = axMaps_{dim};
        inds = zeros(size(coords));
        inds = inds(:);
        for idx = 1:numel(coords(:))
            [~,minInd] = min(abs(coordMap-coords(idx)));
            inds(idx) = minInd;
        end
        inds = reshape(sort(inds),size(coords));
    end
    
    function updateDisplay(panel)
        panelData = getappdata(panel);
        ax_ = panelData.FocNav_mainAx;
        cla(ax_);
        currFoc = panelData.FocNav_currFoc;
        focLbl = panelData.FocNav_focLbl;
        focLbl.Text = sprintf('Current Focus: %s',getPrettyFocus(currFoc));
        xDim = panelData.FocNav_xDim;
        yDim = panelData.FocNav_yDim;
        zDim = panelData.FocNav_zDim;
        allData = panelData.FocNav_allData;
        cmap = panelData.FocNav_cmap;
        dimLbls_ = panelData.FocNav_dimLbls;
        axMaps_ = panelData.FocNav_axMaps;
        intensityLbl = panelData.FocNav_intensityLbl;
        if isempty(xDim)||isempty(yDim)
            error('ERROR: x,y dimensions cannot be empty!')
        end
        allDims = 1:ndims(allData);
        if zDim==0
            if xDim == yDim
                %1D plot
                currFoc{xDim} = ':';
                focData = allData(currFoc{:});
                plotData = squeeze(abs(mean(focData,allDims(allDims~=xDim))));
                if ~isscalar(plotData)
                    focLims = ind2coord(panel,getFocDimLims(panel,xDim),xDim);
                    plot(ax_,axMaps_{xDim},plotData);
                    xline(ax_,focLims(1));
                    xline(ax_,focLims(2));
                    xlabel(ax_,dimLbls_(xDim));
                    ylabel(ax_,intensityLbl);
                    axis(ax_,'normal');
                    set(ax_,'YDir','normal');
                else
                    cla(ax_);
                end
            else
                %2D plot
                currFoc{xDim} = ':';
                currFoc{yDim} = ':';
                
                focData = allData(currFoc{:});
                focData = permute(focData,[xDim,yDim,allDims(~ismember(allDims,[xDim,yDim]))]);
                plotData = squeeze(abs(mean(focData,3:ndims(focData))));
                % xs = repmat(axMaps_{xDim}(:),[1,numel(axMaps_{yDim})]);
                % ys = repmat(axMaps_{yDim}(:),[1,numel(axMaps_{xDim})]);
                xs = axMaps_{xDim}(:);
                ys = axMaps_{yDim}(:);
                imagesc(ax_,[xs(1),xs(end)],[ys(1),ys(end)],plotData');
                xLims = ind2coord(panel,getFocDimLims(panel,xDim),xDim);
                yLims = ind2coord(panel,getFocDimLims(panel,yDim),yDim);
                if numel(xs)>1
                    dx = xs(2)-xs(1);
                else
                    dx = 0;
                end
                if numel(ys)>1
                    dy = ys(2)-ys(1);
                else
                    dy = 0;
                end
                
                rectLims = [xLims(1),yLims(1),xLims(2)-xLims(1),yLims(2)-yLims(1)]+[-dx/2,-dy/2,dx,dy];
                rectangle(ax_,"FaceAlpha",0,"EdgeColor",'r','Position',rectLims);
                colormap(ax_,cmap);
                xlabel(ax_,dimLbls_(xDim));
                ylabel(ax_,dimLbls_(yDim));
                axis(ax_,'tight');
                %set(ax_,'DataAspectRatio',[1,1,1]);
                if ismember(xDim,[2,3,4])&&ismember(yDim,[2,3,4])
                    %=> spatial plot
                    set(ax_,'DataAspectRatio',[1,1,1]);
                else
                    if numel(ys)<numel(xs)
                        set(ax_,'DataAspectRatio',[(numel(xs)*dx)/(numel(ys)*dy),1,1]);
                    else
                        set(ax_,'DataAspectRatio',[1,(numel(ys)*dy)/(numel(xs)*dx),1]);
                    end
                    
                    
                end
                
                set(ax_,'YDir','normal');
            end
        else
            %3D plot

        end
        

    end

end
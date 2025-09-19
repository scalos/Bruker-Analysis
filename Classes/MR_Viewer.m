classdef MR_Viewer<handle

    properties
        data
        axMaps
        linkedPlots = {};
        prefs
    end

    properties(SetObservable)
        focus
    end

    events
        showFocChange
    end
    methods (Access = private)
        function handlePropEvents(obj,src,evnt)
            switch evnt.EventName
                case 'PostSet'
                    switch src.Name
                        case 'focus'
                            notify(obj,'showFocChange')
                    end
            end
        end
    end

    methods
        function obj = MR_Viewer(data,axMaps,focus,prefs)
            arguments
                data (:,:,:,:,:) %(spectral,x,y,z,repitions)
                axMaps = {};
                focus = [];
                prefs.layout = [];
            end
            if isempty(focus)
                focus = ones(size(data));
            end

            if numel(size(axMaps))<=numel(size(data))
                axMaps_ = {1:size(data,1),...
                           1:size(data,2),...
                           1:size(data,3),...
                           1:size(data,4),...
                           1:size(data,5)};
                for idx = 1:numel(axMaps)
                    axMaps_{idx} = axMaps{idx}(:);
                end
            end
            % if ~all(size(axMaps_)==size(data))
            %     error('Axes mapping matrix size must match data dimensions!');
            % end
            
            obj.prefs = prefs;
            obj.data = data;
            obj.axMaps = axMaps_;
            obj.focus = focus;
            addlistener(obj,'showFocChange',@updatePlots);
            addlistener(obj,'focus','PostSet',@obj.handlePropEvents);
        end

        function TF = isValidFocus(obj,focus_)
            TF = false;
            if all(size(obj.focus)==size(focus_))&&...
               all(ismember(focus_(:), [0, 1]))
                TF = true;
            end
        end

        function TF = isValidDims(obj,dims)
            TF = false;
            if numel(dims)<=numel(size(obj.data))&&...
               all(dims<=numel(size(obj.data)))
                TF = true;
            end
        end

        function data_ = getFocusData(obj,data_,focus_,dims)
            arguments
                obj
                data_
                focus_
                dims = [];
            end
            data_ = data_.*focus_;
            if ~isempty(dims)&&obj.isValidDims(dims)
                for dim = 1:numel(size(obj.data))
                    if ~any(dim==dims)
                        data_ = sum(data_,dim);
                    end
                end

            end
        end

        function TF = isValidDataSize(~,type,shape)
            TF = false;
            switch type
                case {'line','spiral'}
                    if sum(shape~=1)==1
                        TF = true;
                    end
                case {'line_stack','image','surf'}
                    if sum(shape~=1)==2
                        TF = true;
                    end
                case 'volume'
                    if sum(shape~=1)==3
                        TF = true;
                    end
            end
        end

        function dispFoc(obj)
            summary = summarize5DLogical(obj.focus);
            disp(['([' strjoin(summary', '],[') '])']);
        end

        function clearFocus(obj)
            obj.focus = zeros(size(obj.data));
        end

        function allFocus(obj)
            obj.focus = ones(size(obj.data));
        end

        function adoptFocRegion(obj,region)
            arguments
                obj
                region (:,:,:,:,:)
            end
            newFoc = obj.focus-region;
            newFoc(newFoc<0) = 0;
            newFoc(newFoc>1) = 1;
            obj.focus = newFoc;
        end

        function das = DAs1D(~,xbds,ybds,xPos)
            xbds = sort(xbds);
            ybds = sort(ybds);
            xPos = sort(xPos);
            if isscalar(xPos)
                das = [xbds(1),ybds(1),xbds(2)-xbds(1),ybds(2)-ybds(1)+1];
            else
                nX = numel(xPos);
                das = zeros(nX,4);
                das(1,:) = [xbds(1),ybds(1),xPos(2)-xbds(1),ybds(2)-ybds(1)+1];
                for idx = 2:numel(xPos)-2
                    das(idx,:) = [xPos(idx-1),ybds(1),xPos(idx+1)-xPos(idx-1),ybds(2)-ybds(1)+1];
                end
                das(nX,:) = [xPos(nX-1),ybds(1),xbds(2)-xPos(nX-1),ybds(2)-ybds(1)+1];
            end
        end

        function eRange = embedRange(obj,range,dim)
            eRange = ones(size(obj.data));
            switch dim
                case 1
                    eRange(range,:,:,:,:) = 0;
                case 2
                    eRange(:,range,:,:,:) = 0;
                case 3
                    eRange(:,:,range,:,:) = 0;
                case 4
                    eRange(:,:,:,range,:) = 0;
                case 5
                    eRange(:,:,:,:,range) = 0;
            end
        end

        function roiEvents(obj,src,evt)
                switch class(src)
                    case 'images.roi.Line'
                        roiInfo = get(src,'UserData');
                        personalInd = roiInfo.thisInd;
                        allLines = roiInfo.allROIs;
                        allInds = roiInfo.allInds;
                        dim = roiInfo.dim;
                        xMap = obj.axMaps{dim};
                        yBds = roiInfo.yBds;
                        xBds = [xMap(1),xMap(end)];
                        [~,newInd] = min(abs(src.Position(1)-xMap));
                        allInds(personalInd) = newInd;
                        xregions_ = xMap(allInds);
                        newDAs = obj.DAs1D(xBds,yBds,xregions_);
                        switch evt.EventName
                            case 'MovingROI'
                                
                                
                            case 'ROIMoved'
                                for ii = 1:numel(allLines)
                                    line_ = allLines{ii};
                                    set(line_,'DrawingArea',newDAs(ii,:));
                                    lineInfo = get(line_,'UserData');
                                    lineInfo.allInds = allInds;
                                    lineInfo.allROIs = allLines;
                                    set(line_,'UserData',lineInfo);
                                end
                                newFoc = obj.embedRange(allInds(1):allInds(2),dim);
                                obj.adoptFocRegion(newFoc);
                        end
                end
            end

        function showFocus(obj,ax,type,dims)
            arguments
                obj 
                ax 
                type 
                dims {mustBeInteger}
            end
            
            [~,ranges] = summarize5DLogical(obj.focus);
            xMap = obj.axMaps{dims};
            yBds = [ax.YTick(1),ax.YTick(end)];
            xBds = [xMap(1),xMap(end)];
            switch type
                case 'line'
                    regions = ranges{dims};
                    
                    xregions = xMap(regions(:));
                    DAS = obj.DAs1D(xBds,yBds,xregions);
                    lines = cell(numel(xregions),1);
                    for idx = 1:numel(xregions)
                        xVal = xregions(idx);
                        pos = [xVal,ax.YTick(1);...
                               xVal,ax.YTick(end)];
                        
                        line = drawline(ax,...
                                        'Position',pos, ...
                                        'InteractionsAllowed','translate', ...
                                        'DrawingArea',DAS(idx,:));
                        addlistener(line,'MovingROI',@obj.roiEvents);
                        addlistener(line,'ROIMoved',@obj.roiEvents);
                        lines{idx} = line;
                    end
                    for lInd = 1:numel(lines)
                        line = lines{lInd};
                        info = struct('dim',dims, ...
                                      'yBds',yBds, ...
                                      'thisInd',lInd, ...
                                      'allInds',regions);
                        info.allROIs = lines;
                        set(line,'UserData',info);
                    end
            end
            
        end

        function updatePlots(obj,~)
            obj.linkedPlots = obj.linkedPlots(~cellfun(@isempty,obj.linkedPlots));
            for lInd = 1:numel(obj.linkedPlots)
                params = obj.linkedPlots{lInd};
                type = params.type;
                dims = params.dims;
                focus_ = obj.focus;
                prefs_ = params.prefs;
                if isvalid(prefs_.ax)
                    obj.showPlot(type,dims,focus_,'ax',prefs_.ax,...
                                                  'mode',prefs_.mode,...
                                                  'linkPlot',false,...
                                                  'showFoc',prefs_.showFoc);
                else
                    obj.linkedPlots{lInd} = [];
                end
            end
            obj.linkedPlots = obj.linkedPlots(~cellfun(@isempty,obj.linkedPlots));

        end


        function showPlot(obj,type,dims,focus_,prefs)
            arguments
                obj
                type {mustBeMember(type,{'line',...
                                 'line_stack',...
                                 'image',...
                                 'surf',...
                                 'volume',...
                                 'spiral'})}
                dims;
                focus_ = [];
                prefs.ax = axes(Parent=figure(Visible=false),Visible=false);
                prefs.mode {mustBeMember(prefs.mode,{'abs','real','imag'})} = 'abs'
                prefs.showFoc logical = false;
                prefs.linkPlot logical = true;
            end
            if isempty(focus_)
                focus_ = obj.focus;
            elseif ~obj.isValidFocus(focus_)
                error('ERROR: Invalid focus!')
            end
            data_ = squeeze(obj.getFocusData(obj.data,focus_,dims)); %#ok<NASGU>
            data_ = eval(sprintf('%s(data_)',prefs.mode));
            axMaps_ = obj.axMaps;
            if isvalid(prefs.ax)
                ax = prefs.ax;
            else
                ax = axes(Parent=figure(Visible=false),Visible=false);
            end
            if obj.isValidDataSize(type,size(data_))
                switch type
                    case 'line'
                        if ~isempty(axMaps_{dims(1)})
                            plot(ax,axMaps_{dims(1)},data_);
                        else
                            plot(ax,data_);
                        end
                    case 'spiral'
                        if ~isempty(axMaps_{dims(1)})
                            plot3(ax,axMaps_{dims(1)},real(data_),imag(data_));
                        else
                            plot3(ax,1:numel(data_),real(data_),imag(data_));
                        end
                    case 'image'
                        imagesc(ax,axMaps_{dims(1)},axMaps_{dims(2)},data_');
                        colormap(ax,'parula');
                        axis(ax,'on');
                        axis(ax,"image");
                        set(ax,'XTick',[],'YTick',[])
                        axis(ax,'tight');
                    case 'surf'
                        surf(ax,axMaps_{dims(1)},axMaps_{dims(2)},data_');
                        colormap(ax,'parula');
                        axis(ax,'on');
                        set(ax,'XTick',[],'YTick',[])
                        axis(ax,'tight');
                    case 'line_stack'
                        xMap = axMaps_{dims(1)};
                        yMap = axMaps_{dims(2)};
                        if isempty(xMap)
                            xMap = 1:size(data_,1);
                        end
                        if isempty(yMap)
                            yMap = 1:size(data_,2);
                        end
                        [X,Y] = meshgrid(xMap,yMap);
                        waterfall(ax,X,Y,data_');
                    case 'volume'
                        volshow(data_,'Colormap',parula(numel(data_)));
                        delete(ax);

                end
            else
                error('Data size (%s) does not match plot type (%s)',mat2str(dims),type);
            end
            if isvalid(ax)
                if prefs.showFoc
                    obj.showFocus(ax,type,dims);
                end
                if prefs.linkPlot
                    plotParams = struct('type',type,...
                                        'dims',dims,...
                                        'focus',focus_,...
                                        'prefs',prefs);
                    obj.linkedPlots{end+1} = plotParams;
                end
                set(ax,'Visible',true);
                set(ax.Parent,'Visible',true);
            end
        end
    end
end
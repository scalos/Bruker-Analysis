classdef ImageRecon<handle
    
    properties
        base = struct;
        layers;
        dispAx;
        cbAx;
        rotAng = 0;
        prefs = struct('rotationInterpMethod','bilinear', ...
                       'colorBar',struct('visible',false,...
                                         'targInd',1,...
                                         'nTicks',5,...
                                         'tickLoc','right',...
                                         'tickMargin',0.2,...
                                         'hMargin',0.03,...
                                         'sigFigs',2), ...
                       'grid',struct('visible',false,...
                                     'size',[],...
                                     'visRows',[],...
                                     'visCols',[],...
                                     'innerRGB',[1,1,1],...
                                     'outerRGB',[1,1,1],...
                                     'innerLW',2,...
                                     'outerLW',3 ...
                                     ),...
                       'fit_to_frame',true);
            
        masks = {};
        
    end

    methods (Access = private)

        function newData = globalTforms(obj,data)
            arguments
                obj
                data
            end
            
            newData = imrotate(data,obj.rotAng,obj.prefs.rotationInterpMethod,'crop');
        end
    end

    methods
        function obj = ImageRecon(baseData)
            arguments
                baseData (:,:,:) {mustBeNumeric};
            end
            %Base is 3d matrix (in most cases this will be T1 Flash or T2 Rare)
            %Dimensions: x,y,nReps
            obj.setBase(baseData);
        end

        function drawMask(obj,type)
            arguments
                obj 
                type {mustBeMember(type,{'freehand','ellipse'})}
            end

            
                

            obj.show;
            working = true;
            disp('Draw ROI: ');
            roiLoc = [];
            switch type
                case 'freehand'
                    roi = drawpolygon(obj.dispAx);
                    roiLoc = roi.Position;
                case 'ellipse'
                    roi = drawellipse(obj.dispAx);
                    roiLoc = [roi.Center,roi.SemiAxes,roi.RotationAngle];
            end
            baseData = squeeze(obj.base.data(:,:,1));
            if ~obj.base.tPose
                baseData = baseData';
            end
            baseData = obj.globalTforms(baseData);
            maskSize = size(baseData);
            newMask = createMask(roi,maskSize(1),maskSize(2))';
            newMask = obj.globalTforms(newMask);
            roiLocs = {roiLoc};
            roiSigns = 1;
            maskLayers = newMask;
            saved = false;
            layerInd = obj.addLayer(zeros(maskSize),visible=false,solidRGB=[1,0,0]);
            function totalMask = getTotalMask(layers)
                totalMask = layers(:,:,1);
                for ii = 1:size(layers,3)-1
                    totalMask = totalMask+layers(:,:,ii+1);
                    totalMask(totalMask<0) = 0;
                    totalMask(totalMask>1) = 1;
                end
            end
            while working
                totalMask = getTotalMask(maskLayers);
                obj.layers{layerInd}.data = totalMask;
                obj.layers{layerInd}.visible = true;
                obj.show;
                res = input('add/sub/adjust/blink/apply: ','s');
                switch res
                    case 'blink'
                        obj.blinkLayer(layerInd);
                    case 'add'
                        disp('Draw ROI: ');
                        switch type
                            case 'freehand'
                                addROI = drawpolygon(obj.dispAx,'Color','g');
                                roiLocs{end+1} = addROI.Position; %#ok<AGROW>
                            case 'ellipse'
                                addROI = drawellipse(obj.dispAx,'Color','g');
                                roiLocs{end+1} = [addROI.Center,addROI.SemiAxes,addROI.RotationAngle]; %#ok<AGROW>
                        end
                        roiSigns(end+1) = 1; %#ok<AGROW>
                        addMask = createMask(addROI,maskSize(1),maskSize(2))';
                        addMask = obj.globalTforms(addMask);
                        maskLayers = cat(3,maskLayers,addMask);
                    case 'sub'
                        disp('Draw ROI: ');
                        switch type
                            case 'freehand'
                                subROI = drawpolygon(obj.dispAx,'Color','r');
                                roiLocs{end+1} = subROI.Position; %#ok<AGROW>
                            case 'ellipse'
                                subROI = drawellipse(obj.dispAx,'Color','r');
                                roiLocs{end+1} = [subROI.Center,subROI.SemiAxes,subROI.RotationAngle]; %#ok<AGROW>
                        end
                        roiSigns(end+1) = -1; %#ok<AGROW>
                        subMask = createMask(subROI,maskSize(1),maskSize(2))';
                        subMask = obj.globalTforms(subMask);
                        subMask = subMask.*-1;
                        maskLayers = cat(3,maskLayers,subMask);

                    case 'adjust'
                        adjusting = true;
                        rois = cell(size(roiLocs));
                        for idx = (1:length(rois))
                            if roiSigns(idx)>0
                                color = 'g';
                            else
                                color = 'r';
                            end
                                switch type
                                    case 'freehand'
                                        rois{idx} = images.roi.Polygon(obj.dispAx, ...
                                            Position=roiLocs{idx}, ...
                                            Color=color);
                                    case 'ellipse'
                                        roi_center = roiLocs{idx}(1:2);
                                        roi_semi = roiLocs{idx}(3:4);
                                        roi_rotAng = roiLocs{idx}(5);
                                        rois{idx} = images.roi.Ellipse(obj.dispAx, ...
                                            Center=roi_center,SemiAxes=roi_semi, ...
                                            RotationAngle=roi_rotAng,Color=color);
                                end
                        end
                        while adjusting
                            s = input('update/blink/cancel/apply: ','s');
                            switch s
                                case 'cancel'
                                    adjusting = false;
                                case 'esc'
                                    adjusting = false;
                                    working = false;
                                case 'blink'
                                    delInds = [];
                                    for idx = (1:length(rois))
                                        if isvalid(rois{idx})
                                            roi = rois{idx};
                                            switch type
                                                case 'freehand'
                                                    roiLocs{idx} = rois{idx}.Position;
                                                case 'ellipse'
                                                    roiLocs{idx} = [roi.Center,roi.SemiAxes,roi.RotationAngle];
                                            end
                                            mask_ = createMask(rois{idx},maskSize(1),maskSize(2))';
                                            mask_ = obj.globalTforms(mask_);
                                            mask_ = mask_.*max(1,(roiSigns(idx)*sum(roiSigns==-roiSigns(idx))));
                                            maskLayers(:,:,idx) = mask_;
                                        else
                                            delInds(end+1) = idx;
                                        end
                                    end
                                    for idx = (1:length(delInds))
                                        delInd = delInds(idx);
                                        roiLocs(delInd) = [];
                                        roiSigns(delInd) = [];
                                        maskLayers(:,:,delInd) = [];
                                    end
                                    totalMask = getTotalMask(maskLayers);
                                    obj.layers{layerInd}.data = totalMask;
                                    obj.blinkLayer(layerInd);
                                    rois = cell(size(roiLocs));
                                    for idx = (1:length(rois))
                                        if roiSigns(idx)>0
                                            color = 'g';
                                        else
                                            color = 'r';
                                        end
                                            switch type
                                                case 'freehand'
                                                    rois{idx} = images.roi.Polygon(obj.dispAx, ...
                                                        Position=roiLocs{idx}, ...
                                                        Color=color);
                                                case 'ellipse'
                                                    roi_center = roiLocs{idx}(1:2);
                                                    roi_semi = roiLocs{idx}(3:4);
                                                    roi_rotAng = roiLocs{idx}(5);
                                                    rois{idx} = images.roi.Ellipse(obj.dispAx, ...
                                                        Center=roi_center,SemiAxes=roi_semi, ...
                                                        RotationAngle=roi_rotAng,Color=color);
                                            end
                                    end
                                case 'update'
                                    delInds = [];
                                    for idx = (1:length(rois))
                                        if isvalid(rois{idx})
                                            roi = rois{idx};
                                            switch type
                                                case 'freehand'
                                                    roiLocs{idx} = rois{idx}.Position;
                                                case 'ellipse'
                                                    roiLocs{idx} = [roi.Center,roi.SemiAxes,roi.RotationAngle];
                                            end
                                            mask_ = createMask(rois{idx},maskSize(1),maskSize(2))';
                                            mask_ = obj.globalTforms(mask_);
                                            mask_ = mask_.*roiSigns(idx);
                                            maskLayers(:,:,idx) = mask_;
                                        else
                                            delInds(end+1) = idx;
                                        end
                                    end
                                    for idx = (1:length(delInds))
                                        delInd = delInds(idx);
                                        roiLocs(delInd) = [];
                                        roiSigns(delInd) = [];
                                        maskLayers(:,:,delInd) = [];
                                    end
                                    totalMask = getTotalMask(maskLayers);
                                    obj.layers{layerInd}.data = totalMask;
                                    rois = cell(size(roiLocs));
                                    for idx = (1:length(rois))
                                        if roiSigns(idx)>0
                                            color = 'g';
                                        else
                                            color = 'r';
                                        end
                                            switch type
                                                case 'freehand'
                                                    rois{idx} = images.roi.Polygon(obj.dispAx, ...
                                                        Position=roiLocs{idx}, ...
                                                        Color=color);
                                                case 'ellipse'
                                                    roi_center = roiLocs{idx}(1:2);
                                                    roi_semi = roiLocs{idx}(3:4);
                                                    roi_rotAng = roiLocs{idx}(5);
                                                    rois{idx} = images.roi.Ellipse(obj.dispAx, ...
                                                        Center=roi_center,SemiAxes=roi_semi, ...
                                                        RotationAngle=roi_rotAng,Color=color);
                                            end
                                    end
                                case 'apply'
                                    delInds = [];
                                    adjusting = false;
                                    for idx = (1:length(rois))
                                        if isvalid(rois{idx})
                                            roi = rois{idx};
                                            switch type
                                                case 'freehand'
                                                    roiLocs{idx} = rois{idx}.Position;
                                                case 'ellipse'
                                                    roiLocs{idx} = [roi.Center,roi.SemiAxes,roi.RotationAngle];
                                            end
                                            mask_ = createMask(rois{idx},maskSize(1),maskSize(2))';
                                            mask_ = obj.globalTforms(mask_);
                                            mask_ = mask_.*roiSigns(idx);
                                            maskLayers(:,:,idx) = mask_;
                                        else
                                            delInds(end+1) = idx;
                                        end
                                    end
                                    for idx = (1:length(delInds))
                                        delInd = delInds(idx);
                                        roiLocs(delInd) = [];
                                        roiSigns(delInd) = [];
                                        maskLayers(:,:,delInd) = [];
                                    end
                                otherwise
                                    disp('Unrecognized Response!');
                            end
                        end

                    case 'esc'
                        working = false;
                    case 'apply'
                        totalMask = getTotalMask(maskLayers);
                        obj.masks{end+1} = totalMask;
                        working = false;
                        saved = true;
                    otherwise
                        disp('Unrecognized Response!');
                end
            end
            if ~saved
                deciding = true;
                while deciding
                   totalMask = getTotalMask(maskLayers);
                   obj.layers{layerInd}.data = totalMask;
                   res = input('Would you like to save the current mask? (y/n) ','s');
                   switch res
                       case 'y'
                           deciding = false;
                           obj.masks{end+1} = totalMask;
                       case 'n'
                           deciding = false;
                       otherwise
                           disp('Unrecognized Response!');
                   end
                end
            end
            obj.layers(layerInd) = [];
            obj.show;
        end

        function roiInfo = roiAnalysis(obj,roiMasks,targetInd,opts)
            arguments
                 obj
                 roiMasks
                 %use targetInd = 0 for base image;
                 targetInd {mustBeInteger,mustBeGreaterThanOrEqual(targetInd,0)};
                 opts.roi_RGB = [1,0,0];
                 opts.roi_Trans = 0.2;
                 opts.roiBd = true;
                 opts.roiBd_style = '-';
                 opts.roiBd_incVis = false;
                 opts.showInfo = true;
                 opts.lbl_RGB = [1,1,1];
                 opts.lbl_Shift = [0,0];
                 opts.lbl_fontSize = 12;
            end
            if ~iscell(roiMasks)
                roiMasks = {roiMasks};
            end
            obj.purgeLayers;
            if targetInd>numel(obj.layers)
                error('Target Index (%d) is out of range for %d layers',targetInd,numel(obj.layers));
            end
            obj.show;
            roiInfo = cell(length(roiMasks),1);
            for idx = 1:numel(roiMasks)
                roiMask =obj.globalTforms(roiMasks{idx}');
                maskCenter = regionprops(roiMask,'Centroid');
                hold(obj.dispAx,'on');
                rgb = opts.roi_RGB;
                rgbMap = cat(2,cat(2,rgb(1).*ones(length(roiMask),1), ...
                                     rgb(2).*ones(length(roiMask),1)), ...
                                     rgb(3).*ones(length(roiMask),1));
                roiRGB = ind2rgb(uint8(roiMask),rgbMap);
                img = imagesc(obj.dispAx,roiRGB);
                imAlphaData = zeros(size(roiMask)); % transparency mask
                imAlphaData(roiMask(:) > (0)) = opts.roi_Trans;
                set(img,'AlphaData',imAlphaData);
                set(img, 'AlphaDataMapping', 'none');
                
                if opts.roiBd
                    visboundaries(obj.dispAx, ...
                    bwboundaries(roiMask,'TraceStyle',"pixeledge"),...
                                         'Color',opts.roi_RGB,...
                                         'LineStyle',opts.roiBd_style, ...
                                         'EnhanceVisibility',opts.roiBd_incVis);
                end

                hold(obj.dispAx,'off');
                roiInfo{idx} = struct;
                if targetInd == 0
                    rep = obj.base.viewRep;
                    roiData = mask(obj.base.data(:,:,rep),roiMask);
                else
                    rep = obj.layers{targetInd}.viewRep;
                    roiData = mask(obj.layers{targetInd}.data(:,:,rep),roiMask);
                end
                roiInfo{idx}.sum = abs(sum(sum(roiData)));
                roiInfo{idx}.area = abs(regionprops(roiMask','Area').Area);
                roiInfo{idx}.mean = roiInfo{idx}.sum/roiInfo{idx}.area;
                if opts.showInfo
                    text(obj.dispAx,maskCenter.Centroid(1)+opts.lbl_Shift(1), ...
                                    maskCenter.Centroid(2)+opts.lbl_Shift(2), ...
                                    formattedDisplayText(roiInfo{idx}), ...
                                    "Color",opts.lbl_RGB, ...
                                    "FontSize",opts.lbl_fontSize);
                end
            end
        end

        function setBase(obj,baseData)
            obj.base.data = baseData;
            obj.base.viewRep = 1;
            obj.base.visible = true;
            obj.base.mask = [];
            obj.base.shift = [0,0];
            obj.base.tPose = false;
            [~,~,obj.base.nReps] = size(baseData);
        end
        
        function adjustBase(obj)
            adjusting = true;
            obj.show;
            while adjusting
                shift = input(sprintf('\nFrame (i,k) = %d\nShift (wasd): [U/D,L/R]=[%d,%d] ->', ...
                    obj.base.viewRep,obj.base.shift(1),obj.base.shift(2)),'s');
                switch shift
                    case 'esc'
                        adjusting = false;
                    case 'reset'
                        obj.base.shift = [0,0];
                    case 'a'
                        obj.base.shift(1) = obj.base.shift(1)-1;
                    case 'd'
                        obj.base.shift(1) = obj.base.shift(1)+1;
                    case 'w'
                        obj.base.shift(2) = obj.base.shift(2)-1;
                    case 's'
                        obj.base.shift(2) = obj.base.shift(2)+1;
                    case 'i'
                        if obj.base.viewRep+1<=obj.base.nReps
                            obj.base.viewRep = obj.base.viewRep+1;
                        end
                    case 'k'
                        if obj.base.viewRep>1
                            obj.base.viewRep = obj.base.viewRep-1;
                        end
                end
                obj.show;
                drawnow;
            end
        end

        function layerInd = addLayer(obj,layerData,opts)
            arguments
                obj 
                layerData (:,:,:) {mustBeNumeric};
                opts.visible logical = true;
                opts.viewRep {mustBeInteger,mustBeGreaterThan(opts.viewRep,0)} = 1;
                opts.trans {mustBeNumeric,...
                            mustBeGreaterThanOrEqual(opts.trans,0),...
                            mustBeLessThanOrEqual(opts.trans,1)} = 0.3;
                opts.thresh {mustBeNumeric,...
                            mustBeGreaterThanOrEqual(opts.thresh,0),...
                            mustBeLessThanOrEqual(opts.thresh,1)} = 0.1;
                opts.mask (:,:) logical = [];
                opts.tPose logical = false;
                opts.solidRGB {mustBeNumeric} = [];
                opts.name = [];
            end
            obj.purgeLayers;
            
            %Layer is 3d matrix (x,y,nReps)
            layerData = squeeze(layerData);
            newLayer = struct;
            newLayer.name = opts.name;
            newLayer.data = layerData;
            newLayer.visible = opts.visible;
            [~,~,newLayer.nReps] = size(layerData);
            newLayer.viewRep = opts.viewRep;
            newLayer.trans = opts.trans;
            newLayer.thresh = opts.thresh;
            newLayer.mask = opts.mask;
            newLayer.tPose = opts.tPose;
            newLayer.solidRGB = opts.solidRGB;
            newLayer.normVal = [];
            obj.layers{end+1} = newLayer;
            layerInd = numel(obj.layers);
            obj.show;
        end

        function purgeLayers(obj)
            %Honestly this isn't necessary
            delInds = [];
            for idx = 1:numel(obj.layers)
                if isempty(obj.layers{idx})
                    delInds(end+1) = idx;
                end
            end
            for idx = 1:numel(delInds)
                layerInd = delInds(idx);
                obj.layers(layerInd) = [];
            end
        end

        function [tileAxes,panels] = tileLayers(obj,m,n,inds,opts)
            arguments
                obj
                m {mustBeInteger};
                n {mustBeInteger};
                inds {mustBeInteger} = [];
                opts.spacing = 0;
                opts.showNames = true;
                opts.startInd {mustBeInteger} = 1;
                opts.match_dispAx_sizes = true;
                opts.allCbars = true;
                opts.parent = [];
                opts.zoom = [];
                opts.panel_hSqueeze = 0;
            end
            if isempty(inds)
                inds = 1:numel(obj.layers);
            end
            old_prefs = obj.prefs;
            obj.prefs.fit_to_frame = true;
            if isempty(opts.parent)
                parent = figure;
            else
                parent = opts.parent;
            end
            ax = obj.dispAx;
            cax = obj.cbAx;
            visLayers = obj.whosVis;
            tileAxes = cell(m*n,1);
            axPositions = ones(m*n,4);
            panels = cell(m*n,1);
            
            for idx = 1:numel(inds)
                tileIdx = idx+opts.startInd-1;
                obj.setVis(inds(idx));
                if opts.allCbars
                    obj.prefs.colorBar.targInd = inds(idx);
                end
                panel = uipanel('Position',getGridPos(m,n,tileIdx,opts.spacing), ...
                    'BorderType', 'none','Parent',parent,"BackgroundColor",'white');
                col = mod(idx - 1, n) + 1;
                panel.Position(1) = panel.Position(1)-opts.panel_hSqueeze*(col-1);
                obj.dispAx = axes('Parent',panel);
                obj.cbAx = [];
                obj.show;
                if ~isempty(opts.zoom)
                    axis(obj.dispAx,opts.zoom);
                end
                if opts.showNames
                    if inds(idx)> 0
                        title(obj.dispAx,obj.layers{inds(idx)}.name)
                    end
                end
                tileAxes{tileIdx} = {obj.dispAx,obj.cbAx};
                axPositions(tileIdx,:) = obj.dispAx.Position;
                panels{tileIdx} = panel;
            end
            if opts.match_dispAx_sizes
                for idx = 1:numel(tileAxes)
                    if ~isempty(tileAxes{idx})
                        tileAxes{idx}{1}.Position(1) = min(axPositions(:,1));
                        tileAxes{idx}{1}.Position(2) = min(axPositions(:,2));
                        tileAxes{idx}{1}.Position(3) = min(axPositions(:,3));
                        tileAxes{idx}{1}.Position(4) = min(axPositions(:,4));
                    end
                end
            end
            obj.prefs = old_prefs;
            obj.setVis(visLayers);
            obj.dispAx = ax;
            obj.cbAx = cax;
        end
        
        function blinkLayer(obj,layerInd,opts)
            arguments
                obj 
                layerInd;
                opts.blinkTime {mustBeNumeric,mustBeGreaterThan(opts.blinkTime,0)} = 0.2;
                opts.nBlinks {mustBeInteger,mustBeGreaterThan(opts.nBlinks,0)} = 5; 
            end
            if layerInd>numel(obj.layers)
                error("Layer %d index is out of range for %d layers",layerInd,numel(obj.layers));
            end
            if ~isempty(obj.layers{layerInd})
                for idx = (1:opts.nBlinks)
                    obj.layers{layerInd}.visible = false;
                    obj.show;
                    pause(opts.blinkTime);
                    obj.layers{layerInd}.visible = true;
                    obj.show;
                    pause(opts.blinkTime);
                end
            else
                fprintf('\nLayer %d is empty!',layerInd);
            end
        end

        function setVis(obj,layerInds)
            for idx = 1:numel(obj.layers)
                if find(layerInds==idx)
                    obj.layers{idx}.visible = true;
                else
                    obj.layers{idx}.visible = false;
                end
            end
        end

        function inds = whosVis(obj)
            inds = [];
            for idx = 1:numel(obj.layers)
                if obj.layers{idx}.visible
                    inds(end+1) = idx;  %#ok<AGROW>
                end
            end
        end

        function animate(obj,ind,opts)
            arguments
                obj 
                ind 
                opts.dt = 0.1;
                opts.nFrames = [];
            end
            
            if ind<0 || ind > numel(obj.layers)
                error('Invalid layer index!')
            end
            if ind == 0
                initRep = obj.base.viewRep;
                reps = obj.base.nReps;
            else
                initRep = obj.layers{ind}.viewRep;
                reps = obj.layers{ind}.nReps;
            end
            if ~isempty(opts.nFrames)&&opts.nFrames<=reps
                reps = opts.nFrames;
            end
            currVis = obj.whosVis;
            obj.setVis(ind);
            for rep = 1:reps
                if ind == 0
                    obj.base.viewRep = rep;
                else
                    obj.layers{ind}.viewRep = rep;
                end
                obj.show;
                title(obj.dispAx,sprintf('Frame: %d',rep))
                pause(opts.dt);
            end
            if ind == 0
                obj.base.viewRep = initRep;
            else
                obj.layers{ind}.viewRep = initRep;
            end
            obj.setVis(currVis);
            obj.show;

        end

        function show(obj,mode)
            arguments
                obj
                mode = 'abs';
            end
            
            switch mode
                case 'abs'
                    baseData = abs(squeeze(obj.base.data(:,:,obj.base.viewRep)));
                case 'real'
                    baseData = real(squeeze(obj.base.data(:,:,obj.base.viewRep)));
                case 'imag'
                    baseData = imag(squeeze(obj.base.data(:,:,obj.base.viewRep)));
            end
            
            
            if ~obj.base.tPose
                baseData = baseData';
            end
            if ~isempty(obj.base.mask)
                baseData = mask(baseData,obj.base.mask);
            end
            baseData =obj.globalTforms(baseData);

            baseData = circshift(baseData,obj.base.shift);
            
            if isempty(obj.dispAx)||~isvalid(obj.dispAx)
                ax = axes(figure,Visible='off');
                obj.dispAx = ax;
                disp('Making new figure');
            else
                ax = obj.dispAx;
            end
            baseData = baseData/max(max(baseData))*255;
            baseGray = ind2rgb(uint8(baseData),gray(256));
            if obj.base.visible
                imagesc(ax,baseGray);
            else
                imagesc(ax,zeros(size(baseData),'like',baseData));
            end
            %colormap(ax,'gray');
            axis(ax,'on');
            axis(ax,"image");
            set(ax,'XTick',[],'YTick',[])
            axis(ax,'tight');
            if ~obj.prefs.colorBar.visible&&~isempty(obj.cbAx)&&isvalid(obj.cbAx)
                obj.prefs.fit_to_frame = true;
            end
            if obj.prefs.fit_to_frame
                ax.Position = [0,0,1,1];
            end
            %%%%%%%%%%%%%%%%%% Add Grid %%%%%%%%%%%%%%%%%%
            if obj.prefs.grid.visible
                cellSize = (size(squeeze(obj.base.data(:,:,1)))./obj.prefs.grid.size);
                overlayGrid(ax,obj.prefs.grid.size,cellSize,"innerLW",obj.prefs.grid.innerLW,...
                                                            "innerRGB",obj.prefs.grid.innerRGB,...
                                                            "outerLW",obj.prefs.grid.outerLW,...
                                                            "outerRGB",obj.prefs.grid.outerRGB,...
                                                            "visCols",obj.prefs.grid.visCols,...
                                                            "visRows",obj.prefs.grid.visRows);
           end
            if isempty(find(obj.whosVis==obj.prefs.colorBar.targInd, 1))
                if ~isempty(obj.cbAx)
                    if isvalid(obj.cbAx)
                        delete(obj.cbAx)
                    end
                end
                obj.cbAx = [];
            end


           for idx = 1:numel(obj.layers)
                layer = obj.layers{idx};
                if ~isempty(layer)
                    layerData = layer.data;
                    
                    if layer.visible
                        switch mode
                            case 'abs'
                                layerData = abs(squeeze(layerData(:,:,layer.viewRep)));
                            case 'real'
                                layerData = real(squeeze(layerData(:,:,layer.viewRep)));
                            case 'imag'
                                layerData = imag(squeeze(layerData(:,:,layer.viewRep)));
                        end
                        
                        if ~layer.tPose
                            layerData = layerData';
                        end

                        %check to determine if imresize is necessary
                        if ~isequal(size(baseData),size(layerData))
                            layerData=imresize(layerData,size(baseData));
                        end
                        if ~isempty(layer.mask)
                            layerData = mask(layerData,layer.mask');
                        end
                        layerData =obj.globalTforms(layerData);

                        %avoid negatives:
                        min_value = min(min(layerData));
                        layerData = layerData+abs(min_value);
                        
                        
                        layerDataRaw = layerData;
                        if ~isempty(layer.normVal)
                            layerData(layerData>layer.normVal) = layer.normVal;
                            layerData=layerData/layer.normVal*255;
                        else
                            max_value = max(max(layerData));
                            layerData=layerData/max_value*255;
                        end
                        if isempty(layer.solidRGB)
                            coltab = ind2rgb(uint8(layerData),jet(256)); % use jet color, convert to RGB format, 256x256
                        else
                            rgb = layer.solidRGB;
                            rgbMap = cat(2,cat(2,rgb(1).*ones(length(layerData),1), ...
                                                 rgb(2).*ones(length(layerData),1)), ...
                                                 rgb(3).*ones(length(layerData),1));
                            coltab = ind2rgb(uint8(layerData),rgbMap);
                        end
                        %coltab =obj.globalTforms(coltab);
                        
                        hold(ax,'on');
                        img = imagesc(ax,coltab);
                        imAlphaData = zeros(size(layerData)); % transparency mask
                        imAlphaData(layerData(:) >= (layer.thresh*255)) = layer.trans;
                        set(img,'AlphaData',imAlphaData);
                        set(img, 'AlphaDataMapping', 'none');
                        hold(ax,'off');

                        %%%%%%%%%%%% Add Color Bar %%%%%%%%%%%%%%%%%%%
                        
                        if idx == obj.prefs.colorBar.targInd
                            if obj.prefs.colorBar.visible
                                data = layerDataRaw(layerData>0);
                                if isempty(obj.cbAx)||~isvalid(obj.cbAx)
                                    obj.prefs.fit_to_frame = false;
                                    obj.cbAx = plotRGBColorbar(obj.dispAx,data,jet(256),true,"nTicks",obj.prefs.colorBar.nTicks, ...
                                                                                             "tickLoc",obj.prefs.colorBar.tickLoc, ...
                                                                                             'tickMargin',obj.prefs.colorBar.tickMargin,...
                                                                                             'margin_h',obj.prefs.colorBar.hMargin, ...
                                                                                             'sigFigs',obj.prefs.colorBar.sigFigs);
                                else
                                    plotRGBColorbar(obj.cbAx,data,jet(256),false,"nTicks",obj.prefs.colorBar.nTicks,...
                                                                                 "tickLoc",obj.prefs.colorBar.tickLoc,...
                                                                                 'tickMargin',obj.prefs.colorBar.tickMargin,...
                                                                                 'margin_h',obj.prefs.colorBar.hMargin,...
                                                                                 'sigFigs',obj.prefs.colorBar.sigFigs);
                                end
                            else
                                if ~isempty(obj.cbAx)&&isvalid(obj.cbAx)
                                    delete(obj.cbAx);
                                end
                            end
                        end
                    end
                end
            end
        end
    end

end
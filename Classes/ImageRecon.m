classdef ImageRecon<handle
    
    properties
        layers;
        dispAx;
        rotAng = 0;
        baseInd = 1;
        aspect = [];
        prefs = struct('rotationInterpMethod','bilinear', ...
                       'colorbar',struct('visible',false,...
                                         'targInd',1, ...
                                         'nTicks',5,...
                                         'sigFigs',2,...
                                         'padding_LR',[0,0.1],...
                                         'padding_UD',[0.05,0.05]),...
                       'grid',struct('visible',false,...
                                     'size',[],...
                                     'visRows',[],...
                                     'visCols',[],...
                                     'innerRGB',[1,1,1],...
                                     'outerRGB',[1,1,1],...
                                     'innerLW',2,...
                                     'outerLW',3 ...
                                     ));
            
        masks = {};
        
    end

    properties (Dependent)
        base;
    end


    methods (Access = private)

        function newData = globalTforms(obj,data,invert)
            arguments
                obj
                data
                invert = false
            end
            if invert
                newData = imrotate(data,-obj.rotAng,obj.prefs.rotationInterpMethod,'crop');
            else
                newData = imrotate(data,obj.rotAng,obj.prefs.rotationInterpMethod,'crop');
            end
        end
    end

    methods
        function obj = ImageRecon(baseData)
            arguments
                baseData (:,:,:) {mustBeNumeric} = [];
            end
            %Base data is assumed to be structural MRI. If this behavior is
            %not desired, do not pass base data when instantiating and
            %instead add layers after.
            if ~isempty(baseData)
                obj.addLayer(baseData,style="struc");
            end
        end

        function baseLayer = get.base(obj)
            baseLayer = obj.layers{obj.baseInd};
        end

        function set.base(obj,baseStruct)
            obj.layers{obj.baseInd} = baseStruct;
        end

        function toFront(obj)
            if isvalid(obj.dispAx)
                fig = ancestor(obj.dispAx, 'figure');
                figure(fig);
            end
        end

        function newMask(obj)
            obj.toFront;
            maskSize = size(obj.base.data(:,:,1)');
            [mask_,saveMask] = drawMask(obj.dispAx,maskSize);
            mask_ = obj.globalTforms(mask_,true);
            if ~isempty(mask_)
                if saveMask
                    obj.masks{end+1} = mask_;
                else
                    deciding = true;
                    while deciding
                        res = input('Would you like to save this mask? (y/n)','s');
                        switch res
                            case 'y'
                                obj.masks{end+1} = mask_;
                                deciding = false;
                            case 'n'
                                deciding = false;
                            otherwise
                                disp('Valid responses are: ''y'' or ''n''')
                        end
                    end
                end
            end
        end

        function roiInfo = roiAnalysis(obj,roiMasks,targetInd,opts)
            arguments
                 obj
                 roiMasks
                 targetInd {mustBeInteger,mustBeGreaterThanOrEqual(targetInd,1)} = 1;
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
        
        function adjustLayer(obj,layerInd)
            obj.toFront;
            adjusting = true;
            obj.show;
            origShift = obj.layers{layerInd}.shift;
            while adjusting
                shift = input(sprintf('\nFrame (i,k) = %d\nShift (wasd): [U/D,L/R]=[%d,%d] ->', ...
                    obj.layers{layerInd}.viewRep,obj.layers{layerInd}.shift(1),obj.layers{layerInd}.shift(2)),'s');
                switch shift
                    case 'esc'
                        obj.layers{layerInd}.shift = origShift;
                        adjusting = false;
                    case 'apply'
                        adjusting = false;
                    case 'reset'
                        obj.layers{layerInd}.shift = [0,0];
                    case 'w'
                        obj.layers{layerInd}.shift(1) = obj.layers{layerInd}.shift(1)+1;
                    case 's'
                        obj.layers{layerInd}.shift(1) = obj.layers{layerInd}.shift(1)-1;
                    case 'd'
                        obj.layers{layerInd}.shift(2) = obj.layers{layerInd}.shift(2)+1;
                    case 'a'
                        obj.layers{layerInd}.shift(2) = obj.layers{layerInd}.shift(2)-1;
                    case 'i'
                        if obj.layers{layerInd}.viewRep+1<=obj.layers{layerInd}.nReps
                            obj.layers{layerInd}.viewRep = obj.layers{layerInd}.viewRep+1;
                        end
                    case 'k'
                        if obj.layers{layerInd}.viewRep>1
                            obj.layers{layerInd}.viewRep = obj.layers{layerInd}.viewRep-1;
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
                opts.name = [];
                opts.style {mustBeMember(opts.style,{'struc','func'})} = 'func';
                opts.visible logical = true;
                opts.tPose logical = false;
                opts.shift (1,2) = [0,0];
                opts.viewRep {mustBeInteger,mustBeGreaterThan(opts.viewRep,0)} = 1;
                opts.trans {mustBeNumeric,...
                            mustBeGreaterThanOrEqual(opts.trans,0),...
                            mustBeLessThanOrEqual(opts.trans,1)} = [];
                opts.thresh {mustBeNumeric,...
                            mustBeGreaterThanOrEqual(opts.thresh,0),...
                            mustBeLessThanOrEqual(opts.thresh,1)} = [];
                opts.mask (:,:) logical = [];
                opts.cmap (:,3) = [];
                opts.clim (1,2) = [0,1];
            end

            %Layer is 3d matrix (x,y,nReps)
            layerData = squeeze(layerData);
            [~,~,nReps] = size(layerData);
            if strcmp(opts.style,'func')
                %default formatting for fMRI
                if isempty(opts.trans)
                    opts.trans = 0.3;
                end
                if isempty(opts.thresh)
                    opts.thresh = [0,1];
                end
                if isempty(opts.cmap)
                    opts.cmap = jet(256);
                end
            else
                %default formatting for sMRI
                if isempty(opts.trans)
                    opts.trans = 1;
                end
                if isempty(opts.thresh)
                    opts.thresh = [0,1];
                end
                if isempty(opts.cmap)
                    opts.cmap = gray(256);
                end
            end
            newLayer = struct('name',opts.name,...
                              'style',opts.style,...
                              'data',layerData,...
                              'visible',opts.visible,...
                              'tPose',opts.tPose,...
                              'shift',opts.shift,...
                              'viewRep',opts.viewRep,...
                              'nReps',nReps,...
                              'trans',opts.trans,...
                              'thresh',opts.thresh,...
                              'mask',opts.mask,...
                              'cmap',opts.cmap,...
                              'clim',opts.clim,...
                              'mode','abs');
            obj.layers{end+1} = newLayer;
            layerInd = numel(obj.layers);
            obj.show;
        end

        function [tileAxes,panels] = tileLayers(obj,m,n,inds,opts)
            arguments
                obj
                m {mustBeInteger};
                n {mustBeInteger};
                inds {mustBeInteger} = [];
                opts.showNames = true;
                opts.parent = [];
                opts.zoom = [];
                opts.spacing {mustBeGreaterThanOrEqual(opts.spacing,0),...
                              mustBeLessThanOrEqual(opts.spacing,1)}= 0;
                opts.hSqueeze {mustBeGreaterThanOrEqual(opts.hSqueeze,0),...
                              mustBeLessThanOrEqual(opts.hSqueeze,1)}= 0;
                opts.autoThresh = false;
                opts.autoCB = true;
            end
            if isempty(inds)
                inds = 1:numel(obj.layers);
            end
            old_prefs = obj.prefs;
            if isempty(opts.parent)
                parent = figure;
            else
                parent = opts.parent;
            end
            currAx = obj.dispAx;
            visLayers = obj.whosVis;
            tileAxes = cell(m*n,1);
            axPositions = ones(m*n,4);
            panels = cell(m*n,1);
            
            
            for idx = 1:(m*n)
                
                pos = getGridPos(m,n,idx,opts.spacing);
                col = mod(idx - 1, n) + 1;
                pos(1) = pos(1)-opts.hSqueeze*(col-1);
                ax = axes('Parent',parent,'Visible','off');
                if idx<=numel(inds)
                    obj.setVis(inds(idx));
                    set(ax,'Visible','on');
                    obj.dispAx = ax;
                    obj.show("autoCB",opts.autoCB,"autoThresh",opts.autoThresh,'bounds',pos,'clearFig',false);
                    if ~isempty(opts.zoom)
                        axis(obj.dispAx,opts.zoom);
                    end
                    if opts.showNames
                        if inds(idx)> 0
                            title(obj.dispAx,obj.layers{inds(idx)}.name)
                        end
                    end
                end
                tileAxes{idx} = ax;
                axPositions(idx,:) = ax.Position;
            end
            obj.prefs = old_prefs;
            obj.setVis(visLayers);
            obj.dispAx = currAx;
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

        function setVis(obj,layerInds,opts)
            arguments
                obj
                layerInds
                opts.holdBase = true
            end
            for idx = 1:numel(obj.layers)
                if find(layerInds==idx)
                    obj.layers{idx}.visible = true;
                else
                    obj.layers{idx}.visible = false;
                end
            end
            if opts.holdBase
                obj.layers{obj.baseInd}.visible = true;
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
                opts.frames {mustBeInteger} = [];
            end
        
            initRep = obj.layers{ind}.viewRep;
            reps = 1:obj.layers{ind}.nReps;
            
            if ~isempty(opts.frames)
                assert(all(opts.frames>=1 & opts.frames<=numel(reps)), ...
                    'Error: frame range is out of bounds.');
                reps = opts.frames;
            end
            currVis = obj.whosVis;
            obj.setVis(ind);
            for rep = reps
                obj.layers{ind}.viewRep = rep;
                obj.show;
                title(obj.dispAx,sprintf('Frame: %d',rep))
                pause(opts.dt);
            end
            obj.layers{ind}.viewRep = initRep;
            obj.setVis(currVis);
            obj.show;

        end

        function tbl = listLayers(obj,fields,inds)
            arguments
                obj
                fields = {'name'}
                inds = [];
            end
            if isempty(inds)
                inds = 1:numel(obj.layers);
            end
            tbl = listStructFields({obj.layers{inds}},fields);
        end

        function adjustCmap(obj,layerInd,opts)
            arguments
                obj
                layerInd
                opts.nControlPts = 2;
                opts.reset = false;
                opts.iterative = false;
            end
            
            working = true;
            save = false;
            ax = axes(figure);
            initCmap = obj.layers{layerInd}.cmap;
            while working
                if opts.reset
                    switch obj.layers{layerInd}.style
                        case 'struc'
                            obj.layers{layerInd}.cmap = gray(256);
                        case 'func'
                            obj.layers{layerInd}.cmap = jet(256);
                    end
                end
                
                cmap = obj.layers{layerInd}.cmap;
                adjustCmap(cmap,opts.nControlPts,[],"dispAx",ax);
                if opts.iterative
                    opts.reset = true;
                    res = input('Enter/apply/esc: ','s');
                    switch res
                        case ''
                        case 'apply'
                            working = false;
                            save = true;
                        case 'esc'
                            working = false;
                            save = false;
                        otherwise
                            disp('invalid response');
                    end
                else
                    input('Press any enter to confirm')
                end
                drawnow;
                if isvalid(ax)
                    newCmap = get(ax,'Colormap');
                    obj.layers{layerInd}.cmap = newCmap;
                end
                if opts.iterative
                    obj.show
                end
            end
            if isvalid(ax)
                close(ax.Parent);
            end
            if ~save
                obj.layers{layerInd}.cmap = initCmap;
            end
            if opts.iterative
                obj.show
            end
            
        end

        function spreadParams(obj,refInd,spreadInds,fields)
            refLayer = obj.layers{refInd};
            spreadLayers = {obj.layers{spreadInds}}; %#ok<CCAT1>
            newLayers = spreadStructFields(refLayer,spreadLayers,fields);
            for idx = 1:numel(spreadInds)
                ind = spreadInds(idx);
                obj.layers{ind} = newLayers{idx};
            end
        end

        function data = getShowData(obj,layerInds)
            baseLayer = obj.base;
            data = cell(numel(layerInds),1);
            if baseLayer.tPose
                baseSize = size(squeeze(baseLayer.data(:,:,1)));
            else
                baseSize = size(squeeze(baseLayer.data(:,:,1))');
            end
            for idx = 1:numel(layerInds)
                lInd = layerInds(idx);
                layer = obj.layers{lInd};
                rep = layer.viewRep;
                layerData = squeeze(eval(sprintf('%s(layer.data(:,:,%d))',layer.mode,rep)));
                if ~layer.tPose
                    layerData = layerData';
                end
                layerData = imresize(layerData,baseSize);
                layerData = obj.globalTforms(layerData);
                layerData = circshift(layerData,layer.shift);
                if ~isempty(layer.mask)
                    if ~layer.tPose
                        layerMask = layer.mask';
                    else
                        layerMask = layer.mask;
                    end
                    layerMask = obj.globalTforms(layerMask);
                    layerData = mask(layerData,layerMask);
                end
                data{idx} = layerData;
            end
        end

        function show(obj,opts)
            arguments
                obj
                opts.autoThresh = false
                opts.autoCB = true;
                opts.clearFig = true;
                opts.bounds = [0,0,1,1];
            end

            if isempty(obj.dispAx)||~isvalid(obj.dispAx)
                ax = axes(figure);
                obj.dispAx = ax;
                
            else
                ax = obj.dispAx;
            end
            cbTargInd = obj.prefs.colorbar.targInd;
            if obj.prefs.colorbar.visible
                pos = opts.bounds;
                padLR = obj.prefs.colorbar.padding_LR;
                padUD = obj.prefs.colorbar.padding_UD;
                %normalize padding:
                padLR = padLR.*pos(3);
                padUD = padUD.*pos(4);
                pos(1) = pos(1)+padLR(1);
                pos(2) = pos(2)+padUD(1);
                pos(3) = pos(3)-padLR(2)-padLR(1);
                pos(4) = pos(4)-padUD(2)-padUD(2);
                set(ax,'Position',pos);
                %autoTargInd:
                if opts.autoCB
                    currVis = obj.whosVis;
                    currVis_notBase = currVis(currVis~=obj.baseInd);
                    if numel(currVis_notBase)>1
                        warning(['Too many layers for auto colorbar!' ...
                                ' Please specify colorbar target index!']);
                    else
                        if numel(currVis_notBase)==0
                            currVis_notBase = obj.baseInd;
                        end
                        cbTargInd = currVis_notBase;
                    end
                end
            else
                set(ax,'Position',opts.bounds);
            end
            obj.toFront;

            cla(ax);
            if opts.clearFig
                children = get(ax.Parent,'Children');
                for idx = 1:numel(children)
                    child = children(idx);
                    if child ~=ax
                        delete(child)
                    end
                end
            end
            
            baseLayer = obj.base;
            if baseLayer.tPose
                baseSize = size(squeeze(baseLayer.data(:,:,1)));
            else
                baseSize = size(squeeze(baseLayer.data(:,:,1))');
            end
            for lInd = 1:numel(obj.layers)
                if obj.layers{lInd}.visible
                    layer = obj.layers{lInd};
                    rep = layer.viewRep;
                    layerData = squeeze(eval(sprintf('%s(layer.data(:,:,%d))',layer.mode,rep)));
                    if ~layer.tPose
                        layerData = layerData';
                    end
                    layerData = imresize(layerData,baseSize);
                    layerData = obj.globalTforms(layerData);
                    layerData = circshift(layerData,layer.shift);
                    if ~isempty(layer.mask)
                        if ~layer.tPose
                            layerMask = layer.mask';
                        else
                            layerMask = layer.mask;
                        end
                        layerMask = obj.globalTforms(layerMask);
                        layerData = mask(layerData,layerMask);
                    end
                    [dataMin,dataMax] = bounds(layerData,'all');
                    dataRange = dataMax-dataMin;
                    dataMax = dataMax-dataRange*(1-layer.clim(2));
                    dataMin = dataMin+dataRange*layer.clim(1);
                    %format data for cmap
                    layerData = layerData-min(min(layerData));
                    layerData = layerData/max(max(layerData));
                    layerData_norm = layerData;

                    layerData(layerData<=layer.clim(1)) = layer.clim(1);
                    layerData(layerData>=layer.clim(2)) = layer.clim(2);

                    layerData = mat2gray(layerData)*height(layer.cmap);
                    layerTC = ind2rgb(round(layerData),layer.cmap);
                    if opts.autoThresh
                        thresh = layer.clim;
                    else
                        thresh = layer.thresh;
                    end
                    hold(ax,'on');
                    img = imagesc(ax,layerTC);
                    imAlpha = repmat(layer.trans,size(layerData));
                    imAlpha(layerData_norm<thresh(1)) = 0;
                    imAlpha(layerData_norm>thresh(2)) = 0;
                    set(img,'AlphaData',imAlpha);
                    set(img,'AlphaDataMapping','none');
                    hold(ax,'off');
                    if obj.prefs.colorbar.visible&&lInd==cbTargInd
                        cbAx = axes(Visible=false, ...
                                    HandleVisibility='on', ...
                                    Position = ax.Position);
                        set(cbAx,'Parent',ax.Parent)
                        colormap(cbAx,layer.cmap);
                        linkaxes([ax,cbAx])
                        linkprop([ax,cbAx],{'Position','DataAspectRatio'});
                        cb = colorbar(cbAx);
                        nTicks = obj.prefs.colorbar.nTicks;
                        cb.Ticks = linspace(0,1,nTicks);
                        sf = obj.prefs.colorbar.sigFigs;
                        ticks = round(linspace(dataMin,dataMax,nTicks),sf,'significant');
                        cb.TickLabels = arrayfun(@(x) sprintf('%.*e', sf-1, x), ticks, 'UniformOutput', false);
                        drawnow;
                    end
                end
            end
            if obj.prefs.grid.visible
                if ~isempty(obj.prefs.grid.size)
                    cellSize = (size(squeeze(obj.base.data(:,:,1)'))./obj.prefs.grid.size);
                    overlayGrid(ax,obj.prefs.grid.size,cellSize,"innerLW",obj.prefs.grid.innerLW,...
                                                                "innerRGB",obj.prefs.grid.innerRGB,...
                                                                "outerLW",obj.prefs.grid.outerLW,...
                                                                "outerRGB",obj.prefs.grid.outerRGB,...
                                                                "visCols",obj.prefs.grid.visCols,...
                                                                "visRows",obj.prefs.grid.visRows);
                end
           end
            axis(ax,'on');
            set(ax,'XTick',[],'YTick',[])
            axis(ax,'tight');
            if ~isempty(obj.aspect)
                set(ax,'DataAspectRatio',obj.aspect)
            else
                axis(ax,'image')
            end
            drawnow;
        end
    end

end
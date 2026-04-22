classdef VisAssembly < handle
    
    properties
        dispAx = gobjects(0);
        baseInd = 1;
        layers = {};
    end

    properties (Dependent)
        base;
    end

    methods

        function obj = VisAssembly(baseObj,opts)
            arguments
                baseObj = [];
                opts.dispAx = gobjects(0);
            end
            obj.dispAx = opts.dispAx;
            if ~isempty(baseObj)
                obj.addLayer(baseObj,"name",'Base Layer','trans',1);
            end
        end

        function addLayer(obj,data,geomObj,opts)
            arguments
                obj
                data
                geomObj
                opts.name = '';
                opts.visible = 1;
                opts.trans = 1;
                opts.cmap = gray(256);
            end
            assert(isa(geomObj,'GeometryObj'),'Geometry objects must be members of GeometryObj!');
            fdata = geomObj.formatData(data);
            name = opts.name;
            if isempty(name)
                name = sprintf('Layer %d',numel(obj.layers)+1);
            end
            objStruct = struct('name',name,...
                               'data',fdata,...
                               'cmap',opts.cmap,...
                               'visible',opts.visible,...
                               'trans',opts.trans,...
                               'geometry',geomObj);
            obj.layers{end+1} = objStruct;
        end

        function baseLayer = get.base(obj)
            baseLayer = obj.layers{obj.baseInd};
        end

        function show3D(obj,opts)
            arguments
                obj
                opts.thresh = 0;
                opts.focFrame = [];
            end
            if ~isempty(obj.dispAx)
                if isvalid(obj.dispAx)||isa(matlab.graphics.axis.Axes)
                    ax = obj.dispAx; 
                end
            else
                ax = axes(figure);
            end
            cla(ax);
            hold(ax,'on');
            axis(ax,'equal');
            grid(ax,'on');
            for idx = 1:numel(obj.layers)
                layer = obj.layers{idx};
                if layer.visible
                    geomObj = layer.geometry;
                    [xs,ys,zs] = geomObj.getMapping(geomObj.affMats_wrld);
                    thresh = opts.thresh;
                    for slice = 1:geomObj.nSlices
                        xs_frame = squeeze(xs(:,:,:,slice));
                        ys_frame = squeeze(ys(:,:,:,slice));
                        zs_frame = squeeze(zs(:,:,:,slice));
                        frameData = squeeze(sum(layer.data(:,:,:,:,slice),1));
                        frameData_norm = frameData;
                        frameData_norm = frameData_norm-min(frameData(:),[],'omitmissing');
                        frameData_norm = frameData_norm./max(frameData(:),[],'omitmissing');
                        frameData_norm(frameData_norm<thresh) = NaN;
                        frameTC = mat2TC(frameData_norm,layer.cmap);
                        mesh(ax,xs_frame,ys_frame,zs_frame,frameTC,'FaceColor','interp', ...
                                                                   'FaceAlpha',layer.trans, ...
                                                                   'EdgeAlpha',layer.trans);
                    end
                end
            end
            hold(ax,'on');
            view(ax,3);
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

        function show2D(obj,opts)
            arguments
                obj
                opts.baseFrame = [];
            end
            baseLayer = obj.base;
            baseGeomObj = baseLayer.geometry;
            baseFrame = opts.baseFrame;
            if isempty(opts.baseFrame)
                baseFrame = 1;
            end
            if ~isempty(obj.dispAx)
                if isvalid(obj.dispAx)||isa(matlab.graphics.axis.Axes)
                    ax = obj.dispAx; 
                end
            else
                ax = axes(figure);
                view(ax,2);
            end
            axis(ax,'image');
            grid(ax,'off');
                
            
            [xs,ys,zs] = baseGeomObj.getMapping(baseGeomObj.affMats_img);
            baseData = squeeze(sum(baseLayer.data(:,:,:,1,baseFrame),1));
            baseData_norm = baseData;
            baseData_norm = baseData_norm-min(baseData(:),[],'omitmissing');
            baseData_norm = baseData_norm./max(baseData(:),[],'omitmissing');
            baseData_tc = mat2TC(baseData_norm,baseLayer.cmap);
            hold(ax,"on");
            cla(ax);
            mesh(ax,xs(:,:,:,baseFrame),ys(:,:,:,baseFrame),zs(:,:,:,baseFrame),baseData_tc,'FaceColor','interp',...
                                                                                            'FaceAlpha',baseLayer.trans, ...
                                                                                            'EdgeAlpha',0);
            framePos = zs(1,1,1,baseFrame);
            frameThick_base = baseGeomObj.voxSize(3);

            for idx = 1:numel(obj.layers)
                layer = obj.layers{idx};
                if layer.visible
                    layerGeomObj = layer.geometry;
                    if ~isequal(layerGeomObj,baseGeomObj)
                        baseMat_img = baseGeomObj.affMats_img(:,:,baseFrame);
                        baseMat_wrld = baseGeomObj.affMats_wrld(:,:,baseFrame);
                        baseTform = baseMat_img/baseMat_wrld;
                        tForm = zeros(size(layerGeomObj.affMats_wrld));
                        for slc = 1:layerGeomObj.nSlices
                            tForm(:,:,slc) = baseTform*layerGeomObj.affMats_wrld(:,:,slc);
                        end
                        [xs,ys,zs] = layerGeomObj.getMapping(tForm);
                        zRange = [framePos-frameThick_base/2,framePos+frameThick_base/2];
                        zMask = ones(size(zs));
                        frameThick_layer = layerGeomObj.voxSize(3);
                        zMask(zs+frameThick_layer/2<min(zRange)) = NaN;
                        zMask(zs-frameThick_layer/2>max(zRange)) = NaN;
                        data = layer.data;
                        data = data.*reshape(zMask,size(data));
                        data = squeeze(mean(data(:,:,:,:,:,1),[1,4]));
                        data_norm = data;
                        data_norm = data_norm-min(data(:),[],'omitmissing');
                        data_norm = data_norm./max(data(:),[],'omitmissing');
                        for slc = 1:size(data_norm,3)
                            slcData = data_norm(:,:,slc);
                            tc = mat2TC(slcData,layer.cmap);
                            mesh(ax,xs(:,:,:,slc),ys(:,:,:,slc),zs(:,:,:,slc),tc,"FaceColor","interp", ...
                                                                                 'FaceAlpha',layer.trans, ...
                                                                                 'EdgeAlpha',layer.trans);
                        end
                    end
                end
            end
            hold(ax,'off');
        end
    
    end
end
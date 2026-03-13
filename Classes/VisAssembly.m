classdef VisAssembly
    
    properties
        visObjs
    end

    methods
        function obj = VisAssembly(visObjs)
            arguments
                visObjs
            end
            if ~iscell(visObjs)
                visObjs = {visObjs};
            end
            for idx = 1:numel(visObjs)
                assert(isa(visObjs{idx},'VisObj'),'Vis objects must be members of VisObj!');
            end
            obj.visObjs = visObjs;
        end

        function show3D(obj,opts)
            arguments
                obj
                opts.thresh = 0;
                opts.focFrame = [];
                opts.ax = []
            end
            if ~isempty(opts.ax)
                if isvalid(opts.ax)
                    ax = opts.ax;
                    cla(ax);
                end
            else
                ax = axes(figure);
            end
            hold(ax,'on');
            axis(ax,'equal');
            grid(ax,'on');
            colormap(ax,'gray');
            for idx = 1:numel(obj.visObjs)
                visObj = obj.visObjs{idx};
                [xs,ys,zs] = visObj.getMapping(visObj.affMats_wrld);
                thresh = opts.thresh;
                for slice = 1:visObj.nSlices
                    xs_frame = squeeze(xs(:,:,:,slice));
                    ys_frame = squeeze(ys(:,:,:,slice));
                    zs_frame = squeeze(zs(:,:,:,slice));
                    frameData = squeeze(sum(visObj.data(:,:,:,:,slice),1));
                    frameData_norm = frameData;
                    frameData_norm = frameData_norm-min(frameData(:),[],'omitmissing');
                    frameData_norm = frameData_norm./max(frameData(:),[],'omitmissing');
                    frameData_norm(frameData_norm<thresh) = NaN;
                    m = mesh(ax,xs_frame,ys_frame,zs_frame,frameData_norm,'FaceColor','interp');
                    if ~isempty(opts.focFrame)
                        if isequal(opts.focFrame,slice)
                            m = mesh(ax,xs_frame,ys_frame,zs_frame,'EdgeColor','r','FaceColor','r','FaceAlpha',0.2,'EdgeAlpha',0.2);
                        end
                    end
                    set(m,'AlphaData',frameData_norm);
                end
            end
            view(ax,3);
        end

        function show2D(obj,opts)
            arguments
                obj
                opts.baseObj = [];
                opts.baseFrame = [];
                opts.ax = [];
            end
            baseObj = opts.baseObj;
            if isempty(baseObj)
                baseObj = obj.visObjs{1};
            end
            baseFrame = opts.baseFrame;
            if isempty(opts.baseFrame)
                baseFrame = 1;
            end
            ax = opts.ax;
            if ~isempty(ax)
                assert(isa(ax, 'matlab.graphics.axis.Axes')&&isvalid(ax),'ax parameter must be a valid axes handle!');
            else
                ax = axes(figure);
            end
            
            [xs,ys,zs] = baseObj.getMapping(baseObj.affMats_img);
            baseData = squeeze(sum(baseObj.data(:,:,:,1,baseFrame),1));
            baseData_norm = baseData;
            baseData_norm = baseData_norm-min(baseData(:),[],'omitmissing');
            baseData_norm = baseData_norm./max(baseData(:),[],'omitmissing');
            surface(ax,xs(:,:,:,baseFrame),ys(:,:,:,baseFrame),zs(:,:,:,baseFrame),baseData_norm,'EdgeColor','none','FaceColor','flat');
            colormap(ax,'gray');
            axis(ax,'image')
            view(ax,2);
            framePos = zs(1,1,1,baseFrame);
            frameThick_base = baseObj.voxSize(3);

            for idx = 1:numel(obj.visObjs)
                visObj = obj.visObjs{idx};
                if ~isequal(visObj,baseObj)
                    baseMat_img = baseObj.affMats_img(:,:,baseFrame);
                    baseMat_wrld = baseObj.affMats_wrld(:,:,baseFrame);
                    baseTform = baseMat_img/baseMat_wrld;
                    baseTform = repmat(baseTform,[1,1,visObj.nSlices]);
                    [xs,ys,zs] = visObj.getMapping(baseTform.*visObj.affMats_wrld);
                    zRange = [framePos-frameThick_base/2,framePos+frameThick_base/2];
                    zMask = ones(size(zs));
                    frameThick_layer = visObj.voxSize(3);
                    zMask(zs+frameThick_layer/2<min(zRange)) = NaN;
                    zMask(zs-frameThick_layer/2>max(zRange)) = NaN;
                    hold(ax,'on');
                    data = squeeze(sum(visObj.data(:,:,:,1,1),1));
                    data = data.*zMask;
                    data_norm = data;
                    data_norm = data_norm-min(data(:),[],'omitmissing');
                    data_norm = data_norm./max(data(:),[],'omitmissing');
                    tc = mat2TC(data_norm,jet(256));
                    tc(isnan(data)) = NaN;
                    surface(ax,xs(:,:,:,1),ys(:,:,:,1),zs(:,:,:,1),tc,"FaceAlpha",0.3,"FaceColor","flat","EdgeColor","none");
                end
            end
            hold(ax,'off');
        end
    
    end
end
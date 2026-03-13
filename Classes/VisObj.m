classdef VisObj<handle

    properties
        data;
        params;
        cmap = gray(256);
        nSlices;
        nEchos;
        nReps;
    end

    properties (Dependent)
        affMats_img;
        affMats_wrld;
        spatMatSize;
        voxSize;
    end

    methods
        function obj = VisObj(data,params)
            arguments
                data %must be in shape: [core_dims,frameGroups]
                params.allParams = [];

                params.VisuCoreFrameCount = []; %num repititions
                params.VisuCoreSize = []; %matrix size for core dimensions
                params.VisuCoreDimDesc = []; %description of dimension types
                params.VisuCoreExtent = []; %physical length of core dims
                params.VisuCoreFrameThickness = []; %slice thickness
                params.VisuCoreUnits = []; %units for core dims
                params.VisuCoreOrientation = []; %basis vecs for slices
                params.VisuCorePosition = []; %system origin for slices
                params.VisuFGOrderDesc = []; %description of frame groups
                
                %spectral params to create ppm/hz axis:
                params.VisuMrsChemicalShiftReference = []; %ppm center freq
                params.VisuMrsSpectralWidth = []; %hz bandwidth
            end
            % set obj.params to any explicitly passed parameters
            obj.params = rmfield(params,'allParams');
            % if parameters were passed using allParams, fill valid fields:
            if ~isempty(params.allParams)
                paramFields = fieldnames(params.allParams);
                for idx = (1:length(paramFields))
                    fieldName = paramFields{idx};
                    if isfield(obj.params,fieldName)
                        %only use allParams value if not already explicitly set
                        if ~isempty(fieldName)
                            obj.params.(fieldName) = params.allParams.(fieldName);
                        end
                    end
                end
            end

            %check that data size matches Visu params:
            coreSize = ones(1,4);
            visuCoreSize = obj.params.VisuCoreSize;
            coreSize(1:numel(visuCoreSize)) = visuCoreSize;

            fgDims = ones(1,3);
            fgDescs = cell(1,3);
            if isfield(obj.params, 'VisuFGOrderDesc')
                visuFGDesc = obj.params.VisuFGOrderDesc;
                for idx=1:size(visuFGDesc,2)
                    fgDims(idx)= visuFGDesc{1,idx}; 
                    fgDescs{idx} = visuFGDesc{2,idx};
                end      
            else
                fgDims = obj.params.VisuCoreFrameCount;
            end
            fgOrder = cell(1,3);
            if isempty(fgDescs)
                fgOrder{1} = 1;
            else
                fgOrder{1} = find(strcmp(fgDescs,'FG_SLICE'));
                fgOrder{2} = find(strcmp(fgDescs,'FG_ECHO'));
                fgOrder{3} = find(strcmp(fgDescs,'FG_CYCLE'));
            end
            obj.nSlices = 1;
            obj.nReps = 1;
            obj.nEchos = 1;
            if ~isempty(fgOrder{1})
                obj.nSlices = fgDims(fgOrder{1});
            end
            if ~isempty(fgOrder{2})
                obj.nEchos = fgDims(fgOrder{2});
            end
            if ~isempty(fgOrder{3})
                obj.nReps = fgDims(fgOrder{3});
            end
            fgOrder(cellfun('isempty',fgOrder)) = {0};
            fgOrder = cell2mat(fgOrder);
            fgOrder(fgOrder==0) = [];

            expectedShape = [coreSize,fgDims];
            expectedShape_squeezed = expectedShape(expectedShape~=1);
            if ~all(isequal(size(squeeze(data)),expectedShape_squeezed))
                error('ERROR: Data shape of %s does not match expected %s', ...
                    formattedDisplayText(size(squeeze(data)),"SuppressMarkup",true), ...
                    formattedDisplayText(expectedShape_squeezed,"SuppressMarkup",true));
            end
            %%Now reshape data into: [nPoints,x,y,z,slice,echo,rep...]
            coreDesc = obj.params.VisuCoreDimDesc;
            coreOrder = [1,2,3,4];
            if any(ismember(coreDesc,'spectroscopic'))
                for idx = 1:numel(coreDesc)
                    if strcmp(coreDesc{idx},'spectroscopic')
                        coreOrder(1) = idx;
                        coreOrder(idx) = 1;
                    end
                end
            else
                coreOrder = [4,1,2,3];
            end
            dataOrder = [coreOrder,fgOrder+4];
            obj.data = permute(data,dataOrder);

        end

        function vSize = get.voxSize(obj)
            vSize = [];
            coreSize = obj.params.VisuCoreSize;
            coreExtent = obj.params.VisuCoreExtent;
            coreDesc = obj.params.VisuCoreDimDesc;
            for idx = 1:numel(coreSize)
                if strcmp(coreDesc{idx},'spatial')
                    vSize(end+1) = coreExtent(idx)/coreSize(idx); %#ok agrow
                end
            end
            if numel(vSize)<3
                vSize(end+1) = obj.params.VisuCoreFrameThickness;
            end
        end

        function sSize = get.spatMatSize(obj)
            sSize = [];
            coreSize = obj.params.VisuCoreSize;
            coreDesc = obj.params.VisuCoreDimDesc;
            for idx = 1:numel(coreSize)
                if strcmp(coreDesc{idx},'spatial')
                    sSize(end+1) = coreSize(idx); %#ok agrow
                end
            end
            if numel(sSize)<3
                sSize(end+1) = 1;
            end
        end

        function aMats_img = get.affMats_img(obj)
            %get affine matrix stack from (indexed space) -> (image coords)
            %nFrames = obj.params.VisuCoreFrameCount;
            aMats_img = zeros(4,4,obj.nSlices);
            vExtent = obj.voxSize;
            origins_wrld = obj.params.VisuCorePosition;
            %reshape orient matrix so basis for frame n is in rows of
            %(:,:,n)
            orients = permute(reshape(obj.params.VisuCoreOrientation',3,3,[]),[2 1 3]);
            %orients = reshape(obj.params.VisuCoreOrientation.',3,3,[]);
            for slice = 1:obj.nSlices
                upper = diag(vExtent);
                subOrig = origins_wrld(slice,:);
                origin_img = orients(:,:,slice)*subOrig(:);
                aMats_img(:,:,slice) = [upper,origin_img(:);0,0,0,1];
            end
        end

        function aMats_wrld = get.affMats_wrld(obj)
            %get affine matrix stack from (indexed space) -> (world coords)
            %nFrames = obj.params.VisuCoreFrameCount;
            aMats_wrld = zeros(4,4,obj.nSlices);
            %reshape orient matrix so basis for frame n is in rows of
            %(:,:,n)
            orients = permute(reshape(obj.params.VisuCoreOrientation',3,3,[]),[2 1 3]);
            %orients = reshape(obj.params.VisuCoreOrientation.',3,3,[]);
            aMats_img = obj.affMats_img;
            for slice = 1:obj.nSlices
                affOrient = [orients(:,:,slice),zeros(3,1);0,0,0,1];
                aMats_wrld(:,:,slice) = affOrient'*aMats_img(:,:,slice);
            end
        end

        function visualizeSlices(obj,opts)
            arguments
                obj
                opts.thresh = 0;
                opts.focSlice = [];
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
            colormap(ax,obj.cmap);
            [xs,ys,zs] = obj.getMapping(obj.affMats_wrld);
            thresh = opts.thresh;
            for slice = 1:obj.nSlices
                
                xs_frame = squeeze(xs(:,:,:,slice));
                ys_frame = squeeze(ys(:,:,:,slice));
                zs_frame = squeeze(zs(:,:,:,slice));
                frameData = squeeze(sum(obj.data(:,:,:,:,slice),1));
                frameData(frameData<thresh) = NaN;
                m = mesh(ax,xs_frame,ys_frame,zs_frame,frameData,'FaceColor','interp');
                if ~isempty(opts.focSlice)
                    if isequal(opts.focSlice,slice)
                        m = mesh(ax,xs_frame,ys_frame,zs_frame,'EdgeColor','r','FaceColor','r','FaceAlpha',0.2,'EdgeAlpha',0.2);
                    end
                end
                set(m,'AlphaData',frameData);
            end
            view(ax,3);

        end

        function showFrame(obj,frame)
            [xs,ys,~] = obj.getMapping(obj.affMats_img);
            xs_frame = squeeze(xs(:,:,:,frame));
            ys_frame = squeeze(ys(:,:,:,frame));
            frameData = squeeze(sum(obj.data(:,:,:,1,frame),1));
            ax = axes(figure);
            imagesc(ax,xs_frame(:,1),ys_frame(1,:),frameData')
            colormap(ax,obj.cmap);
            set(ax,'YDir','normal');
            axis(ax,'image');
        end

        function showFocNav(obj)
            lbls = {'Freq','x','y','z'};
            [xs,ys,zs] = obj.getMapping(obj.affMats_img);
            xs = xs(:,1,1,1,1);
            ys = ys(1,:,1,1,1);
            zs = zs(1,1,:,1,1);
            axMaps = {1:size(obj.data,1),xs,ys,zs};
            if obj.nSlices>1
                lbls{end+1} = 'slice';
                axMaps{end+1} = 1:obj.nSlices;
            end
            if obj.nEchos>1
                lbls{end+1} = 'echo';
                axMaps{end+1} = 1:obj.nEchos;
            end
            if obj.nReps>1
                lbls{end+1} = 'reps';
                axMaps{end+1} = 1:obj.nReps;
            end
            ndFocNav(obj.data,"dimLbls",lbls,"intensityLbl",'MR Signal (a.u.)','axMaps',axMaps);

        end


        % function [xs,ys,zs] = getProjection(obj,affMat)
        %     [x_wrld, y_wrld, z_wrld] = obj.getMapping(obj.affMats_wrld);
        % 
        %     i_hat = squeeze(affMat(1:3,1));
        %     j_hat = squeeze(affMat(1:3,2));
        %     k_hat = squeeze(affMat(1:3,3));
        % 
        %     i_hat = i_hat / norm(i_hat);
        %     j_hat = j_hat / norm(j_hat);
        %     k_hat = k_hat / norm(k_hat);
        %     basisMat = [i_hat(:),j_hat(:),k_hat(:)];
        % 
        %     world_coords = [x_wrld(:),y_wrld(:),z_wrld(:)];
        %     new_coords = world_coords / basisMat; %/ operator used to account for non-orthogonal bases
        %     sMatSize = obj.spatMatSize;
        %     Nx = sMatSize(1);
        %     Ny = sMatSize(2);
        %     Nz = sMatSize(3);
        %     xs = reshape(new_coords(:,1), Nx, Ny, Nz, obj.nSlices);
        %     ys = reshape(new_coords(:,2), Nx, Ny, Nz, obj.nSlices);
        %     zs = reshape(new_coords(:,3), Nx, Ny, Nz, obj.nSlices);
        % end

        function [xs,ys,zs] = getMapping(obj,affMats)
            %get spatial coordinates for the acquisition mapped according
            %to affine matrix stack
            sMatSize = obj.spatMatSize;
            if size(affMats,3)==1
                affMats = repmat(affMats,[1,1,obj.nSlices]);
            end
            if size(affMats,3)~=obj.nSlices
                error(['ERROR: Affine matrix with size(dim3)=%d ' ...
                    'incorrect for %d frames.'],size(affMats,3),obj.nSlices);
            end
            Nx = sMatSize(1);
            Ny = sMatSize(2);
            Nz = sMatSize(3);
            [i, j, k] = ndgrid(0:Nx-1, 0:Ny-1, 0:Nz-1); 
            coords = [i(:)'; j(:)'; k(:)'; ones(1, numel(i))];
            xs = zeros(Nx,Ny,Nz,obj.nSlices);
            ys = zeros(Nx,Ny,Nz,obj.nSlices);
            zs = zeros(Nx,Ny,Nz,obj.nSlices);
            for slice = 1:obj.nSlices
                frameCoords = affMats(:,:,slice)*coords;
                xs(:,:,:,slice) = reshape(frameCoords(1,:), Nx, Ny, Nz);
                ys(:,:,:,slice) = reshape(frameCoords(2,:), Nx, Ny, Nz);
                zs(:,:,:,slice) = reshape(frameCoords(3,:), Nx, Ny, Nz);
            end
        end

    end
end
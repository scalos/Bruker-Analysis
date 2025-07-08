classdef mrPlot < handle

    properties
        data
        ax
        axMaps
        prefs
        type
        shape
    end

    methods
        function obj = mrPlot(type,data,ax,axMaps,prefs)
            arguments
                type {mustBeMember(type,{'line',...
                                         'line_stack',...
                                         'image',...
                                         'volume'})}
                data;
                ax matlab.graphics.axis.Axes = axes('Parent',figure('Visible',false),'Visible','off');
                axMaps = {};
                prefs.style {mustBeMember(prefs.style,{'structural','functional'})} = 'functional';
                prefs.cmap = [];
                prefs.mode {mustBeMember(prefs.mode,{'abs','real','imag'})} = 'abs';
            end
            obj.type = type;
            obj.ax = ax;
            
            obj.data = squeeze(data);
            
            if ~obj.validType(type)
                error('Data size (%s) does not match plot type (%s)',mat2str(size(obj.data)),obj.type);
            end

            if size(axMaps)<=size(obj.data)
                obj.axMaps = repmat({[]},size(obj.data));
                for idx = 1:numel(axMaps)
                    obj.axMaps{idx} = axMaps{idx};
                end
            else
                error('Axes mapping matrix size must match data dimensions!');
            end
            obj.prefs = prefs;
            
        end

        function passed = validType(obj,type)
            passed = false;
            switch type
                case 'line'
                    if sum(size(obj.data)~=1)==1
                        passed = true;
                    end
                case {'line_stack','image'}
                    if numel(size(obj.data))==2
                        passed = true;
                    end
                case 'volume'
                    if numel(size(obj.data))==3
                        passed = true;
                    end
            end
        end

        function show(obj)
            if ~isvalid(obj.ax)
                obj.ax = axes(figure);
            end
            data_ = eval(sprintf('%s(obj.data)',obj.prefs.mode));
            switch obj.type
                case 'line'
                    if ~isempty(obj.axMaps{1})
                        plot(obj.ax,obj.axMaps{1},data_);
                    else
                        plot(obj.ax,data_);
                    end
                case 'image'
                    imagesc(obj.ax,obj.axMaps{1},obj.axMaps{2},data_');
                    if ~isempty(obj.prefs.cmap)
                        if strcmp(obj.prefs.style,'structural')
                            colormap(obj.ax,'gray');
                        else
                            colormap(obj.ax,'parula');
                        end
                    end
                    axis(obj.ax,'on');
                    axis(obj.ax,"image");
                    set(obj.ax,'XTick',[],'YTick',[])
                    axis(obj.ax,'tight');
                case 'line_stack'
                    waterfall(obj.ax,data_');
                case 'volume'
                    
                    [x,y,z] = ndgrid(1:size(obj.data,1),1:size(obj.data,2),1:size(obj.data,3));
                    v = data_(:);
                    v = v - min(v);        
                    v = v / max(v);
                    
                    sizes = 0.1 + 50 * v;
                    
                    scatter3(obj.ax,x(:),y(:),z(:),sizes,data_(:),'filled');
                    
                    %volshow(data_,'Colormap',parula(numel(data_)));
            end
            set(obj.ax,'Visible',true);
            set(obj.ax.Parent,'Visible',true);
        end
    end
end
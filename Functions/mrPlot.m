function mrPlot(type,data,ax,axMaps,prefs)
    arguments
        type {mustBeMember(type,{'line',...
                                 'line_stack',...
                                 'image',...
                                 'volume',...
                                 'spiral'})}
        data;
        ax = axes('Parent',figure('Visible',false),'Visible','off');
        axMaps = {};
        prefs.style {mustBeMember(prefs.style,{'struc','func'})} = 'func';
        prefs.cmap = [];
        prefs.mode {mustBeMember(prefs.mode,{'abs','real','imag'})} = 'abs';
    end
    data = squeeze(data);
    passed = false;
    switch type
        case {'line','spiral'}
            if sum(size(data)~=1)==1
                passed = true;
            end
        case {'line_stack','image'}
            if numel(size(data))==2
                passed = true;
            end
        case 'volume'
            if numel(size(data))==3
                passed = true;
            end
    end
    if ~passed
        error('Data size (%s) does not match plot type (%s)',mat2str(size(data)),type);
    end

    if size(axMaps)<=size(data)
        axMaps_ = repmat({[]},numel(size(data)));
        for idx = 1:numel(axMaps)
            axMaps_{idx} = axMaps{idx}(:);
        end
    else
        error('Axes mapping matrix size must match data dimensions!');
    end
        
    data_ = eval(sprintf('%s(data)',prefs.mode));
    switch type
        case 'line'
            if ~isempty(axMaps_{1})
                plot(ax,axMaps_{1},data_);
            else
                plot(ax,data_);
            end
        case 'spiral'
            %pass
        case 'image'
            imagesc(ax,axMaps_{1},axMaps_{2},data_');
            if ~isempty(prefs.cmap)
                if strcmp(prefs.style,'struc')
                    colormap(ax,'gray');
                else
                    colormap(ax,'parula');
                end
            end
            axis(ax,'on');
            axis(ax,"image");
            set(ax,'XTick',[],'YTick',[])
            axis(ax,'tight');
        case 'line_stack'
            xMap = axMaps_{1};
            yMap = axMaps_{2};
            if isempty(xMap)
                xMap = 1:size(data_,1);
            end
            if isempty(yMap)
                yMap = 1:size(data_,2);
            end
            [X,Y] = meshgrid(xMap,yMap);
            waterfall(ax,X,Y,data_');
        case 'volume'
            
            [x,y,z] = ndgrid(1:size(data,1),1:size(data,2),1:size(data,3));
            v = data_(:);
            v = v - min(v);        
            v = v / max(v);
            
            sizes = 0.1 + 50 * v;
            
            scatter3(ax,x(:),y(:),z(:),sizes,data_(:),'filled');
            
            %volshow(data_,'Colormap',parula(numel(data_)));
    end
    set(ax,'Visible',true);
    set(ax.Parent,'Visible',true);
    
end

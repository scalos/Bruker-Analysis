function whiskerPlot(data, opts)
    arguments
        data (:,:);  % group data is in columns
        opts.ax = [];
        opts.groupLabels = [];
        opts.dataSpread = 1;
        opts.boxColors = [];             % nGroups x 3 RGB array
        opts.showData = true;
        opts.markerColor = [0, 0, 0];
        opts.markerSize = 20;
        opts.markerStyle = 'o';
        opts.markerFilled = false;
        opts.legend = true;
    end

    if isempty(opts.ax)
        fig = figure;
        ax = axes(fig);
    else
        ax = opts.ax;
    end
    hold(ax, 'on');

    nGroups = size(data, 2);

    % Default boxColors if not provided
    if isempty(opts.boxColors)
        opts.boxColors = lines(nGroups);  % MATLAB colormap
    end
    
    %opts.boxColors = [255,126,124;255,213,129]/255;

    boxes = gobjects(nGroups,1);

    for i = 1:nGroups
        y = data(:,i);
        x = repmat(i, size(y));  % fixed X position for group

        boxes(i) = boxchart(ax, x, y,'BoxFaceColor', opts.boxColors(i,:), ...
                                     'BoxFaceAlpha',1,'BoxEdgeColor','k','MarkerSize',opts.markerSize);
    end

    % Apply group labels
    if ~opts.legend
        if ~isempty(opts.groupLabels)
            xticks(ax, 1:nGroups);
            xticklabels(ax, opts.groupLabels);
        end
    else
       lgnd = legend(ax,opts.groupLabels,'location','southoutside', ...
                                  'Orientation','horizontal');
       lgnd.Box = 'off';
       lgnd.AutoUpdate = 'off';       

    end
    nPoints = size(data,1);
    if opts.showData
        for idx = 1:size(data,2)
            xRange = linspace(double(boxes(idx).XData(idx))-boxes(idx).BoxWidth*opts.dataSpread/2,...
                      double(boxes(idx).XData(idx))+boxes(idx).BoxWidth*opts.dataSpread/2,nPoints);
            if opts.markerFilled
                scatter(ax,xRange,data(:,idx),opts.markerSize,opts.markerColor,opts.markerStyle,'filled');
            else
                scatter(ax,xRange,data(:,idx),opts.markerSize,opts.markerColor,opts.markerStyle);
            end
        end
    end
    set(ax,'XTick',[]);
    ax.Parent.Color = [1,1,1];
    set(ax,'LineWidth',2);
    hold(ax,'off');
end
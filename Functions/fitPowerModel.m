function [fits,gofs,outputs,msgs] = fitPowerModel(data,xData,opts)
    arguments
        data
        xData = [];
        opts.showFits = false
    end
    if isempty(xData)
        xData = repmat((1:size(data,1))',[1,size(data,2)]);
    end
    if size(xData)~=size(data)
        error('Size of x-data must match data size!');
    end
    fits = cell(size(data,2),1);
    gofs = cell(size(fits));
    outputs = cell(size(fits));
    msgs = cell(size(fits));
    for series = 1:size(data,2)
        series_data = data(:,series);
        series_xData = xData(:,series);
        [fits{series},gofs{series},outputs{series},msgs{series}] = ...
            fit(series_xData,series_data,'power2');
    end
    if opts.showFits
        ax = axes(figure);
        for idx = 1:numel(fits)
            if isvalid(ax)
                plot(ax,fits{idx},xData(:,idx),data(:,idx))
                pause(1);
            end
        end
    end
end
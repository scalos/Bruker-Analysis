classdef LinkedPlot < dynamicprops
    properties (Access = private)
        PlotFunctionMap % propName -> cell array of {axesHandle, plotFcn, opts}
        Listeners = {}  % prevent listener GC
    end

    methods
        function obj = LinkedPlot()
            obj.PlotFunctionMap = containers.Map();
        end

        function linkPlot(obj, propName, ax, plotFcn, opts)
            arguments
                obj
                propName (1,:) char
                ax {mustBeA(ax, 'matlab.graphics.axis.Axes')}
                plotFcn (1,1) function_handle
                opts.mode {mustBeMember(opts.mode,{'real', ...
                                                   'abs', ...
                                                   'imag'})}
                opts.xAx;
            end

            % Add dynamic property if needed
            if ~isprop(obj, propName)
                p = addprop(obj, propName);
                p.SetObservable = true;
            end

            % Initialize map entry if not present
            if ~isKey(obj.PlotFunctionMap, propName)
                obj.PlotFunctionMap(propName) = {};
                % Add a listener for this property
                l = addlistener(obj, propName, 'PostSet', ...
                    @(src, evt) obj.callPlotFunctions(propName));
                obj.Listeners{end+1} = l;
            end

            % Replace or append the plot function for this axes
            entries = obj.PlotFunctionMap(propName);
            found = false;

            % Search and replace if the axes already exists
            for i = 1:numel(entries)
                if isvalid(entries{i}{1}) && entries{i}{1} == ax
                    entries{i} = {ax, plotFcn, opts};
                    found = true;
                    break;
                end
            end

            % If not found, append
            if ~found
                entries{end+1} = {ax, plotFcn, opts};
            end

            % Clean up invalid axes
            entries = entries(cellfun(@(e) isvalid(e{1}), entries));

            % Save updated list
            obj.PlotFunctionMap(propName) = entries;

            % Automatic initialization
            if isprop(obj, propName)
                val = obj.(propName);
                if ~isempty(val)
                    plotFcn(obj, ax, val, opts);
                end
            end
        end

        function updateLinkedPlots(obj)
            propNames = obj.PlotFunctionMap.keys;
            for idx = 1:numel(propNames)
                obj.callPlotFunctions(propNames{idx});
            end
        end

        function callPlotFunctions(obj, propName)
            if isKey(obj.PlotFunctionMap, propName)
                val = obj.(propName);
                entries = obj.PlotFunctionMap(propName);
                newEntries = {};
                for k = 1:numel(entries)
                    ax = entries{k}{1};
                    plotFcn = entries{k}{2};
                    opts = entries{k}{3};
                    if isvalid(ax)
                        try
                            xl = xlim(ax);
                            yl = ylim(ax);
                            try zl = zlim(ax); catch, zl = []; end
        
                            % Pass opts as a single struct argument to plotFcn
                            plotFcn(obj, ax, val, opts);
                            zoom(ax,'reset');
        
                            if isvalid(ax)
                                xlim(ax, xl);
                                ylim(ax, yl);
                                if ~isempty(zl)
                                    try zlim(ax, zl); catch, end
                                end
                            end
                            newEntries{end+1} = {ax, plotFcn, opts}; %#ok<AGROW>
                        catch ME
                            warning('LinkedPlot:PlotError', ...
                                'Error plotting property "%s": %s', propName, ME.message);
                        end
                    end
                end
                % Update with only valid axes
                obj.PlotFunctionMap(propName) = newEntries;
            end
        end
    end
end

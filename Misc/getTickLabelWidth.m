function tickWidthNorm = getTickLabelWidth(ax)
    if nargin < 1
        ax = gca;
    end

    drawnow; % ensure tick labels are rendered

    % Store original units
    originalFigUnits = get(ancestor(ax, 'figure'), 'Units');
    originalAxUnits  = get(ax, 'Units');

    % Temporarily set to 'pixels'
    fig = ancestor(ax, 'figure');
    set(fig, 'Units', 'pixels');
    set(ax,  'Units', 'pixels');

    % Get figure and axis pixel sizes
    figPos = get(fig, 'Position');  % [x y w h]
    axPos  = get(ax, 'Position');

    % Use longest Y-tick label for width estimate
    labels = get(ax, 'YTickLabel');
    if isempty(labels)
        tickWidthNorm = 0;
    else
        % Create invisible text object in axis coordinates
        h = text(ax, 'String', labels{1}, ...
                 'Units', 'pixels', ...
                 'Visible', 'off', ...
                 'FontSize', ax.FontSize, ...
                 'FontName', ax.FontName);
        extent = get(h, 'Extent');  % [x y w h]
        tickWidth_pix = extent(3);
        delete(h);

        % Convert to normalized figure units
        tickWidthNorm = tickWidth_pix / figPos(3);
    end

    % Restore original units
    set(fig, 'Units', originalFigUnits);
    set(ax,  'Units', originalAxUnits);
end

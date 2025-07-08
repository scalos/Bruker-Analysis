function overlayGrid(ax,gridSize,cellSize,opts)
    arguments
        ax
        gridSize
        cellSize
        opts.visRows = [];
        opts.visCols = [];
        opts.innerRGB;
        opts.outerRGB
        opts.innerLW;
        opts.outerLW;
    end
    rows = 0:gridSize(1);
    if ~isempty(opts.visRows)
        rows = opts.visRows-1;
        rows(end+1) = rows(end)+1;
    end
    cols = 0:gridSize(2);
    if ~isempty(opts.visCols)
        cols = opts.visCols-1;
        cols(end+1) = cols(end)+1;
    end
    for row = 0:gridSize(1)
        if find(rows==row)
            if find(rows==row)==1 || find(rows==row) == length(rows)
                lw = opts.outerLW;
                rgb = opts.outerRGB;
            else
                lw = opts.innerLW;
                rgb = opts.outerRGB;
            end
            hold(ax,'on');
            plot(ax,[min(cols)*cellSize(2);max(cols)*cellSize(2)], ...
                [row*cellSize(1);row*cellSize(1)],Color=rgb,LineWidth=lw);
            hold(ax,'off');
        end
    end
    
    for col = 0:gridSize(2)
        if ~isempty(cols)
            if find(cols==col)
                if find(cols==col)==1 || find(cols==col) == length(cols)
                    lw = opts.outerLW;
                    rgb = opts.outerRGB;
                else
                    lw = opts.innerLW;
                    rgb = opts.outerRGB;
                end
                hold(ax,'on');
                plot(ax,[col*cellSize(2);col*cellSize(2)], ...
                    [min(rows)*cellSize(1);max(rows)*cellSize(1)], ...
                    Color=rgb,LineWidth=lw);
                hold(ax,'off');
            end
        else    
            xline(ax,col*cellSize(2),Color=opts.innerRGB,LineWidth=opts.innerLW);
        end
    end



end
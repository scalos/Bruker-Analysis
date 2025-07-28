function adjustCmap(cmap,nPts,startPos,opts)
    arguments
        cmap
        nPts = 2
        startPos = [];
        opts.Color = [0,0,0];
        opts.dispAx = [];
    end
    if ~isempty(opts.dispAx)&&isvalid(opts.dispAx)
        ax = opts.dispAx;
    else
        ax = axes(figure);
    end
    cHeight = height(cmap);
    cGrid = reshape(repmat(cmap,[cHeight,1]),[cHeight,cHeight,3]);
    imagesc(ax,linspace(0,1,cHeight),linspace(0,1,cHeight),cGrid);
    set(ax,'YDir','normal');
    axis(ax,'off');
    if isempty(startPos)
        xPos = linspace(0,1,nPts+2);
        yPos = linspace(0,1,nPts+2);
    else
        xPos = startPos(:,1);
        yPos = startPos(:,2);
    end
    pointTag = 'controlPt';
    %left Point:
    pt = drawpoint(ax,'Position',[xPos(1),yPos(1)], ...
                      'Tag',pointTag,...
                      'Color',opts.Color);
    addlistener(pt,'ROIMoved',@updateDA);
    addlistener(pt,'MovingROI',@drawLine);
    for idx = 2:nPts+1
        pos = [xPos(idx),yPos(idx)];
        pt = drawpoint(ax,'Position',pos, ...
                          'Tag',pointTag,...
                          'Color',opts.Color);
        addlistener(pt,'ROIMoved',@updateDA);
        addlistener(pt,'MovingROI',@drawLine);
    end
    pt = drawpoint(ax,'Position',[1,1], ...
                      'Tag',pointTag,...
                      'Color',opts.Color);
    addlistener(pt,'ROIMoved',@updateDA);
    addlistener(pt,'MovingROI',@drawLine);
    updateDA;
    drawLine;
    
    

    function drawLine(~,~)
        if isvalid(ax)
            [~,posSorted] = getPosSorted;
            xVals = linspace(0,1,100);
            spln = interp1(posSorted(:,1),posSorted(:,2),xVals,"pchip");
            delete(findobj(ax.Children,'Tag','fitLine'));
            hold(ax,"on");
            plot(ax,xVals,spln,'Color',opts.Color,'Tag','fitLine');
            hold(ax,"off");
            axChldn = get(ax,'Children');
            if numel(axChldn)>nPts+2
                set(ax,'Children',axChldn([2:nPts+3,1,nPts+4:numel(axChldn)]));
            else
                set(ax,'Children',axChldn([2:nPts+2,1]));
            end
            ylim(ax,[0,1]);
            getCmap;
        end
    end

    function [pts,pos] = getPosSorted()
         allPts = findobj(ax.Children,'Tag',pointTag);
        newPos = zeros(numel(allPts),2);
        for ind = 1:numel(allPts)
            newPos(ind,:) = allPts(ind).Position;
        end
        [~,inds] = sort(newPos(:,1));
        pos = newPos(inds,:);
        pts = allPts(inds);
    end

    function getCmap()
        [~,pos_sorted] = getPosSorted;
        line = interp1(pos_sorted(:,1),pos_sorted(:,2),linspace(0,1,height(cmap)),"pchip");
        try
            newCmap = interp1(line,cmap,linspace(0,1,height(cmap)));
            colormap(ax,newCmap);
            colorbar(ax);
        catch
            % TODO: fix
            % Likely caused by non-unique sample points => ok to pass
        end
    end
   

    function updateDA(~,~)
        if isvalid(ax)
            allPts_sorted = getPosSorted;
            set(allPts_sorted(1), ...
               'DrawingArea',[0,0,eps,allPts_sorted(2).Position(2)-eps]);
            set(allPts_sorted(end), ...
               'DrawingArea',[1,allPts_sorted(end-1).Position(2)+eps,eps,1-allPts_sorted(end-1).Position(2)+eps]);

            for ptInd = 2:numel(allPts_sorted)-1
                prevPos = allPts_sorted(ptInd-1).Position;
                nextPos = allPts_sorted(ptInd+1).Position;
                newDA = [prevPos(1)+eps,prevPos(2)+eps,nextPos(1)-prevPos(1)-2*eps,nextPos(2)-prevPos(2)-2*eps];
                set(allPts_sorted(ptInd),'DrawingArea',newDA);
            end
        end
    end

    
end
function specGrid(spectra, bkgdImg, opts)
    arguments
        spectra (:,:,:) double
        bkgdImg (:,:) double = [];
        opts.mode {mustBeMember(opts.mode, {'real', 'imag', 'abs'})} = 'real'
        opts.border logical = true
        opts.tPose = false;
        opts.borderColor = 'w'
        opts.borderLW = 3;
        opts.grayClim = [];
        opts.pltRBG = [1,1,1];
        opts.pltLW = 1;
        opts.baseCmap = 'gray';
    end
    if isempty(bkgdImg)
        bkgdImg = zeros(size(spectra,2),size(spectra,3));
    end
    bkgdImg = bkgdImg';
    [nPoints, dimX, dimY] = size(spectra);
    
    [imgH, imgW] = size(bkgdImg);
    
    % Create figure and single axes
    fig = figure('Units', 'normalized');
    ax = axes(fig);
    ax.Position = [0,0,1,1];
    imagesc(bkgdImg, 'Parent', ax);
    axis(ax, 'image');
    axis(ax, 'off');
    xlim(ax, [0, imgW]);
    ylim(ax, [0, imgH]);
    hold(ax, 'on');
    colormap(ax, opts.baseCmap);
    if ~isempty(opts.grayClim)
        clim(ax,opts.grayClim);
    end
    
    % Tile sizes in image coordinates
    tileW = (imgW / dimX);
    tileH = (imgH / dimY);
    
    % normalize all spectra for consistent scaling
    globalMin = inf;
    globalMax = -inf;
    
    for x = 1:dimX
        for y = 1:dimY
            spec = spectra(:, x, y);
            switch opts.mode
                case 'real', ydata = real(spec);
                case 'imag', ydata = imag(spec);
                case 'abs',  ydata = abs(spec);
            end
            globalMin = min(globalMin, min(ydata));
            globalMax = max(globalMax, max(ydata));
        end
    end
    
    % Scale factor to fit spectrum vertically into tile
    yRange = globalMax - globalMin;
    if yRange == 0, yRange = 1; end  % prevent division by zero
    
    % Plot each spectrum
    for x = 1:dimX
        for y = 1:dimY
            % Get tile position in image coordinates
            left   = (x - 1) * tileW+0.5;
            bottom = (dimY - y) * tileH+0.5;
    
            x0 = left;
            x1 = left + tileW;
            y0 = bottom;
            y1 = bottom + tileH;
    
            % Spectrum data
            spec = spectra(:, x, dimY-y+1);
            switch opts.mode
                case 'real', ydata = real(spec);
                case 'imag', ydata = imag(spec);
                case 'abs',  ydata = abs(spec);
            end
    
            % Normalize spectrum to [0, 1]
            yScaled = (ydata - globalMin) / yRange;
    
            % Map to image coordinates
            xVals = linspace(x0, x1, nPoints);
            yVals = y1 - yScaled * (y1 - y0);
    
            % Plot spectrum
            plot(ax, xVals, flip(yVals), 'LineWidth', opts.pltLW,'Color',opts.pltRBG);
    
            % Optional border
            if opts.border
                rectangle('Position', [left, bottom, tileW, tileH], ...
                          'EdgeColor', opts.borderColor, ...
                          'LineWidth', opts.borderLW, ...
                          'Parent', ax);
            end
        end
    end
    
    hold(ax, 'off');
end

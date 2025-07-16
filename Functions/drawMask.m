function [totalMask,exitType] = drawMask(ax,maskSize,opts)
    arguments
        ax,
        maskSize (1,2)
        opts.subColor (1,3) = [0.6350 0.0780 0.1840];
        opts.addColor (1,3) = [0.4660 0.6740 0.1880];
        opts.maskColor (1,3) = [0.8,0.5,0];
        opts.maskTrans = 0.4;

    end
    if ~isvalid(ax)
        error('Axes handle must be valid!')
    end
    totalMask = [];
    working = true;
    layers = {};
    subColor = opts.subColor;
    addColor = opts.addColor;
    maskColor = opts.maskColor;
    
    function totalMask = getTotalMask(layers)
        totalMask = layers(:,:,1);
        for ii = 1:size(layers,3)-1
            totalMask = totalMask+layers(:,:,ii+1);
            totalMask(totalMask<0) = 0;
            totalMask(totalMask>1) = 1;
        end
    end
    function cleanLayers()
        newLayers = {};
        for idx = 1:numel(layers)
            layerRoi = layers{idx}.roi;
            if isvalid(layerRoi)
                newLayers{end+1} = layers{idx}; %#ok Agrow
            end
        end
        layers = newLayers;
    end

    function cleanup()
        cleanLayers
        for idx = 1:numel(layers)
            delete(layers{idx}.roi)
        end
        if ~isempty(maskImg)
            delete(maskImg)
        end
    end

    maskImg = [];
    while working
        res = input('->','s');
        roi = [];
        if ~isempty(res)
            if strcmp(res(1),'+')||strcmp(res(1),'-')
                sign = eval(sprintf('%s1',res(1)));
                if sign>0
                    color = addColor;
                else
                    color = subColor;
                end
            end
        end
        switch res
            case {'+free','-free'}
                disp('Start drawing freehand polygon:')
                roi = drawpolygon(ax,'Color',color);
            case {'+oval','-oval'}
                disp('Start drawing ellipse:')
                roi = drawellipse(ax,'Color',color);
            case {'+rect','-rect'}
                disp('Start drawing rectangle:')
                roi = drawrectangle(ax,'Color',color,'FaceAlpha',0);
            case 'help'
                options = struct('Freehand','+free, -free', ...
                                 'Ellipse','+oval, -oval', ...
                                 'Rectangle','+rect, -rect', ...
                                 'apply','end session with exitType = 1', ...
                                 'esc','end session with exitType = 0');

                fprintf('Valid Options:\n%s',formattedDisplayText(options))
            case 'esc'
                totalMask = totalMask';
                cleanup;
                exitType = 0;
                return
            case 'apply'
                totalMask = totalMask';
                cleanup;
                exitType = 1;
                return
            case ''
                %do nothing but don't display message
            otherwise
                disp('Unrecognized command, use "help" for options.');
        end
        if ~isempty(roi)
            layers{end+1} = struct('roi',roi,'sign',sign); %#ok agrow
        end
        cleanLayers;
        totalMask = [];
        if ~isempty(maskImg)
            delete(maskImg)
        end
        if ~isempty(layers)
            maskLayers = zeros(maskSize(1),maskSize(2),numel(layers));
            for ind = 1:numel(layers)
                roi = layers{ind}.roi;
                sign = layers{ind}.sign;
                newMask = createMask(roi,maskSize(1),maskSize(2));
                newMask = newMask*sign;
                maskLayers(:,:,ind) = newMask;
            end
            totalMask = getTotalMask(maskLayers);
            hold(ax,'on')
            TC_color = repmat(maskColor,size(totalMask));
            totalMaskTC = ind2rgb(uint8(totalMask),TC_color);
            img = imagesc(ax,totalMaskTC);
            imgAlph = mask(repmat(opts.maskTrans,size(totalMask)),totalMask);
            set(img,'AlphaData',imgAlph);
            set(img,'AlphaDataMapping','none');
            hold(ax,'off');
            cldn = get(ax,'Children');
            perm = [2:1+size(maskLayers,3),1,size(maskLayers,3)+2:numel(cldn)];
            set(ax,'Children',cldn(perm))
            maskImg = img;
        end
    end
end
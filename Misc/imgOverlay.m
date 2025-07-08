function fig = imgOverlay(base,layer,varargin)
    if numel(size(base))>2||numel(size(layer))>2
        error('Input matrices must be 2 dimensional');
    end
    trans = 0.3;
    thresh = 0.33;
    shift = [0,0];
    for ind = 1:length(varargin)
        try
            lbl = string(varargin{ind});
        catch
            continue
        end
        switch lbl
            case 'trans'
                 trans = varargin{ind+1};
            case 'thresh'
                thresh = varargin{ind+1};
            case 'shiftUp'
                shift(1) = shift(1)+varargin{ind+1};
            case 'shiftDown'
                shift(1) = shift(1)-varargin{ind+1};
            case 'shiftLeft'
                shift(2) = shift(2)+varargin{ind+1};
            case 'shiftRight'
                shift(2) = shift(2)-varargin{ind+1};
        end
    end
    base = abs(squeeze(base));
    layer = abs(squeeze(layer));
    icol=imresize(layer,size(base));
    max_value = max(max(icol));
    icol=icol/max_value*255;
    % display transparency and signal threshold
    coltab = ind2rgb(uint8(icol),jet(256)); % use jet color, convert to RGB format, 256x256
    % transparency and threshold
    figure;
    subplot('Position',[0,0,1,1]); % avoid gray boundary around image
    imagesc(circshift(base', shift)); % [up-down, L-R]
    colormap('gray');
    axis('off');
    axis square;
    hold on; % data cursor only shows the second overlay image
    imh = imagesc(permute(coltab,[2,1,3]));
    imAlphaData = icol*0; % transparency mask
    imAlphaData(icol(:) >= (thresh*256)) = trans;
    set(imh,'AlphaData',imAlphaData)
    set(gca,'YDir','reverse')
    hold off
    fig = imh;
end
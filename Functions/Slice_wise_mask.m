function [mask_out] = Slice_wise_mask(baseMat,outputSize)
    assert(ndims(baseMat)==3,'ERROR: baseMat must only have 3 dimensions');

    mask_out = zeros(size(baseMat));
    working = true;
    ax = axes(figure);
    img = imagescND(permute(baseMat,[2,1,3]),"imagescArgs",{'Parent',ax});
    colormap(ax,'gray');
    axis(ax,'image');
    mask_img = gobjects(1);
    while working
        currSlice = getappdata(img,'ndParams_highDimInds');
        res = input(sprintf('slice [%d], (m,u,s,e):',currSlice),'s');
        if isvalid(mask_img)
            delete(mask_img);
        end
        switch res
            case 'help'
                fprintf(['Options:' ...
                        '\n\t m: start mask on current slice' ...
                        '\n\t u: update current slice' ...
                        '\n\t s: show existing mask for current slice' ...
                        '\n\t e: end session\n']);
            case 'm'
                currSlice = getappdata(img,'ndParams_highDimInds');
                fprintf('Create mask for slice %d:\n',currSlice);
                [sliceMask,flag] = drawMask(ax,size(baseMat,[1,2]));
                if flag==1
                    mask_out(:,:,currSlice) = sliceMask;
                end
            case {'u',''}
                %do nothing
            case 's'
                currSlice = getappdata(img,'ndParams_highDimInds');
                sliceMask = squeeze(mask_out(:,:,currSlice))';
                if sum(sliceMask)==0
                    fprintf('\tSlice %d mask is empty.\n',currSlice)
                else
                    hold(ax,'on');
                    maskTC = mat2TC(sliceMask,[0.2314,0.6667,0.1961]);
                    mask_img = imagesc(maskTC);
                    alph = ones(size(sliceMask));
                    alph(sliceMask==0) = 0;
                    alph(sliceMask==1) = 0.5;
                    set(mask_img,'AlphaData',alph);
                    hold(ax,'off');
                end
            case 'e'
                working = false;
            otherwise
                disp('Unrecognized command. Type "help" for options.');
        end
    end
    mask_out_rsz = zeros([outputSize,size(baseMat,3)]);
    for slc = 1:size(mask_out,3)
        mask_out_rsz(:,:,slc) = imresize(squeeze(mask_out(:,:,slc)),outputSize,'nearest');
    end
    mask_out = mask_out_rsz;
end
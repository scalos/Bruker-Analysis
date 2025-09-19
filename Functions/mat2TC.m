function TC = mat2TC(data,colormap)
    % Convert 2D matrix into true color array
    %
    % mat2TC(data,colormap)

    arguments
        data (:,:);
        colormap (:,3);
    end
    data = data/max(max(data));
    data = data*height(colormap);
    TC = ind2rgb(round(data),colormap);
end
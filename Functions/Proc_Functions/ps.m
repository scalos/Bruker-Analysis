function [data,phase] = ps(data,zeroOrder,pivotInd,firstOrder)
        arguments
            data
            zeroOrder; %deg
            pivotInd = [];
            firstOrder = []; %deg
        end
        if isempty(firstOrder)
            phase = repmat(zeroOrder,length(data),1);
        else
            phase = ((1:length(data))'-pivotInd)*firstOrder+zeroOrder;
        end
        data = data.*exp(1i*deg2rad(phase));
end
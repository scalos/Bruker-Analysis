function y = lorentz(x,loc,hwhm,height)
    y = 1 ./ (hwhm.*...
        (1+((x-loc)./hwhm).^2));
    y = y.*(height/max(y));
end